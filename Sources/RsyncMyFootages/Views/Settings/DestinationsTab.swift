import SwiftUI

struct DestinationsTab: View {
    @Environment(AppState.self) private var appState
    @State private var showFilePicker = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Destination Disks") {
                ForEach($state.destinationDisks) { $disk in
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

                        Toggle("Backup", isOn: $disk.isBackup)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                .onDelete { indexSet in
                    appState.destinationDisks.remove(atOffsets: indexSet)
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
                let disk = DestinationDisk(
                    name: url.lastPathComponent,
                    path: url.path,
                    diskIdentifier: url.lastPathComponent
                )
                appState.destinationDisks.append(disk)
            }
        }
    }
}
