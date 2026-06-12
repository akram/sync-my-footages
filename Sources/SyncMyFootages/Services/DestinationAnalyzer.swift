import Foundation

/// Analyzes a destination to find existing DJI files and compare with source
enum DestinationAnalyzer {
    /// Result of analyzing one source file against a destination
    enum FileStatus: Sendable {
        /// File not found on destination — needs to be copied
        case new
        /// File exists at the expected pattern path — skip
        case alreadyAtCorrectPath(String)
        /// File exists but at a different path — user decides
        case existsElsewhere(currentPath: String, expectedPath: String)
    }

    struct AnalysisResult: Sendable {
        let newFiles: [(file: FootageFile, destPath: String)]
        let alreadyCopied: [(file: FootageFile, path: String)]
        let misplaced: [(file: FootageFile, currentPath: String, expectedPath: String)]

        var newCount: Int { newFiles.count }
        var skippedCount: Int { alreadyCopied.count }
        var misplacedCount: Int { misplaced.count }
        var newBytes: Int64 { newFiles.reduce(0) { $0 + $1.file.fileSize } }
    }

    /// Scan a destination for existing DJI files and build a SHA256 → path index
    /// Uses file size as a fast pre-filter before hashing
    static func analyze(
        sourceFiles: [FootageFile],
        destination: URL,
        deviceType: DJIDeviceType,
        pattern: String,
        progressHandler: @escaping @Sendable (String, Double) -> Void
    ) async -> AnalysisResult {
        let fm = FileManager.default

        // Step 1: Build an index of existing files on destination by filename → path
        progressHandler("Scanning destination...", 0)
        let existingFiles = findDJIFiles(in: destination)

        var filenameIndex: [String: [URL]] = [:]
        for file in existingFiles {
            let name = file.lastPathComponent
            filenameIndex[name, default: []].append(file)
        }

        // Step 2: For each source file, check if it already exists on destination
        var newFiles: [(FootageFile, String)] = []
        var alreadyCopied: [(FootageFile, String)] = []
        var misplaced: [(FootageFile, String, String)] = []

        let total = sourceFiles.count
        for (index, sourceFile) in sourceFiles.enumerated() {
            let progress = Double(index) / Double(max(total, 1))
            progressHandler("Checking \(sourceFile.filename)...", progress)

            let expectedPath = FileOrganizer.destinationPath(
                destinationRoot: destination,
                deviceType: deviceType,
                file: sourceFile,
                pattern: pattern
            ).path

            // Check 1: Does it exist at the expected path with matching size?
            if fm.fileExists(atPath: expectedPath),
               let attrs = try? fm.attributesOfItem(atPath: expectedPath),
               let size = attrs[.size] as? Int64,
               size == sourceFile.fileSize {
                alreadyCopied.append((sourceFile, expectedPath))
                continue
            }

            // Check 2: Does a file with the same name and size exist elsewhere?
            if let candidates = filenameIndex[sourceFile.filename] {
                var foundMatch = false
                for candidate in candidates {
                    if let attrs = try? fm.attributesOfItem(atPath: candidate.path),
                       let size = attrs[.size] as? Int64,
                       size == sourceFile.fileSize {
                        // Check if it's in a titled folder that matches the expected date
                        // e.g. found at "20251222 - RC Car Vlog/videos/" vs expected "20251222/videos/"
                        if isInMatchingTitledFolder(actual: candidate.path, expected: expectedPath) {
                            alreadyCopied.append((sourceFile, candidate.path))
                        } else {
                            misplaced.append((sourceFile, candidate.path, expectedPath))
                        }
                        foundMatch = true
                        break
                    }
                }
                if foundMatch { continue }
            }

            // Not found anywhere — it's new
            newFiles.append((sourceFile, expectedPath))
        }

        progressHandler("Analysis complete", 1.0)

        return AnalysisResult(
            newFiles: newFiles,
            alreadyCopied: alreadyCopied,
            misplaced: misplaced
        )
    }

    /// Check if two paths differ only by a project title in a date component
    /// e.g. ".../20251222 - RC Car Vlog/videos/xxx.MP4" vs ".../20251222/videos/xxx.MP4"
    private static func isInMatchingTitledFolder(actual: String, expected: String) -> Bool {
        let actualParts = actual.split(separator: "/")
        let expectedParts = expected.split(separator: "/")
        guard actualParts.count == expectedParts.count else { return false }

        for (a, e) in zip(actualParts, expectedParts) {
            if a == e { continue }
            let as_ = String(a)
            let es = String(e)
            // Allow if both start with the same 8-digit date prefix
            if as_.count >= 8 && es.count >= 8 &&
               as_.prefix(8).allSatisfy(\.isNumber) &&
               es.prefix(8).allSatisfy(\.isNumber) &&
               as_.prefix(8) == es.prefix(8) {
                continue
            }
            return false
        }
        return true
    }

    /// Recursively find all DJI-named files on a volume
    private static func findDJIFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isFile else { continue }

            if DJIFilenameParser.isDJIFile(fileURL.lastPathComponent) {
                results.append(fileURL)
            }
        }
        return results
    }
}
