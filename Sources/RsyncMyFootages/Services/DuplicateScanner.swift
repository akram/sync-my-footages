import Foundation

/// Scans a directory for duplicate DJI files using size + SHA256
enum DuplicateScanner {
    struct DuplicateGroup: Identifiable, Sendable {
        let id: String  // SHA256
        let sha256: String
        let filename: String
        let fileSize: Int64
        let paths: [String]

        var count: Int { paths.count }
        var wastedBytes: Int64 { fileSize * Int64(count - 1) }
    }

    struct ScanResult: Sendable {
        let duplicates: [DuplicateGroup]
        let totalFilesScanned: Int
        let totalDuplicateFiles: Int
        let totalWastedBytes: Int64
    }

    /// Scan a directory for duplicate DJI files
    /// Step 1: Group by filename+size (fast)
    /// Step 2: Hash only the groups with multiple matches (slow, but targeted)
    static func scan(
        directory: URL,
        progressHandler: @escaping @Sendable (String, Double) -> Void
    ) async -> ScanResult {
        // Step 1: Find all DJI files
        progressHandler("Scanning for DJI files...", 0)
        let allFiles = findAllDJIFiles(in: directory)

        let totalFiles = allFiles.count
        progressHandler("Found \(totalFiles) DJI files, grouping by size...", 0.1)

        // Step 2: Group by filename + size (potential duplicates)
        struct SizeKey: Hashable {
            let filename: String
            let size: Int64
        }

        let grouped = Dictionary(grouping: allFiles) { file in
            SizeKey(filename: file.url.lastPathComponent, size: file.size)
        }

        let potentialDuplicates = grouped.filter { $0.value.count > 1 }

        if potentialDuplicates.isEmpty {
            progressHandler("No duplicates found", 1.0)
            return ScanResult(duplicates: [], totalFilesScanned: totalFiles, totalDuplicateFiles: 0, totalWastedBytes: 0)
        }

        // Step 3: Hash only potential duplicates to confirm
        let totalToHash = potentialDuplicates.values.reduce(0) { $0 + $1.count }
        var hashedCount = 0
        var duplicateGroups: [DuplicateGroup] = []

        for (sizeKey, files) in potentialDuplicates {
            // Hash each file in this group
            var hashToPath: [String: [String]] = [:]

            for file in files {
                hashedCount += 1
                let progress = 0.1 + 0.9 * Double(hashedCount) / Double(totalToHash)
                progressHandler("Hashing \(file.url.lastPathComponent)...", progress)

                guard let hash = try? await HashingService.sha256(of: file.url) else { continue }
                hashToPath[hash, default: []].append(file.url.path)
            }

            // Keep only groups with actual duplicates (same SHA256)
            for (hash, paths) in hashToPath where paths.count > 1 {
                duplicateGroups.append(DuplicateGroup(
                    id: hash,
                    sha256: hash,
                    filename: sizeKey.filename,
                    fileSize: sizeKey.size,
                    paths: paths.sorted()
                ))
            }
        }

        let totalDuplicateFiles = duplicateGroups.reduce(0) { $0 + $1.count - 1 }
        let totalWasted = duplicateGroups.reduce(Int64(0)) { $0 + $1.wastedBytes }

        progressHandler("Done", 1.0)

        return ScanResult(
            duplicates: duplicateGroups.sorted { $0.wastedBytes > $1.wastedBytes },
            totalFilesScanned: totalFiles,
            totalDuplicateFiles: totalDuplicateFiles,
            totalWastedBytes: totalWasted
        )
    }

    // MARK: - Private

    private struct FileInfo: Sendable {
        let url: URL
        let size: Int64
    }

    /// Synchronous file enumeration (NSDirectoryEnumerator can't be used in async contexts)
    private static func findAllDJIFiles(in directory: URL) -> [FileInfo] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [FileInfo] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            if DJIFilenameParser.isDJIFile(fileURL.lastPathComponent) {
                files.append(FileInfo(url: fileURL, size: Int64(values.fileSize ?? 0)))
            }
        }
        return files
    }
}
