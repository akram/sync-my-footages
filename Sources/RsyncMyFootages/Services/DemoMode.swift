import Foundation

/// Creates mock DJI device and destination for testing without real hardware
enum DemoMode {
    static let basePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".rsync-my-footages/demo")

    static var devicePath: URL { basePath.appendingPathComponent("device") }
    static var destinationPath: URL { basePath.appendingPathComponent("destination") }

    /// Set up a fake DJI device with sample files and a fake destination
    static func setup() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: devicePath, withIntermediateDirectories: true)
        try fm.createDirectory(at: destinationPath, withIntermediateDirectories: true)

        // Create DCIM/DJI_001/ structure on the "device"
        let dcimDir = devicePath
            .appendingPathComponent("DCIM")
            .appendingPathComponent("DJI_001")
        try fm.createDirectory(at: dcimDir, withIntermediateDirectories: true)

        // Generate sample DJI files across a few dates
        let sessions: [(date: String, count: Int)] = [
            ("20251206", 4),  // Dec 6 — will match RC Car Vlog if PROJECT.md exists
            ("20251222", 6),  // Dec 22
            ("20260115", 3),  // Jan 15
        ]

        for session in sessions {
            for seq in 1...session.count {
                let seqStr = String(format: "%04d", seq)
                let baseName = "DJI_\(session.date)120000_\(seqStr)_D"

                // Create MP4 (fake, small — just enough to have valid size)
                let mp4 = dcimDir.appendingPathComponent("\(baseName).MP4")
                if !fm.fileExists(atPath: mp4.path) {
                    let data = generateFakeContent(name: baseName, ext: "MP4", size: 1024 * 100) // 100KB
                    try data.write(to: mp4)
                }

                // Create LRF
                let lrf = dcimDir.appendingPathComponent("\(baseName).LRF")
                if !fm.fileExists(atPath: lrf.path) {
                    let data = generateFakeContent(name: baseName, ext: "LRF", size: 1024 * 10) // 10KB
                    try data.write(to: lrf)
                }

                // Create WAV
                let wav = dcimDir.appendingPathComponent("\(baseName).WAV")
                if !fm.fileExists(atPath: wav.path) {
                    let data = generateFakeContent(name: baseName, ext: "WAV", size: 1024 * 50) // 50KB
                    try data.write(to: wav)
                }
            }
        }

        // Add a JPG for good measure
        let jpg = dcimDir.appendingPathComponent("DJI_20251222120000_0007_D.JPG")
        if !fm.fileExists(atPath: jpg.path) {
            try generateFakeContent(name: "photo", ext: "JPG", size: 1024 * 5).write(to: jpg)
        }

        // Pre-populate some files on the "destination" to test duplicate detection
        // Copy a couple files to simulate a previous manual copy
        let destVideos = destinationPath.appendingPathComponent("Videos")
        try fm.createDirectory(at: destVideos, withIntermediateDirectories: true)

        let srcFile = dcimDir.appendingPathComponent("DJI_20251222120000_0001_D.MP4")
        let dstFile = destVideos.appendingPathComponent("DJI_20251222120000_0001_D.MP4")
        if fm.fileExists(atPath: srcFile.path) && !fm.fileExists(atPath: dstFile.path) {
            try fm.copyItem(at: srcFile, to: dstFile)
        }

        // Create a PROJECT.md in destination
        let projectDir = destinationPath.appendingPathComponent("OsmoPocket3/20251206")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try ProjectFile.create(at: projectDir, fields: [
            "title": "RC Car Vlog",
            "client": "Personal",
            "tags": "rc, vlog",
        ])
    }

    /// Clean up demo files
    static func teardown() {
        try? FileManager.default.removeItem(at: basePath)
    }

    /// Check if demo mode is active
    static var isActive: Bool {
        FileManager.default.fileExists(atPath: devicePath.path)
    }

    /// Generate deterministic fake file content (different per file so SHA256 differs)
    private static func generateFakeContent(name: String, ext: String, size: Int) -> Data {
        let header = "\(name).\(ext)\n".data(using: .utf8) ?? Data()
        var data = Data(capacity: size)
        data.append(header)
        // Fill remaining with repeating pattern
        let filler = Data(repeating: UInt8(name.hashValue & 0xFF), count: max(0, size - header.count))
        data.append(filler)
        return data
    }
}
