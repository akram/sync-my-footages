import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("RSync My Footages")
                    .font(.headline)
                Spacer()
                Button {
                    appState.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan volumes")
            }

            Divider()

            // Connected devices
            if appState.connectedDevices.isEmpty {
                HStack {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(.secondary)
                    Text("No DJI devices connected")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(appState.connectedDevices) { device in
                    DeviceRowView(device: device)
                }
            }

            // Active syncs
            if !appState.activeSyncJobs.isEmpty {
                Divider()
                Text("Active Syncs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(appState.activeSyncJobs) { job in
                    SyncProgressView(job: job)
                }
            }

            Divider()

            // Footer actions
            HStack {
                Button("Dashboard") {
                    WindowManager.shared.openDashboard(appState: appState)
                }
                .buttonStyle(.borderless)

                Button("Duplicates") {
                    WindowManager.shared.openDuplicates()
                }
                .buttonStyle(.borderless)

                Button("Projects") {
                    WindowManager.shared.openApplyProjects(appState: appState)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Settings...") {
                    WindowManager.shared.openSettings(appState: appState)
                }
                .buttonStyle(.borderless)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)

            // Demo mode toggle
            HStack {
                Button(appState.isDemoActive ? "Stop Demo" : "Demo Mode") {
                    appState.toggleDemo()
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundStyle(appState.isDemoActive ? .orange : .secondary)

                if appState.isDemoActive {
                    Text("Simulated device & destination active")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear {
            if appState.diskWatcher == nil {
                appState.start()
            }
        }
    }
}
