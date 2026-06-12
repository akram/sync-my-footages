import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    // MARK: - Connected devices
    var connectedDevices: [CaptureDevice] = []

    // MARK: - Active sync jobs
    var activeSyncJobs: [SyncJob] = []

    // MARK: - Device profiles (persisted via UserDefaults)
    var deviceProfiles: [DeviceProfile] = []

    // MARK: - Destination disks
    var destinationDisks: [DestinationDisk] = []

    /// Save current state to UserDefaults (call after modifications)
    func saveSettings() {
        Self.save(deviceProfiles, forKey: "deviceProfiles")
        Self.save(destinationDisks, forKey: "destinationDisks")
    }

    // MARK: - UI state
    var selectedDeviceForSync: CaptureDevice?

    // MARK: - Services
    private(set) var diskWatcher: DiskWatcher?
    private let rsyncEngine = RsyncEngine()
    private(set) var journalManager: JournalManager?

    // MARK: - Computed

    var isSyncing: Bool {
        activeSyncJobs.contains { $0.status.isActive }
    }

    var menuBarIconName: String {
        if isSyncing {
            return "arrow.triangle.2.circlepath.circle.fill"
        } else if !connectedDevices.isEmpty {
            return "arrow.triangle.2.circlepath.circle"
        } else {
            return "arrow.triangle.2.circlepath"
        }
    }

    // MARK: - Lifecycle

    func start() {
        // Load persisted data
        deviceProfiles = Self.load(forKey: "deviceProfiles") ?? DeviceProfile.defaults
        destinationDisks = Self.load(forKey: "destinationDisks") ?? []

        // Update availability of destinations
        for i in destinationDisks.indices {
            destinationDisks[i].isAvailable = FileManager.default.fileExists(atPath: destinationDisks[i].path)
        }

        // Initialize journal manager
        if journalManager == nil {
            journalManager = try? JournalManager()
        }

        let watcher = DiskWatcher { [weak self] volume in
            await self?.volumeAppeared(volume)
        } onDisappear: { [weak self] volume in
            await self?.volumeDisappeared(volume)
        }
        self.diskWatcher = watcher
        watcher.start()
    }

    func stop() {
        diskWatcher?.stop()
        diskWatcher = nil
    }

    var isDemoActive: Bool { DemoMode.isActive }

    func rescan() {
        connectedDevices.removeAll()
        let devices = DeviceIdentifier.scanMountedVolumes()
        connectedDevices = devices
    }

    func toggleDemo() {
        if DemoMode.isActive {
            connectedDevices.removeAll { $0.volumePath == DemoMode.devicePath }
            destinationDisks.removeAll { $0.path == DemoMode.destinationPath.path }
            saveSettings()
            DemoMode.teardown()
        } else {
            try? DemoMode.setup()
            // Add demo device
            if let device = DeviceIdentifier.identify(volumePath: DemoMode.devicePath) {
                if !connectedDevices.contains(where: { $0.volumePath == device.volumePath }) {
                    connectedDevices.append(device)
                }
            }
            // Add demo destination
            if !destinationDisks.contains(where: { $0.path == DemoMode.destinationPath.path }) {
                destinationDisks.append(DestinationDisk(
                    name: "Demo Destination",
                    path: DemoMode.destinationPath.path,
                    diskIdentifier: "demo-dest"
                ))
            }
            saveSettings()
        }
    }

    // MARK: - Cancel

    private var syncTasks: [UUID: Task<Void, Never>] = [:]

    func cancelSync(jobID: UUID) {
        syncTasks[jobID]?.cancel()
        syncTasks.removeValue(forKey: jobID)
        Task { await rsyncEngine.cancel() }
        updateJob(jobID) { $0.status = .cancelled }
    }

    // MARK: - Device events

    private func volumeAppeared(_ volumePath: URL) {
        guard let device = DeviceIdentifier.identify(volumePath: volumePath) else { return }
        if !connectedDevices.contains(where: { $0.volumePath == device.volumePath }) {
            connectedDevices.append(device)
        }
    }

    private func volumeDisappeared(_ volumePath: URL) {
        connectedDevices.removeAll { $0.volumePath == volumePath }
    }

    // MARK: - Source change detection

    /// Stores last known mod dates of source DCIM folders: "volumeUUID:destPath" → timestamp
    nonisolated(unsafe) private static let lastSyncKey = "lastSyncTimestamps"

    /// Get the latest modification timestamp of a device's DCIM folders
    nonisolated private func sourceModTimestamp(_ device: CaptureDevice) -> TimeInterval {
        var latest: TimeInterval = 0
        for folder in device.dcimFolders {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: folder.path),
               let modDate = attrs[.modificationDate] as? Date {
                latest = max(latest, modDate.timeIntervalSince1970)
            }
        }
        return latest
    }

    /// Get the Volume UUID for a mounted volume via diskutil
    nonisolated private func volumeUUID(for path: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", path.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return path.lastPathComponent }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            if line.contains("Volume UUID") {
                let parts = line.split(separator: ":")
                if parts.count >= 2 { return parts[1].trimmingCharacters(in: .whitespaces) }
            }
        }
        return path.lastPathComponent // fallback
    }

    /// Check if source has changed since last sync to this destination
    nonisolated private func sourceHasChanged(device: CaptureDevice, destinationPath: String) -> Bool {
        let uuid = volumeUUID(for: device.volumePath)
        let key = "\(uuid):\(destinationPath)"
        guard let data = UserDefaults.standard.data(forKey: Self.lastSyncKey),
              let saved = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return true
        }
        let lastTimestamp = saved[key] ?? 0
        let currentTimestamp = sourceModTimestamp(device)
        return currentTimestamp != lastTimestamp
    }

    /// Record that we synced this source to this destination
    nonisolated private func recordSyncTimestamp(device: CaptureDevice, destinationPath: String) {
        let uuid = volumeUUID(for: device.volumePath)
        let key = "\(uuid):\(destinationPath)"
        var saved: [String: TimeInterval]
        if let data = UserDefaults.standard.data(forKey: Self.lastSyncKey),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            saved = decoded
        } else {
            saved = [:]
        }
        saved[key] = sourceModTimestamp(device)
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: Self.lastSyncKey)
        }
    }

    // MARK: - Sync

    /// Sync only new files (not already present on destination)
    func syncDevice(_ device: CaptureDevice, to destinationPath: String, onlyFiles: [(file: FootageFile, destPath: String)]? = nil) {
        let job = SyncJob(device: device, destinationPath: destinationPath)
        activeSyncJobs.append(job)
        let jobID = job.id

        let task = Task {
            do {
                let destURL = URL(fileURLWithPath: destinationPath)
                let fm = FileManager.default
                let diskIdentifier = destURL.lastPathComponent
                let diskName = destURL.lastPathComponent

                // Quick check: has the source changed since last sync? (run off main thread)
                if onlyFiles == nil {
                    let dev = device
                    let dest = destinationPath
                    let changed = await Task.detached {
                        self.sourceHasChanged(device: dev, destinationPath: dest)
                    }.value
                    if !changed {
                        updateJob(jobID) {
                            $0.status = .completed
                            $0.progress.currentFile = "No changes since last sync"
                        }
                        return
                    }
                }

                // Determine which files to copy
                let filesToCopy: [(file: FootageFile, destPath: String)]
                if let provided = onlyFiles {
                    filesToCopy = provided
                } else {
                    updateJob(jobID) { $0.status = .scanning }
                    let dev = device
                    let files = try await Task.detached { try FileOrganizer.scanDevice(dev) }.value
                    filesToCopy = files.map { file in
                        let dest = FileOrganizer.destinationPath(
                            destinationRoot: destURL,
                            deviceType: device.deviceType,
                            file: file
                        )
                        return (file, dest.path)
                    }
                }

                let totalFiles = filesToCopy.count
                let totalBytes = filesToCopy.reduce(Int64(0)) { $0 + $1.file.fileSize }

                updateJob(jobID) {
                    $0.progress.totalFiles = totalFiles
                    $0.progress.totalBytes = totalBytes
                    $0.status = .syncing
                }

                // Build a cache of directory listings to avoid repeated I/O (off main thread)
                let destURLCopy = destURL
                let dirCache = await Task.detached { DirectoryListingCache(root: destURLCopy) }.value

                // Copy files on a background thread to avoid blocking UI
                let filesToCopyRef = filesToCopy
                let copyResult = await Task.detached { () -> (copied: Int, skipped: Int, bytes: Int64, error: Error?) in
                    let fm = FileManager.default
                    var copiedCount = 0
                    var skippedCount = 0
                    var copiedBytes: Int64 = 0

                    for (index, item) in filesToCopyRef.enumerated() {
                        if Task.isCancelled { return (copiedCount, skippedCount, copiedBytes, CancellationError()) }

                        if dirCache.fileExists(filename: item.file.filename, expectedSize: item.file.fileSize, patternPath: item.destPath) {
                            skippedCount += 1
                            await MainActor.run {
                                self.updateJob(jobID) { $0.progress.filesTransferred = index + 1 }
                            }
                            continue
                        }

                        let destFileURL = URL(fileURLWithPath: item.destPath)
                        let destDir = destFileURL.deletingLastPathComponent()

                        // Show which file is being copied BEFORE starting
                        let sizeStr = ByteCountFormatter.string(fromByteCount: item.file.fileSize, countStyle: .file)
                        await MainActor.run {
                            self.updateJob(jobID) {
                                $0.progress.currentFile = "\(item.file.filename) (\(sizeStr))"
                            }
                        }

                        do {
                            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                            if fm.fileExists(atPath: destFileURL.path) {
                                try fm.removeItem(at: destFileURL)
                            }

                            // For large files (>500MB), poll destination size for progress
                            let largeFileThreshold: Int64 = 500 * 1024 * 1024
                            var dispatchTimer: DispatchSourceTimer?
                            if item.file.fileSize > largeFileThreshold {
                                let destPath = destFileURL.path
                                let totalSize = item.file.fileSize
                                let currentCopied = copiedBytes
                                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                                timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
                                timer.setEventHandler {
                                    let currentSize = (try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? 0
                                    Task { @MainActor in
                                        self.updateJob(jobID) {
                                            $0.progress.bytesTransferred = currentCopied + currentSize
                                            $0.progress.currentFile = "\(item.file.filename) (\(ByteCountFormatter.string(fromByteCount: currentSize, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)))"
                                        }
                                    }
                                }
                                timer.resume()
                                dispatchTimer = timer
                            }

                            try fm.copyItem(at: item.file.url, to: destFileURL)
                            dispatchTimer?.cancel()
                            copiedCount += 1
                            copiedBytes += item.file.fileSize
                        } catch {
                            return (copiedCount, skippedCount, copiedBytes, error)
                        }

                        await MainActor.run {
                            self.updateJob(jobID) {
                                $0.progress.filesTransferred = index + 1
                                $0.progress.bytesTransferred = copiedBytes
                            }
                        }
                    }
                    return (copiedCount, skippedCount, copiedBytes, nil)
                }.value

                if let error = copyResult.error {
                    if error is CancellationError { throw error }
                    throw error
                }

                // Hash synced files and record in journals
                updateJob(jobID) { $0.status = .hashing }

                for (index, item) in filesToCopy.enumerated() {
                    try Task.checkCancellation()

                    // Find the actual file path (may be in a titled folder)
                    let actualPath = findActualFilePath(
                        filename: item.file.filename,
                        expectedPath: item.destPath,
                        destRoot: destURL
                    ) ?? item.destPath
                    let destFileURL = URL(fileURLWithPath: actualPath)
                    guard fm.fileExists(atPath: actualPath) else { continue }

                    let sha256 = try await HashCache.shared.hashForFile(at: destFileURL)

                    try journalManager?.record(
                        sha256: sha256,
                        originalFilename: item.file.filename,
                        originalSourcePath: item.file.url.path,
                        currentPath: actualPath,
                        diskIdentifier: diskIdentifier,
                        diskName: diskName,
                        fileSize: item.file.fileSize,
                        captureDate: item.file.captureDate ?? Date(),
                        fileExtension: item.file.fileExtension,
                        deviceType: device.deviceType.rawValue
                    )

                    let relativePath = item.destPath.replacingOccurrences(of: destURL.path, with: "")
                    let entry = DecentralizedJournal.Entry(
                        sha256: sha256,
                        relativePath: relativePath,
                        originalFilename: item.file.filename,
                        originalSourcePath: item.file.url.path,
                        fileSize: item.file.fileSize,
                        captureDate: item.file.captureDate ?? Date(),
                        syncTimestamp: Date(),
                        deviceType: device.deviceType.rawValue
                    )
                    try DecentralizedJournal.appendEntry(
                        entry,
                        to: destURL,
                        diskIdentifier: diskIdentifier,
                        diskName: diskName
                    )

                    updateJob(jobID) {
                        $0.progress.filesTransferred = index + 1
                        $0.progress.currentFile = item.file.filename
                    }
                }

                // Save hash cache
                await HashCache.shared.saveToDisk()

                // Apply PROJECT.md titles to date folders (same as Reorganize)
                FileOrganizer.applyProjectTitles(in: destURL)
                FileOrganizer.refreshFinder(destURL)

                // Record sync timestamp for fast skip next time
                let dev = device
                let dest = destinationPath
                await Task.detached { self.recordSyncTimestamp(device: dev, destinationPath: dest) }.value

                updateJob(jobID) { $0.status = .completed }
            } catch is CancellationError {
                updateJob(jobID) { $0.status = .cancelled }
            } catch {
                updateJob(jobID) { $0.status = .failed("\(error)") }
            }
            syncTasks.removeValue(forKey: jobID)

            // Auto-cleanup: keep max 3 inactive jobs
            let inactive = activeSyncJobs.filter { !$0.status.isActive }
            if inactive.count > 3 {
                let toRemove = inactive.prefix(inactive.count - 3)
                activeSyncJobs.removeAll { job in toRemove.contains { $0.id == job.id } }
            }
        }
        syncTasks[jobID] = task
    }

    /// Find the actual path of a file, checking titled folder variants
    private func findActualFilePath(filename: String, expectedPath: String, destRoot: URL) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: expectedPath) { return expectedPath }

        let relative = expectedPath.replacingOccurrences(of: destRoot.path + "/", with: "")
        let parts = relative.split(separator: "/").map(String.init)

        for (i, part) in parts.enumerated() {
            guard part.count >= 8, part.prefix(8).allSatisfy(\.isNumber) else { continue }
            let datePrefix = String(part.prefix(8))
            let parentDir: URL
            if i == 0 {
                parentDir = destRoot
            } else {
                parentDir = destRoot.appendingPathComponent(parts[0..<i].joined(separator: "/"))
            }
            guard let siblings = try? fm.contentsOfDirectory(atPath: parentDir.path) else { continue }
            for sibling in siblings where sibling != part && sibling.hasPrefix(datePrefix) {
                var altParts = parts
                altParts[i] = sibling
                let altPath = destRoot.appendingPathComponent(altParts.joined(separator: "/")).path
                if fm.fileExists(atPath: altPath) {
                    return altPath
                }
            }
            break
        }
        return nil
    }

    /// Check if a file already exists on the destination, accounting for titled folders.
    /// e.g. pattern says ".../20251222/videos/" but file is in ".../20251222 - RC Car Vlog/videos/"
    private func fileAlreadyExists(filename: String, expectedSize: Int64, destPath: String, destRoot: URL) -> Bool {
        let fm = FileManager.default

        // Check exact path first
        if let attrs = try? fm.attributesOfItem(atPath: destPath),
           let size = attrs[.size] as? Int64,
           size == expectedSize {
            return true
        }

        // Check in titled folder variant
        // destPath is like ".../OsmoPocket3/20251222/videos/DJI_xxx.MP4"
        // Look for ".../OsmoPocket3/20251222 - */videos/DJI_xxx.MP4"
        let relative = destPath.replacingOccurrences(of: destRoot.path + "/", with: "")
        let parts = relative.split(separator: "/").map(String.init)

        // Find the date component and look for titled variants
        for (i, part) in parts.enumerated() {
            guard part.count >= 8, part.prefix(8).allSatisfy(\.isNumber) else { continue }
            let datePrefix = String(part.prefix(8))
            let parentDir: URL
            if i == 0 {
                parentDir = destRoot
            } else {
                parentDir = destRoot.appendingPathComponent(parts[0..<i].joined(separator: "/"))
            }

            guard let siblings = try? fm.contentsOfDirectory(atPath: parentDir.path) else { continue }
            for sibling in siblings where sibling != part && sibling.hasPrefix(datePrefix) {
                var altParts = parts
                altParts[i] = sibling
                let altPath = destRoot.appendingPathComponent(altParts.joined(separator: "/")).path
                if let attrs = try? fm.attributesOfItem(atPath: altPath),
                   let size = attrs[.size] as? Int64,
                   size == expectedSize {
                    return true
                }
            }
            break // only check the first date component
        }

        return false
    }

    private func updateJob(_ id: UUID, _ update: (inout SyncJob) -> Void) {
        if let idx = activeSyncJobs.firstIndex(where: { $0.id == id }) {
            update(&activeSyncJobs[idx])
        }
    }

    // MARK: - Persistence helpers

    private static func save<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Codable>(forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Caches directory listings and file existence checks to avoid repeated I/O during sync
private final class DirectoryListingCache: @unchecked Sendable {
    private let root: URL
    private var existingFiles: Set<String> = []  // all footage file paths on destination
    private var dateFolderMap: [String: String] = [:]  // datePrefix → actual folder name

    init(root: URL) {
        self.root = root
        buildIndex()
    }

    private func buildIndex() {
        let fm = FileManager.default

        // Walk the entire destination tree once and index all footage files
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            if DJIFilenameParser.isDJIFile(fileURL.lastPathComponent) {
                existingFiles.insert(fileURL.path)
            }
        }

        // Build date folder map from immediate subdirs (and their subdirs)
        func scanDateFolders(in dir: URL) {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            for name in contents {
                guard name.count >= 8, name.prefix(8).allSatisfy(\.isNumber) else {
                    // Recurse into non-date dirs (e.g. OsmoPocket3/)
                    let subdir = dir.appendingPathComponent(name)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: subdir.path, isDirectory: &isDir), isDir.boolValue {
                        scanDateFolders(in: subdir)
                    }
                    continue
                }
                let datePrefix = String(name.prefix(8))
                // Prefer longer name (titled)
                if let existing = dateFolderMap[datePrefix] {
                    if name.count > existing.count { dateFolderMap[datePrefix] = name }
                } else {
                    dateFolderMap[datePrefix] = name
                }
            }
        }
        scanDateFolders(in: root)
    }

    /// Check if a file exists on the destination, accounting for titled folders
    func fileExists(filename: String, expectedSize: Int64, patternPath: String) -> Bool {
        let fm = FileManager.default

        // Check exact path
        if existingFiles.contains(patternPath) {
            if let attrs = try? fm.attributesOfItem(atPath: patternPath),
               let size = attrs[.size] as? Int64, size == expectedSize {
                return true
            }
        }

        // Check titled folder variant
        let relative = patternPath.replacingOccurrences(of: root.path + "/", with: "")
        let parts = relative.split(separator: "/").map(String.init)

        for (i, part) in parts.enumerated() {
            guard part.count >= 8, part.prefix(8).allSatisfy(\.isNumber) else { continue }
            let datePrefix = String(part.prefix(8))
            guard let actualFolder = dateFolderMap[datePrefix], actualFolder != part else { continue }

            var altParts = parts
            altParts[i] = actualFolder
            let altPath = root.appendingPathComponent(altParts.joined(separator: "/")).path

            if existingFiles.contains(altPath) {
                if let attrs = try? fm.attributesOfItem(atPath: altPath),
                   let size = attrs[.size] as? Int64, size == expectedSize {
                    return true
                }
            }
            break
        }

        return false
    }
}
