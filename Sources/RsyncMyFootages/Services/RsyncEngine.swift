import Foundation

/// Thread-safe mutable state for rsync output parsing
private final class RsyncOutputState: @unchecked Sendable {
    private let lock = NSLock()
    var lineBuffer = ""
    var progress = SyncProgress()

    func withLock<T>(_ body: (inout String, inout SyncProgress) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&lineBuffer, &progress)
    }
}

/// Wraps rsync execution via Foundation.Process with progress tracking
actor RsyncEngine {
    private var currentProcess: Process?
    private var isCancelled = false

    struct SyncResult: Sendable {
        let filesTransferred: Int
        let totalBytes: Int64
        let duration: TimeInterval
    }

    struct FileListing: Sendable {
        let files: [(name: String, size: Int64)]
        var totalFiles: Int { files.count }
        var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    }

    /// Cancel the current sync operation
    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
    }

    /// Phase 1: Dry-run to get file list and total sizes
    func dryRun(source: URL, destination: URL) async throws -> FileListing {
        let args = [
            "-r",
            "--dry-run",
            "--out-format=%n %l",
        ] + excludeArgs() + [
            source.path.hasSuffix("/") ? source.path : source.path + "/",
            destination.path.hasSuffix("/") ? destination.path : destination.path + "/",
        ]

        let output = try await runRsync(args: args)
        var files: [(String, Int64)] = []

        for line in output.split(separator: "\n") {
            if let parsed = RsyncProgressParser.parseDryRunLine(String(line)) {
                if case .dryRunFile(let name, let size) = parsed {
                    files.append((name, size))
                }
            }
        }

        return FileListing(files: files)
    }

    /// Phase 2: Actual sync with progress reporting
    func sync(
        source: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (SyncProgress) -> Void
    ) async throws -> SyncResult {
        isCancelled = false
        let startTime = Date()

        // Detect if source is a file or directory
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir)

        let sourcePath: String
        let destPath: String
        if isDir.boolValue {
            // Directory: trailing slash means "copy contents"
            sourcePath = source.path.hasSuffix("/") ? source.path : source.path + "/"
            destPath = destination.path.hasSuffix("/") ? destination.path : destination.path + "/"
        } else {
            // Single file: no trailing slash, destination is a directory
            sourcePath = source.path
            destPath = destination.path.hasSuffix("/") ? destination.path : destination.path + "/"
        }

        let args = [
            "-t",
            "--progress",
            "--itemize-changes",
        ] + (isDir.boolValue ? ["-r"] : []) + excludeArgs() + [
            sourcePath,
            destPath,
        ]

        let process = Process()
        self.currentProcess = process

        process.executableURL = URL(fileURLWithPath: Constants.rsyncPath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // discard stderr

        let state = RsyncOutputState()
        let handle = pipe.fileHandleForReading
        let progressCallback = progressHandler

        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

            state.withLock { lineBuffer, progress in
                lineBuffer += chunk
                let lines = lineBuffer.split(separator: "\n", omittingEmptySubsequences: false)

                for i in 0..<(lines.count - 1) {
                    let line = String(lines[i])
                    if let parsed = RsyncProgressParser.parse(line) {
                        switch parsed {
                        case .fileStart(let filename):
                            progress.currentFile = filename
                        case .progress(let bytes, _, let xferNum, _, let total):
                            progress.bytesTransferred += bytes
                            progress.filesTransferred = xferNum
                            progress.totalFiles = total
                            progressCallback(progress)
                        case .dryRunFile:
                            break
                        }
                    }
                }

                lineBuffer = String(lines.last ?? "")
            }
        }

        try process.run()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        handle.readabilityHandler = nil
        self.currentProcess = nil

        guard !isCancelled else {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            throw SyncError.rsyncFailed(
                code: Int(process.terminationStatus),
                message: "rsync exited with code \(process.terminationStatus)"
            )
        }

        let finalProgress = state.withLock { _, progress in progress }
        let duration = Date().timeIntervalSince(startTime)
        return SyncResult(
            filesTransferred: finalProgress.filesTransferred,
            totalBytes: finalProgress.bytesTransferred,
            duration: duration
        )
    }

    // MARK: - Private

    private func excludeArgs() -> [String] {
        Constants.rsyncExcludes.flatMap { ["--exclude", $0] }
    }

    private func runRsync(args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Constants.rsyncPath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw SyncError.rsyncFailed(
                code: Int(process.terminationStatus),
                message: "rsync dry-run failed with code \(process.terminationStatus)"
            )
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum SyncError: LocalizedError {
    case rsyncFailed(code: Int, message: String)
    case destinationNotAvailable(String)
    case sourceNotMounted(String)

    var errorDescription: String? {
        switch self {
        case .rsyncFailed(_, let message): return message
        case .destinationNotAvailable(let path): return "Destination not available: \(path)"
        case .sourceNotMounted(let path): return "Source not mounted: \(path)"
        }
    }
}
