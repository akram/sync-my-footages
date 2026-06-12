import Foundation

/// A configured destination disk for syncing footage
struct DestinationDisk: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var path: String
    var diskIdentifier: String
    var isBackup: Bool
    var isAvailable: Bool

    init(name: String, path: String, diskIdentifier: String, isBackup: Bool = false) {
        self.id = diskIdentifier
        self.name = name
        self.path = path
        self.diskIdentifier = diskIdentifier
        self.isBackup = isBackup
        self.isAvailable = FileManager.default.fileExists(atPath: path)
    }
}
