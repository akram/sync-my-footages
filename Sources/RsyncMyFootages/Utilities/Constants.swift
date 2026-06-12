import Foundation

enum Constants {
    /// App identifier
    static let appIdentifier = "com.akram.rsync-my-footages"

    /// Journal filename written to each volume
    static let decentralizedJournalFilename = ".rsync-footages.journal"

    /// Central journal directory
    static let centralJournalDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".rsync-my-footages", isDirectory: true)
    }()

    /// Central journal database filename
    static let centralJournalFilename = "journal.db"

    /// DJI folder patterns
    static let dcimFolderName = "DCIM"
    static let djiFolderPrefix = "DJI_"

    /// File extensions we care about
    static let videoExtensions: Set<String> = ["MP4", "mp4", "MOV", "mov"]
    static let lowResExtensions: Set<String> = ["LRF", "lrf"]
    static let audioExtensions: Set<String> = ["WAV", "wav"]
    static let photoExtensions: Set<String> = ["JPG", "jpg", "JPEG", "jpeg", "DNG", "dng", "PNG", "png"]
    static let allFootageExtensions: Set<String> = videoExtensions.union(lowResExtensions).union(audioExtensions).union(photoExtensions)

    /// rsync binary path
    static let rsyncPath = "/usr/bin/rsync"

    /// rsync exclude patterns
    static let rsyncExcludes = ["._*", ".Spotlight-V100", ".Trashes", ".fseventsd", ".DS_Store"]

    /// SHA256 hashing buffer size (1 MB)
    static let hashBufferSize = 1024 * 1024

    /// Thumbnail size
    static let thumbnailMaxDimension: CGFloat = 240
}
