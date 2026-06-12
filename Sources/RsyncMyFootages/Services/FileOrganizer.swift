import Foundation

/// Builds destination paths and scans source devices for footage files
enum FileOrganizer {
    /// Default organization pattern
    static let defaultPattern = "{device}/{year}{month}{day}/{type}"

    /// Get the folder name for a file extension using the configurable mapping
    static func typeFolderName(for extension_: String) -> String {
        FileTypeMapping.load().folderName(for: extension_)
    }

    /// Expand a pattern into a relative path
    /// Tokens: {device}, {year}, {month}, {day}, {type}
    static func expandPattern(
        _ pattern: String,
        deviceType: DJIDeviceType,
        captureDate: Date,
        fileExtension: String = "MP4"
    ) -> String {
        let cal = Calendar(identifier: .gregorian)
        let deviceName = deviceType.rawValue.replacingOccurrences(of: " ", with: "")
        let typeFolder = typeFolderName(for: fileExtension)

        return pattern
            .replacingOccurrences(of: "{device}", with: deviceName)
            .replacingOccurrences(of: "{year}", with: String(format: "%04d", cal.component(.year, from: captureDate)))
            .replacingOccurrences(of: "{month}", with: String(format: "%02d", cal.component(.month, from: captureDate)))
            .replacingOccurrences(of: "{day}", with: String(format: "%02d", cal.component(.day, from: captureDate)))
            .replacingOccurrences(of: "{type}", with: typeFolder)
    }

    /// Build destination path for a footage file
    static func destinationPath(
        destinationRoot: URL,
        deviceType: DJIDeviceType,
        file: FootageFile,
        pattern: String? = nil
    ) -> URL {
        let date = file.captureDate ?? Date()
        let pat = pattern ?? currentPattern()
        let relative = expandPattern(pat, deviceType: deviceType, captureDate: date, fileExtension: file.fileExtension)

        return destinationRoot
            .appendingPathComponent(relative)
            .appendingPathComponent(file.filename)
    }

    /// Build the directory portion of the destination (without filename)
    static func destinationDirectory(
        destinationRoot: URL,
        deviceType: DJIDeviceType,
        captureDate: Date,
        fileExtension: String = "MP4",
        pattern: String? = nil
    ) -> URL {
        let pat = pattern ?? currentPattern()
        let relative = expandPattern(pat, deviceType: deviceType, captureDate: captureDate, fileExtension: fileExtension)

        return destinationRoot.appendingPathComponent(relative)
    }

    /// Read the current pattern from UserDefaults
    static func currentPattern() -> String {
        UserDefaults.standard.string(forKey: "organizationPattern") ?? defaultPattern
    }

    /// Generate preview strings showing what the pattern produces
    static func patternPreview(
        _ pattern: String,
        deviceType: DJIDeviceType = .osmoPocket3,
        date: Date = Date()
    ) -> String {
        if pattern.contains("{type}") {
            let mp4 = expandPattern(pattern, deviceType: deviceType, captureDate: date, fileExtension: "MP4")
            let wav = expandPattern(pattern, deviceType: deviceType, captureDate: date, fileExtension: "WAV")
            let jpg = expandPattern(pattern, deviceType: deviceType, captureDate: date, fileExtension: "JPG")
            return "\(mp4)/DJI_...0001_D.MP4\n\(wav)/DJI_...0001_D.WAV\n\(jpg)/DJI_...0001_D.JPG"
        } else {
            let expanded = expandPattern(pattern, deviceType: deviceType, captureDate: date)
            return expanded + "/DJI_...0001_D.MP4"
        }
    }

    // MARK: - Reorganize

    /// Move files from old pattern to new pattern (rename only, same disk)
    /// Then renames date folders that contain a PROJECT.md.
    /// Idempotent: running multiple times produces the same result.
    static func reorganize(
        directory: URL,
        deviceType: DJIDeviceType,
        fromPattern: String,
        toPattern: String,
        separator: String = " - ",
        progressHandler: @escaping (String, Double) -> Void
    ) -> (moved: Int, skipped: Int, errors: Int) {
        let fm = FileManager.default

        // Strip {device}/ from pattern if the selected dir already IS the device folder
        var effectivePattern = toPattern
        let deviceName = deviceType.rawValue.replacingOccurrences(of: " ", with: "")
        if directory.lastPathComponent == deviceName && effectivePattern.hasPrefix("{device}/") {
            effectivePattern = String(effectivePattern.dropFirst("{device}/".count))
        }

        // Step 1: Move DJI files according to pattern
        // Files go into plain date folders based on the pattern (e.g. 20251222/videos/)
        // If a folder is already titled (e.g. "20251222 - RC Car Vlog"), files inside it
        // are already in the right place — the path comparison will skip them.
        progressHandler("Moving files...", 0)
        let allFiles = findDJIFiles(in: directory)
        var moved = 0
        var skipped = 0
        var errors = 0

        for (index, fileURL) in allFiles.enumerated() {
            let progress = 0.8 * Double(index) / Double(max(allFiles.count, 1))
            progressHandler(fileURL.lastPathComponent, progress)

            guard let parsed = DJIFilenameParser.parse(fileURL.lastPathComponent) else {
                skipped += 1
                continue
            }

            let newRelative = expandPattern(
                effectivePattern,
                deviceType: deviceType,
                captureDate: parsed.captureDate,
                fileExtension: parsed.fileExtension
            )

            let newPath = directory
                .appendingPathComponent(newRelative)
                .appendingPathComponent(fileURL.lastPathComponent)

            // Exact path match → skip
            if fileURL.path == newPath.path {
                skipped += 1
                continue
            }

            // Check if file is already in the right place but under a titled folder
            // e.g. file at ".../20251222 - RC Car Vlog/videos/xxx.MP4"
            //   vs expected ".../20251222/videos/xxx.MP4"
            // Compare: same parent structure except the date component has a title suffix
            let currentDir = fileURL.deletingLastPathComponent().path
            let expectedDir = newPath.deletingLastPathComponent().path
            if currentDir != expectedDir {
                // Check if they only differ by a project title in a date component
                let currentParts = currentDir.split(separator: "/")
                let expectedParts = expectedDir.split(separator: "/")
                if currentParts.count == expectedParts.count {
                    var allMatch = true
                    for (c, e) in zip(currentParts, expectedParts) {
                        if c == e { continue }
                        // Allow match if one starts with the other's 8-digit date prefix
                        let cs = String(c)
                        let es = String(e)
                        if cs.count >= 8 && es.count >= 8 &&
                           cs.prefix(8).allSatisfy(\.isNumber) &&
                           es.prefix(8).allSatisfy(\.isNumber) &&
                           cs.prefix(8) == es.prefix(8) {
                            continue  // date component with/without title — same thing
                        }
                        allMatch = false
                        break
                    }
                    if allMatch {
                        skipped += 1
                        continue
                    }
                }
            }

            do {
                try fm.createDirectory(at: newPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: fileURL, to: newPath)
                moved += 1
            } catch {
                errors += 1
            }
        }

        cleanEmptyDirectories(in: directory)

        // Step 2: Rename date folders that contain a PROJECT.md
        progressHandler("Applying project titles...", 0.9)
        renameWithProjectTitles(in: directory, separator: separator)

        cleanEmptyDirectories(in: directory)
        progressHandler("Done", 1.0)
        return (moved, skipped, errors)
    }

    /// Simple rename: for each immediate subfolder that has a PROJECT.md,
    /// rename the folder to include the title. Skip if already named correctly.
    private static func renameWithProjectTitles(in directory: URL, separator: String) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            NSLog("[ProjectTitles] Cannot list directory: %@", directory.path)
            return
        }

        // Write debug log to a file
        let logPath = "/tmp/rsync-project-titles.log"
        try? "=== renameWithProjectTitles ===\n".write(toFile: logPath, atomically: true, encoding: .utf8)
        func log(_ msg: String) {
            let line = "\(msg)\n"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            }
        }
        log("Directory: \(directory.path)")
        log("Items: \(contents.count)")

        for subdir in contents {
            guard (try? subdir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            let projectURL = subdir.appendingPathComponent(ProjectFile.filename)
            let projectExists = fm.fileExists(atPath: projectURL.path)

            log("  \(subdir.lastPathComponent): PROJECT.md exists=\(projectExists)")

            // Recurse into subdirectories that don't have a PROJECT.md
            if !projectExists {
                renameWithProjectTitles(in: subdir, separator: separator)
                continue
            }
            guard let project = ProjectFile.parse(at: projectURL) else {
                log("  Cannot parse PROJECT.md")
                continue
            }
            let title = project.sanitizedTitle
            guard !title.isEmpty else { continue }

            let dirName = subdir.lastPathComponent
            guard !dirName.contains(title) else {
                log("  Already titled: \(dirName)")
                continue
            }

            let newName = "\(dirName)\(separator)\(title)"
            let newURL = subdir.deletingLastPathComponent().appendingPathComponent(newName)

            log("  Title: \(title), dirName: \(dirName)")
            log("  New name: \(newName)")
            log("  Target exists: \(fm.fileExists(atPath: newURL.path))")

            if fm.fileExists(atPath: newURL.path) {
                log("  SKIP: target exists")
                continue
            }

            do {
                try fm.moveItem(at: subdir, to: newURL)
                log("  RENAMED OK")
            } catch {
                log("  FAILED: \(error)")
            }
        }
    }

    /// Remove empty directories recursively
    private static func cleanEmptyDirectories(in directory: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var dirs: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                dirs.append(url)
            }
        }

        for dir in dirs.sorted(by: { $0.path.count > $1.path.count }) {
            if let contents = try? fm.contentsOfDirectory(atPath: dir.path),
               contents.allSatisfy({ $0.hasPrefix(".") }) {
                try? fm.removeItem(at: dir)
            }
        }
    }

    // MARK: - Scan

    private static func findDJIFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if DJIFilenameParser.isDJIFile(fileURL.lastPathComponent) {
                results.append(fileURL)
            }
        }
        return results
    }

    /// Scan a DJI device for all footage files
    static func scanDevice(_ device: DJIDevice) throws -> [FootageFile] {
        let fm = FileManager.default
        var files: [FootageFile] = []

        for dcimFolder in device.dcimFolders {
            guard let contents = try? fm.contentsOfDirectory(
                at: dcimFolder,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            ) else { continue }

            for fileURL in contents {
                let ext = fileURL.pathExtension.uppercased()
                guard Constants.allFootageExtensions.contains(ext) else { continue }

                let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard resourceValues?.isRegularFile == true else { continue }

                let fileSize = Int64(resourceValues?.fileSize ?? 0)
                let parsed = DJIFilenameParser.parse(fileURL.lastPathComponent)

                files.append(FootageFile(url: fileURL, parsed: parsed, fileSize: fileSize))
            }
        }

        return files.sorted { ($0.captureDate ?? .distantPast) < ($1.captureDate ?? .distantPast) }
    }

    /// Group footage files by capture date (day)
    static func groupByDate(_ files: [FootageFile]) -> [(date: Date, files: [FootageFile])] {
        let cal = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: files) { file -> DateComponents in
            let date = file.captureDate ?? Date.distantPast
            return cal.dateComponents([.year, .month, .day], from: date)
        }

        return grouped
            .sorted { lhs, rhs in
                let ld = cal.date(from: lhs.key) ?? .distantPast
                let rd = cal.date(from: rhs.key) ?? .distantPast
                return ld < rd
            }
            .map { (cal.date(from: $0.key) ?? .distantPast, $0.value) }
    }

    /// Group footage files by clip (related MP4+LRF+WAV)
    static func groupByClip(_ files: [FootageFile]) -> [[FootageFile]] {
        let grouped = Dictionary(grouping: files) { $0.clipGroupKey ?? $0.id }
        return grouped.values
            .sorted { ($0.first?.captureDate ?? .distantPast) < ($1.first?.captureDate ?? .distantPast) }
    }
}
