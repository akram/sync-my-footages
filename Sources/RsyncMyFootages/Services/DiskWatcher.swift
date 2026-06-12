import Foundation
import DiskArbitration

/// Watches for volume mount/unmount events using DiskArbitration framework.
/// Falls back to polling /Volumes/ if DA session cannot be created.
final class DiskWatcher: @unchecked Sendable {
    private let onAppear: @Sendable (URL) async -> Void
    private let onDisappear: @Sendable (URL) async -> Void
    private var session: DASession?
    private let queue = DispatchQueue(label: "com.rsync-my-footages.disk-watcher")
    private var fallbackSource: DispatchSourceFileSystemObject?
    private var knownVolumes: Set<String> = []

    init(
        onAppear: @escaping @Sendable (URL) async -> Void,
        onDisappear: @escaping @Sendable (URL) async -> Void
    ) {
        self.onAppear = onAppear
        self.onDisappear = onDisappear
    }

    func start() {
        // Try DiskArbitration first
        if let daSession = DASessionCreate(kCFAllocatorDefault) {
            self.session = daSession
            DASessionSetDispatchQueue(daSession, queue)

            let ctx = Unmanaged.passUnretained(self).toOpaque()

            DARegisterDiskAppearedCallback(daSession, nil, { disk, ctx in
                guard let ctx else { return }
                let watcher = Unmanaged<DiskWatcher>.fromOpaque(ctx).takeUnretainedValue()
                watcher.handleDiskAppeared(disk)
            }, ctx)

            DARegisterDiskDisappearedCallback(daSession, nil, { disk, ctx in
                guard let ctx else { return }
                let watcher = Unmanaged<DiskWatcher>.fromOpaque(ctx).takeUnretainedValue()
                watcher.handleDiskDisappeared(disk)
            }, ctx)
        } else {
            // Fallback: watch /Volumes directory for changes
            startFallbackWatcher()
        }

        // Also scan existing volumes at startup
        scanExistingVolumes()
    }

    func stop() {
        if let session {
            DAUnregisterCallback(session, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), nil)
            self.session = nil
        }
        fallbackSource?.cancel()
        fallbackSource = nil
    }

    // MARK: - DiskArbitration callbacks

    private func handleDiskAppeared(_ disk: DADisk) {
        guard let desc = DADiskCopyDescription(disk) as? [CFString: Any],
              let volumePathURL = desc[kDADiskDescriptionVolumePathKey] as? URL else {
            return
        }
        let callback = onAppear
        Task { await callback(volumePathURL) }
    }

    private func handleDiskDisappeared(_ disk: DADisk) {
        guard let desc = DADiskCopyDescription(disk) as? [CFString: Any],
              let volumePathURL = desc[kDADiskDescriptionVolumePathKey] as? URL else {
            return
        }
        let callback = onDisappear
        Task { await callback(volumePathURL) }
    }

    // MARK: - Fallback watcher

    private func startFallbackWatcher() {
        let fd = open("/Volumes", O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.checkVolumeChanges()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fallbackSource = source

        // Record initial state
        knownVolumes = currentVolumeNames()
    }

    private func checkVolumeChanges() {
        let current = currentVolumeNames()
        let appeared = current.subtracting(knownVolumes)
        let disappeared = knownVolumes.subtracting(current)

        for name in appeared {
            let url = URL(fileURLWithPath: "/Volumes/\(name)")
            let callback = onAppear
            Task { await callback(url) }
        }

        for name in disappeared {
            let url = URL(fileURLWithPath: "/Volumes/\(name)")
            let callback = onDisappear
            Task { await callback(url) }
        }

        knownVolumes = current
    }

    private func currentVolumeNames() -> Set<String> {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: "/Volumes") else {
            return []
        }
        return Set(contents)
    }

    // MARK: - Initial scan

    private func scanExistingVolumes() {
        let fm = FileManager.default
        guard let volumes = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) else { return }

        for volume in volumes {
            let callback = onAppear
            Task { await callback(volume) }
        }
    }
}
