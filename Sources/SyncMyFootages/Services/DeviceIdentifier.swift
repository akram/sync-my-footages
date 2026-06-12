import Foundation
import AVFoundation

/// Identifies capture devices from mounted volume paths
enum DeviceIdentifier {
    /// Check if a mounted volume is a footage source (not a sync destination)
    static func identify(volumePath: URL) -> CaptureDevice? {
        let fm = FileManager.default

        // Skip volumes that are sync destinations (contain our journal file)
        let journalPath = volumePath.appendingPathComponent(Constants.decentralizedJournalFilename)
        if fm.fileExists(atPath: journalPath.path) {
            return nil
        }

        let dcimPath = volumePath.appendingPathComponent(Constants.dcimFolderName)
        guard fm.fileExists(atPath: dcimPath.path) else { return nil }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: dcimPath,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch {
            return nil
        }

        let djiDirs = contents.filter { url in
            url.lastPathComponent.hasPrefix(Constants.djiFolderPrefix)
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        guard !djiDirs.isEmpty else { return nil }

        let deviceType = inferDeviceType(from: djiDirs)
        let storageType = inferStorageType(volumePath: volumePath)

        return CaptureDevice(
            volumePath: volumePath,
            volumeName: volumePath.lastPathComponent,
            deviceType: deviceType,
            dcimFolders: djiDirs,
            storageType: storageType
        )
    }

    /// Also detect footage in non-DCIM folders (e.g. already-copied files)
    /// Returns nil if this doesn't look like a DJI source
    static func identifyFromVideoFiles(in folderURL: URL) -> CaptureDeviceType? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        let mp4s = files.filter {
            $0.pathExtension.uppercased() == "MP4" && CaptureDeviceFilenameParser.isDJIFile($0.lastPathComponent)
        }
        guard let firstMP4 = mp4s.first else { return nil }
        return readDeviceTypeFromMetadata(firstMP4)
    }

    /// Infer device type by reading video file metadata (encoder tag)
    private static func inferDeviceType(from djiDirs: [URL]) -> CaptureDeviceType {
        let fm = FileManager.default

        for dir in djiDirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                continue
            }

            let mp4Files = files.filter { $0.pathExtension.uppercased() == "MP4" }
            for mp4 in mp4Files.prefix(3) {
                if let type = readDeviceTypeFromMetadata(mp4) {
                    return type
                }
            }
        }

        return .unknown
    }

    /// Read the encoder/model tag from an MP4 file using AVFoundation
    /// Runs entirely off the main thread to avoid deadlocks
    /// DJI stores model in the ©too (encoder) tag, e.g. "DJI OsmoPocket3"
    private static func readDeviceTypeFromMetadata(_ videoURL: URL) -> CaptureDeviceType? {
        let box = SendableBox()
        let semaphore = DispatchSemaphore(value: 0)

        // Must run the async Task from a background queue, NOT the main thread
        // Otherwise semaphore.wait blocks main and Task.detached may need main → deadlock
        DispatchQueue.global(qos: .userInitiated).async {
            let innerSem = DispatchSemaphore(value: 0)
            Task.detached {
                defer { innerSem.signal() }
                let asset = AVURLAsset(url: videoURL)
                guard let metadata = try? await asset.load(.metadata) else { return }

                for item in metadata {
                    guard let value = try? await item.load(.stringValue) else { continue }
                    if value.uppercased().contains("DJI") {
                        if let matched = matchDeviceType(from: value), matched != .unknown {
                            box.set(matched)
                            return
                        }
                    }
                }
            }
            _ = innerSem.wait(timeout: .now() + 2)
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 3)
        return box.get()
    }

    /// Thread-safe box for passing result across concurrency boundaries
    private final class SendableBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CaptureDeviceType?
        func set(_ v: CaptureDeviceType) { lock.lock(); value = v; lock.unlock() }
        func get() -> CaptureDeviceType? { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Match a metadata model string to a DJI device type
    private static func matchDeviceType(from modelString: String) -> CaptureDeviceType? {
        let model = modelString.lowercased()

        if model.contains("pocket3") || model.contains("pocket 3") {
            return .osmoPocket3
        }
        if model.contains("action5") || model.contains("action 5") {
            return .action5Pro
        }
        if model.contains("neo2") || model.contains("neo 2") {
            return .neo2
        }
        if model.contains("osmo") || model.contains("pocket") {
            return .osmoPocket3
        }
        if model.contains("action") {
            return .action5Pro
        }
        if model.contains("neo") || model.contains("avata") {
            return .neo2
        }
        if model.contains("dji") {
            return .unknown
        }
        return nil
    }

    /// Determine storage type using diskutil info
    private static func inferStorageType(volumePath: URL) -> CaptureDevice.StorageType {
        let diskutilInfo = getDiskutilInfo(volumePath: volumePath)

        if let protocol_ = diskutilInfo["Protocol"] {
            let proto = protocol_.uppercased()
            if proto.contains("SDXC") || proto.contains("SD CARD") || proto.contains("SDHC") {
                return .sdCard
            }
        }

        if let mediaName = diskutilInfo["Media Name"] {
            let name = mediaName.uppercased()
            if name.contains("SD") || name.contains("SDXC") || name.contains("SDHC")
                || name.contains("CARD READER") || name.contains("MICRO SD") {
                return .sdCard
            }
        }

        if let removable = diskutilInfo["Removable Media"] {
            if removable.lowercased().contains("removable") {
                return .sdCard
            }
        }

        let volumeName = volumePath.lastPathComponent.uppercased()
        if volumeName.contains("SD") || volumeName.contains("SDCARD") || volumeName.contains("EXT") {
            return .sdCard
        }
        if volumeName.contains("INTERNAL") || volumeName.contains("DJI") {
            return .internalStorage
        }

        if let protocol_ = diskutilInfo["Protocol"] {
            if protocol_.uppercased().contains("USB") {
                return .internalStorage
            }
        }

        return .unknown
    }

    /// Run diskutil info and parse key-value pairs
    private static func getDiskutilInfo(volumePath: URL) -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", volumePath.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var info: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            info[key] = value
        }
        return info
    }

    /// Scan all currently mounted volumes for capture devices
    static func scanMountedVolumes() -> [CaptureDevice] {
        let fm = FileManager.default
        guard let volumes = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        return volumes.compactMap { identify(volumePath: $0) }
    }
}
