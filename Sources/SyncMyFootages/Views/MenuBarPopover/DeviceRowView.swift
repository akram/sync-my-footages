import SwiftUI

struct DeviceRowView: View {
    @Environment(AppState.self) private var appState
    let device: DJIDevice

    private var isSyncing: Bool {
        appState.activeSyncJobs.contains { $0.device == device && $0.status.isActive }
    }

    /// Get saved destinations for this device type
    private var savedDestinations: [String] {
        UserDefaults.standard.stringArray(forKey: "syncDestinations_\(device.deviceType.rawValue)") ?? []
    }

    private var hasDestinations: Bool {
        !savedDestinations.isEmpty || !appState.destinationDisks.isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.deviceType.iconName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceType.rawValue)
                    .font(.system(.body, weight: .medium))
                HStack(spacing: 4) {
                    Text(device.volumeName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if device.storageType != .unknown {
                        Text("(\(device.storageType.rawValue))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isSyncing {
                ProgressView()
                    .controlSize(.small)
            } else {
                HStack(spacing: 0) {
                    Button {
                        startQuickSync()
                    } label: {
                        Text("Sync")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasDestinations)

                    Divider()
                        .frame(height: 14)
                        .overlay(Color.white.opacity(0.3))

                    Menu {
                        Button("Configure sync...") {
                            WindowManager.shared.openSyncConfig(device: device, appState: appState)
                        }
                        if !savedDestinations.isEmpty {
                            Divider()
                            ForEach(savedDestinations, id: \.self) { path in
                                let name = URL(fileURLWithPath: path).lastPathComponent
                                let available = FileManager.default.fileExists(atPath: path)
                                Button {
                                    appState.syncDevice(device, to: path)
                                } label: {
                                    Label(name, systemImage: available ? "externaldrive.fill" : "externaldrive.badge.xmark")
                                }
                                .disabled(!available)
                            }
                        }
                        Divider()
                        Button {
                            ejectVolume()
                        } label: {
                            Label("Eject \(device.volumeName)", systemImage: "eject.fill")
                        }
                    } label: {
                        EmptyView()
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16)
                }
                .background(.blue, in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    private func ejectVolume() {
        let volumePath = device.volumePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", volumePath.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.terminationHandler = { _ in
            Task { @MainActor in
                appState.connectedDevices.removeAll { $0.volumePath == volumePath }
            }
        }
    }

    private func startQuickSync() {
        // Use saved destinations, or all configured destinations
        let destinations: [String]
        if !savedDestinations.isEmpty {
            destinations = savedDestinations.filter { FileManager.default.fileExists(atPath: $0) }
        } else {
            destinations = appState.destinationDisks.filter(\.isAvailable).map(\.path)
        }

        for dest in destinations {
            appState.syncDevice(device, to: dest)
        }
    }
}
