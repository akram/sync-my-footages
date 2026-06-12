import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    // MARK: - Connected devices
    var connectedDevices: [DJIDevice] = []

    // MARK: - Active sync jobs
    var activeSyncJobs: [SyncJob] = []

    // MARK: - Device profiles (persisted via UserDefaults)
    var deviceProfiles: [DeviceProfile] = [] {
        didSet { Self.save(deviceProfiles, forKey: "deviceProfiles") }
    }

    // MARK: - Destination disks
    var destinationDisks: [DestinationDisk] = [] {
        didSet { Self.save(destinationDisks, forKey: "destinationDisks") }
    }

    // MARK: - UI state
    var selectedDeviceForSync: DJIDevice?

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
        }
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

    // MARK: - Sync

    /// Sync only new files (not already present on destination)
    func syncDevice(_ device: DJIDevice, to destinationPath: String, onlyFiles: [(file: FootageFile, destPath: String)]? = nil) {
        let job = SyncJob(device: device, destinationPath: destinationPath)
        activeSyncJobs.append(job)
        let jobID = job.id

        Task {
            do {
                let destURL = URL(fileURLWithPath: destinationPath)
                let fm = FileManager.default
                let diskIdentifier = destURL.lastPathComponent
                let diskName = destURL.lastPathComponent

                // Determine which files to copy
                let filesToCopy: [(file: FootageFile, destPath: String)]
                if let provided = onlyFiles {
                    filesToCopy = provided
                } else {
                    // Fallback: scan and build full list
                    updateJob(jobID) { $0.status = .scanning }
                    let files = try FileOrganizer.scanDevice(device)
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

                // Copy each file individually using rsync
                for (index, item) in filesToCopy.enumerated() {
                    let sourceURL = item.file.url
                    let destFileURL = URL(fileURLWithPath: item.destPath)
                    let destDir = destFileURL.deletingLastPathComponent()

                    // Create destination directory
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                    // Skip if already exists with same size
                    if fm.fileExists(atPath: item.destPath),
                       let attrs = try? fm.attributesOfItem(atPath: item.destPath),
                       let size = attrs[.size] as? Int64,
                       size == item.file.fileSize {
                        updateJob(jobID) {
                            $0.progress.filesTransferred = index + 1
                            $0.progress.currentFile = item.file.filename
                        }
                        continue
                    }

                    // Use rsync for the single file (preserves timestamps, shows progress)
                    _ = try await rsyncEngine.sync(
                        source: sourceURL,
                        destination: destFileURL
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.updateJob(jobID) {
                                $0.progress.currentFile = item.file.filename
                                $0.progress.bytesTransferred = progress.bytesTransferred
                            }
                        }
                    }

                    updateJob(jobID) {
                        $0.progress.filesTransferred = index + 1
                    }
                }

                // Hash synced files and record in journals
                updateJob(jobID) { $0.status = .hashing }

                for (index, item) in filesToCopy.enumerated() {
                    let destFileURL = URL(fileURLWithPath: item.destPath)
                    guard fm.fileExists(atPath: item.destPath) else { continue }

                    let sha256 = try await HashingService.sha256(of: destFileURL)

                    try journalManager?.record(
                        sha256: sha256,
                        originalFilename: item.file.filename,
                        originalSourcePath: item.file.url.path,
                        currentPath: item.destPath,
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

                updateJob(jobID) { $0.status = .completed }
            } catch {
                updateJob(jobID) { $0.status = .failed(error.localizedDescription) }
            }
        }
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
