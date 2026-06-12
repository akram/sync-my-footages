import Foundation
import SwiftData

/// Central journal entry stored in SwiftData (SQLite)
/// Tracks a single file copy on a specific disk, identified by SHA256
@Model
final class JournalEntry {
    /// SHA256 hex string — the primary identity of the file
    @Attribute(.unique)
    var compositeKey: String  // sha256 + diskIdentifier + currentPath

    var sha256: String
    var originalFilename: String
    var originalSourcePath: String
    var currentPath: String
    var diskIdentifier: String
    var diskName: String
    var fileSize: Int64
    var captureDate: Date
    var syncTimestamp: Date
    var lastVerifiedDate: Date?
    var lastVerificationLevel: Int?
    var lastVerificationPassed: Bool?
    var fileExtension: String
    var deviceType: String
    var thumbnailPath: String?

    init(
        sha256: String,
        originalFilename: String,
        originalSourcePath: String,
        currentPath: String,
        diskIdentifier: String,
        diskName: String,
        fileSize: Int64,
        captureDate: Date,
        syncTimestamp: Date = Date(),
        fileExtension: String,
        deviceType: String
    ) {
        self.compositeKey = "\(sha256)|\(diskIdentifier)|\(currentPath)"
        self.sha256 = sha256
        self.originalFilename = originalFilename
        self.originalSourcePath = originalSourcePath
        self.currentPath = currentPath
        self.diskIdentifier = diskIdentifier
        self.diskName = diskName
        self.fileSize = fileSize
        self.captureDate = captureDate
        self.syncTimestamp = syncTimestamp
        self.fileExtension = fileExtension
        self.deviceType = deviceType
    }
}
