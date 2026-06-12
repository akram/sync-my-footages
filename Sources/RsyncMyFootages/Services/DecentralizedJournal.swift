import Foundation

/// Per-disk journal stored as JSON at the root of each volume
/// Portable, human-readable, works on exFAT
enum DecentralizedJournal {
    struct JournalFile: Codable {
        var version: Int = 1
        var diskIdentifier: String
        var diskName: String
        var lastUpdated: Date
        var entries: [Entry]
    }

    struct Entry: Codable, Hashable {
        var sha256: String
        var relativePath: String
        var originalFilename: String
        var originalSourcePath: String
        var fileSize: Int64
        var captureDate: Date
        var syncTimestamp: Date
        var deviceType: String
    }

    // MARK: - Read

    /// Read the journal from a volume, returns nil if not found
    static func read(from volumePath: URL) -> JournalFile? {
        let journalURL = volumePath.appendingPathComponent(Constants.decentralizedJournalFilename)
        guard let data = try? Data(contentsOf: journalURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(JournalFile.self, from: data)
    }

    // MARK: - Write

    /// Write the journal to a volume (atomic: write to temp, then rename)
    static func write(_ journal: JournalFile, to volumePath: URL) throws {
        let journalURL = volumePath.appendingPathComponent(Constants.decentralizedJournalFilename)
        let tempURL = volumePath.appendingPathComponent(".rsync-footages.journal.tmp")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(journal)
        try data.write(to: tempURL, options: .atomic)

        let fm = FileManager.default
        if fm.fileExists(atPath: journalURL.path) {
            _ = try fm.replaceItemAt(journalURL, withItemAt: tempURL)
        } else {
            try fm.moveItem(at: tempURL, to: journalURL)
        }
    }

    // MARK: - Append

    /// Add an entry to the journal on a volume
    static func appendEntry(_ entry: Entry, to volumePath: URL, diskIdentifier: String, diskName: String) throws {
        var journal = read(from: volumePath) ?? JournalFile(
            diskIdentifier: diskIdentifier,
            diskName: diskName,
            lastUpdated: Date(),
            entries: []
        )

        // Avoid duplicates (same sha256 + same relative path)
        if !journal.entries.contains(where: { $0.sha256 == entry.sha256 && $0.relativePath == entry.relativePath }) {
            journal.entries.append(entry)
        }

        journal.lastUpdated = Date()
        try write(journal, to: volumePath)
    }

    // MARK: - Query

    /// Check if a file (by SHA256) is already recorded on this volume
    static func contains(sha256: String, on volumePath: URL) -> Bool {
        guard let journal = read(from: volumePath) else { return false }
        return journal.entries.contains { $0.sha256 == sha256 }
    }

    /// Get all entries from a volume
    static func entries(on volumePath: URL) -> [Entry] {
        read(from: volumePath)?.entries ?? []
    }
}
