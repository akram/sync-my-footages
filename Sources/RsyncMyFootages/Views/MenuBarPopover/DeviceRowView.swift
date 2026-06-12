import SwiftUI

struct DeviceRowView: View {
    @Environment(AppState.self) private var appState
    let device: DJIDevice

    private var isSyncing: Bool {
        appState.activeSyncJobs.contains { $0.device == device && $0.status.isActive }
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
                Button("Sync") {
                    WindowManager.shared.openSyncConfig(device: device, appState: appState)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
