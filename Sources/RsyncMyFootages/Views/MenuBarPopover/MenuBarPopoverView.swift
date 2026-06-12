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
                HStack {
                    Text("Active Syncs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if appState.activeSyncJobs.contains(where: { !$0.status.isActive }) {
                        Button("Clear") {
                            appState.activeSyncJobs.removeAll { !$0.status.isActive }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                ForEach(appState.activeSyncJobs) { job in
                    SyncProgressView(job: job)
                }
            }

            Divider()

            // Footer
            HStack(spacing: 0) {
                Menu {
                    Button("Dashboard") {
                        WindowManager.shared.openDashboard(appState: appState)
                    }
                    Button("Duplicates") {
                        WindowManager.shared.openDuplicates()
                    }
                    Button("Projects") {
                        WindowManager.shared.openApplyProjects(appState: appState)
                    }
                    Divider()
                    Button("Settings...") {
                        WindowManager.shared.openSettings(appState: appState)
                    }
                    Divider()
                    Button(appState.isDemoActive ? "Stop Demo" : "Demo Mode") {
                        appState.toggleDemo()
                    }
                    Divider()
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    EmptyView()
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)

                Text("More")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
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
