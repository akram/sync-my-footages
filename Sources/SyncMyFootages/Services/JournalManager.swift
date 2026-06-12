import Foundation
import SwiftData

/// Manages the centralized journal database (SwiftData/SQLite)
@MainActor
final class JournalManager {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let journalDir = Constants.centralJournalDirectory
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)

        let dbURL = journalDir.appendingPathComponent(Constants.centralJournalFilename)
        let config = ModelConfiguration(url: dbURL)
        self.container = try ModelContainer(for: JournalEntry.self, configurations: config)
        self.context = ModelContext(container)
    }

    // MARK: - Record

    /// Record a synced file in the journal
    func record(
        sha256: String,
        originalFilename: String,
        originalSourcePath: String,
        currentPath: String,
        diskIdentifier: String,
        diskName: String,
        fileSize: Int64,
        captureDate: Date,
        fileExtension: String,
        deviceType: String
    ) throws {
        let entry = JournalEntry(
            sha256: sha256,
            originalFilename: originalFilename,
            originalSourcePath: originalSourcePath,
            currentPath: currentPath,
            diskIdentifier: diskIdentifier,
            diskName: diskName,
            fileSize: fileSize,
            captureDate: captureDate,
            fileExtension: fileExtension,
            deviceType: deviceType
        )
        context.insert(entry)
        try context.save()
    }

    // MARK: - Query

    /// Find all entries for a given SHA256 hash (all copies across disks)
    func findByHash(_ sha256: String) throws -> [JournalEntry] {
        let predicate = #Predicate<JournalEntry> { $0.sha256 == sha256 }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try context.fetch(descriptor)
    }

    /// Find all entries on a given disk
    func findByDisk(_ diskIdentifier: String) throws -> [JournalEntry] {
        let predicate = #Predicate<JournalEntry> { $0.diskIdentifier == diskIdentifier }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try context.fetch(descriptor)
    }

    /// Get all unique SHA256 hashes with their copy count
    func redundancyReport() throws -> [(sha256: String, filename: String, copyCount: Int, disks: [String])] {
        let descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.sha256)]
        )
        let allEntries = try context.fetch(descriptor)

        let grouped = Dictionary(grouping: allEntries) { $0.sha256 }
        return grouped.map { sha256, entries in
            (
                sha256: sha256,
                filename: entries.first?.originalFilename ?? "",
                copyCount: entries.count,
                disks: Array(Set(entries.map(\.diskName)))
            )
        }.sorted { $0.copyCount < $1.copyCount } // least redundant first
    }

    /// Find files with only one copy (at risk)
    func atRiskFiles() throws -> [JournalEntry] {
        let report = try redundancyReport()
        let atRiskHashes = Set(report.filter { $0.copyCount == 1 }.map(\.sha256))

        let descriptor = FetchDescriptor<JournalEntry>()
        let allEntries = try context.fetch(descriptor)
        return allEntries.filter { atRiskHashes.contains($0.sha256) }
    }

    /// Check if a file (by SHA256) already exists on a destination disk
    func isAlreadySynced(sha256: String, toDisk diskIdentifier: String) throws -> Bool {
        let predicate = #Predicate<JournalEntry> {
            $0.sha256 == sha256 && $0.diskIdentifier == diskIdentifier
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = try context.fetch(descriptor)
        return !results.isEmpty
    }

    /// Update the path of a journal entry (after file was moved)
    func updatePath(sha256: String, diskIdentifier: String, oldPath: String, newPath: String) throws {
        let predicate = #Predicate<JournalEntry> {
            $0.sha256 == sha256 && $0.diskIdentifier == diskIdentifier && $0.currentPath == oldPath
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = try context.fetch(descriptor)

        for entry in results {
            entry.currentPath = newPath
            entry.compositeKey = "\(sha256)|\(diskIdentifier)|\(newPath)"
        }
        try context.save()
    }

    /// Record verification result
    func recordVerification(sha256: String, diskIdentifier: String, level: Int, passed: Bool) throws {
        let predicate = #Predicate<JournalEntry> {
            $0.sha256 == sha256 && $0.diskIdentifier == diskIdentifier
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = try context.fetch(descriptor)

        for entry in results {
            entry.lastVerifiedDate = Date()
            entry.lastVerificationLevel = level
            entry.lastVerificationPassed = passed
        }
        try context.save()
    }

    /// Get total stats
    func stats() throws -> (totalFiles: Int, totalDisks: Int, totalBytes: Int64) {
        let descriptor = FetchDescriptor<JournalEntry>()
        let all = try context.fetch(descriptor)
        let uniqueHashes = Set(all.map(\.sha256))
        let uniqueDisks = Set(all.map(\.diskIdentifier))
        let totalBytes = all.reduce(Int64(0)) { $0 + $1.fileSize }
        return (uniqueHashes.count, uniqueDisks.count, totalBytes)
    }
}
