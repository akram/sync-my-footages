import Foundation

/// Represents a PROJECT.md file found in a destination directory
struct ProjectFile: Identifiable, Hashable, Sendable {
    let directoryPath: String
    let fields: [String: String]
    let body: String

    var id: String { directoryPath }
    var title: String { fields["title"] ?? "" }

    var sanitizedTitle: String {
        title
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - Parsing

    static let filename = "PROJECT.md"

    static func parse(at url: URL) -> ProjectFile? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(content: content, directoryPath: url.deletingLastPathComponent().path)
    }

    static func parse(content: String, directoryPath: String) -> ProjectFile? {
        let lines = content.components(separatedBy: "\n")

        guard let firstDash = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ProjectFile(directoryPath: directoryPath, fields: [:], body: content)
        }

        let searchStart = lines.index(after: firstDash)
        guard let closingDash = lines[searchStart...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ProjectFile(directoryPath: directoryPath, fields: [:], body: content)
        }

        var fields: [String: String] = [:]
        for line in lines[searchStart..<closingDash] {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        let bodyStart = lines.index(after: closingDash)
        let body = lines[bodyStart...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return ProjectFile(directoryPath: directoryPath, fields: fields, body: body)
    }

    static func create(at directory: URL, fields: [String: String], body: String = "") throws {
        var content = "---\n"
        if let title = fields["title"] {
            content += "title: \(title)\n"
        }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) where key != "title" {
            content += "\(key): \(value)\n"
        }
        content += "---\n"
        if !body.isEmpty {
            content += "\n\(body)\n"
        }
        let fileURL = directory.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Project Actions

/// Scans destinations for PROJECT.md files, renames directories, and merges same-title projects
enum ProjectManager {
    struct ApplyResult: Sendable {
        var renamed: [(from: String, to: String)] = []
        var merged: [(from: String, into: String)] = []
        var errors: [String] = []
    }

    /// Scan a directory for PROJECT.md files and apply them:
    /// 1. Rename each directory to include the project title (e.g. "20251206" → "20251206 - RC Car Vlog")
    /// 2. If multiple directories share the same title, merge their contents into the first one
    static func applyProjects(in rootDirectory: URL, separator: String = " - ") -> ApplyResult {
        let fm = FileManager.default
        var result = ApplyResult()

        // Step 1: Find all PROJECT.md files (only at first subdirectory level)
        guard let subdirs = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return result }

        var projects: [(dir: URL, project: ProjectFile)] = []
        for subdir in subdirs {
            guard (try? subdir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectURL = subdir.appendingPathComponent(ProjectFile.filename)
            guard let project = ProjectFile.parse(at: projectURL) else { continue }
            guard !project.title.isEmpty else { continue }
            projects.append((subdir, project))
        }

        guard !projects.isEmpty else { return result }

        // Step 2: Rename directories that don't already include the title
        var renamedDirs: [(url: URL, project: ProjectFile)] = []
        for (dir, project) in projects {
            let dirName = dir.lastPathComponent
            let title = project.sanitizedTitle

            // Skip if the directory already contains the title
            if dirName.contains(title) {
                renamedDirs.append((dir, project))
                continue
            }

            // Build new name: "20251206" → "20251206 - RC Car Vlog"
            let newName = "\(dirName)\(separator)\(title)"
            let newURL = dir.deletingLastPathComponent().appendingPathComponent(newName)

            // Check if target already exists
            if fm.fileExists(atPath: newURL.path) {
                // Target exists — we'll merge later
                renamedDirs.append((dir, project))
                continue
            }

            do {
                try fm.moveItem(at: dir, to: newURL)
                result.renamed.append((dirName, newName))
                renamedDirs.append((newURL, project))
            } catch {
                result.errors.append("Failed to rename \(dirName): \(error.localizedDescription)")
                renamedDirs.append((dir, project))
            }
        }

        // Step 3: Group by title and merge directories with the same title
        let grouped = Dictionary(grouping: renamedDirs) { $0.project.title }
        for (_, group) in grouped where group.count > 1 {
            let target = group[0].url
            for source in group.dropFirst() {
                let mergeResult = mergeDirectory(from: source.url, into: target)
                if mergeResult.success {
                    result.merged.append((source.url.lastPathComponent, target.lastPathComponent))
                } else {
                    result.errors.append(contentsOf: mergeResult.errors)
                }
            }
        }

        return result
    }

    /// Move all files from source into target, preserving subdirectory structure
    /// Removes source directory when done
    private static func mergeDirectory(from source: URL, into target: URL) -> (success: Bool, errors: [String]) {
        let fm = FileManager.default
        var errors: [String] = []

        guard let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (false, ["Cannot enumerate \(source.lastPathComponent)"])
        }

        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }

            // Skip PROJECT.md from source (keep the target's one)
            if fileURL.lastPathComponent == ProjectFile.filename { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
            let destURL = target.appendingPathComponent(relativePath)
            let destDir = destURL.deletingLastPathComponent()

            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                if fm.fileExists(atPath: destURL.path) {
                    // Duplicate — same name exists, skip (it's likely the same file)
                    continue
                }
                try fm.moveItem(at: fileURL, to: destURL)
            } catch {
                errors.append("Failed to move \(relativePath): \(error.localizedDescription)")
            }
        }

        // Remove source directory if empty (or only has PROJECT.md left)
        try? fm.removeItem(at: source)

        return (errors.isEmpty, errors)
    }

    /// Scan for PROJECT.md files in a directory (non-recursive, first level only)
    static func scan(directory: URL) -> [ProjectFile] {
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var projects: [ProjectFile] = []
        for subdir in subdirs {
            guard (try? subdir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectURL = subdir.appendingPathComponent(ProjectFile.filename)
            if let project = ProjectFile.parse(at: projectURL) {
                projects.append(project)
            }
        }
        return projects.sorted { $0.title < $1.title }
    }
}
