import SwiftUI

struct DestinationsTab: View {
    @Environment(AppState.self) private var appState
    @State private var showFilePicker = false

    var body: some View {
        Form {
            Section("Destination Disks") {
                if appState.destinationDisks.isEmpty {
                    Text("No destinations configured. Add a folder to start syncing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(appState.destinationDisks) { disk in
                    HStack {
                        Image(systemName: disk.isAvailable ? "externaldrive.fill" : "externaldrive.badge.xmark")
                            .foregroundStyle(disk.isAvailable ? .green : .red)

                        VStack(alignment: .leading) {
                            Text(disk.name)
                                .font(.body)
                            Text(disk.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: disk.path)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Open in Finder")
                        .disabled(!disk.isAvailable)

                        Button {
                            toggleBackup(disk)
                        } label: {
                            Text(disk.isBackup ? "Backup" : "Primary")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(disk.isBackup ? .blue.opacity(0.2) : .secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.borderless)
                        .help("Toggle backup status")

                        Button {
                            removeDisk(disk)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove destination")
                    }
                }

                Button("Add Destination...") {
                    showFilePicker = true
                }
            }

            Section {
                Text("Files will be synced to all configured destinations. Backup destinations receive copies in parallel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                guard !appState.destinationDisks.contains(where: { $0.path == url.path }) else { return }
                let disk = DestinationDisk(
                    name: url.lastPathComponent,
                    path: url.path,
                    diskIdentifier: url.lastPathComponent
                )
                appState.destinationDisks.append(disk)
                appState.saveSettings()
            }
        }
    }

    private func toggleBackup(_ disk: DestinationDisk) {
        guard let index = appState.destinationDisks.firstIndex(where: { $0.id == disk.id }) else { return }
        appState.destinationDisks[index].isBackup.toggle()
        appState.saveSettings()
    }

    private func removeDisk(_ disk: DestinationDisk) {
        appState.destinationDisks.removeAll { $0.id == disk.id }
        appState.saveSettings()
    }
}
