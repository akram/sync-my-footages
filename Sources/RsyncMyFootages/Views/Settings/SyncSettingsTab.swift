import SwiftUI

struct SyncSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("defaultVerificationLevel") private var verificationLevel = 2
    @AppStorage("organizationPattern") private var organizationPattern = FileOrganizer.defaultPattern
    @AppStorage("autoHashAfterSync") private var autoHashAfterSync = true
    @AppStorage("showNotifications") private var showNotifications = true

    @State private var showFolderPicker = false
    @State private var reorganizeResult: String?
    @State private var isReorganizing = false
    @State private var reorganizeProgress = ""

    var body: some View {
        Form {
            Section("File Organization") {
                TextField("Pattern", text: $organizationPattern)
                    .font(.body.monospaced())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(FileOrganizer.patternPreview(organizationPattern))
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Available tokens:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        TokenBadge("{device}", hint: "OsmoPocket3")
                        TokenBadge("{year}", hint: "2025")
                        TokenBadge("{month}", hint: "12")
                        TokenBadge("{day}", hint: "22")
                        TokenBadge("{type}", hint: "videos, audios, lowres")
                    }
                    Text("Place a PROJECT.md in a date folder to rename it with the project title.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if organizationPattern != FileOrganizer.defaultPattern {
                    Button("Reset to default") {
                        organizationPattern = FileOrganizer.defaultPattern
                    }
                    .font(.caption)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reorganize files to match the pattern and apply PROJECT.md titles.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isReorganizing {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(reorganizeProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Reorganize folder...") {
                            showFolderPicker = true
                        }
                        .controlSize(.small)
                    }

                    if let result = reorganizeResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("Verification") {
                Picker("Default verification level", selection: $verificationLevel) {
                    Text("Quick (path exists)").tag(1)
                    Text("Medium (path + size)").tag(2)
                    Text("Full (SHA256)").tag(3)
                }

                Toggle("Auto-hash files after sync", isOn: $autoHashAfterSync)
                    .help("Compute SHA256 for each file after copying. Required for journal tracking.")
            }

            Section("Notifications") {
                Toggle("Show notifications", isOn: $showNotifications)
                    .help("Notify when devices are connected and syncs complete.")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                reorganize(directory: url)
            }
        }
    }

    private func reorganize(directory: URL) {
        isReorganizing = true
        reorganizeResult = nil
        let pattern = organizationPattern

        let accessing = directory.startAccessingSecurityScopedResource()
        let deviceType = DeviceIdentifier.identifyFromVideoFiles(in: directory) ?? .osmoPocket3

        Task.detached {
            let result = FileOrganizer.reorganize(
                directory: directory,
                deviceType: deviceType,
                fromPattern: pattern,
                toPattern: pattern
            ) { file, _ in
                Task { @MainActor in
                    reorganizeProgress = file
                }
            }

            await MainActor.run {
                if accessing { directory.stopAccessingSecurityScopedResource() }
                isReorganizing = false
                reorganizeResult = "\(result.moved) moved, \(result.skipped) unchanged, \(result.errors) errors"
            }
        }
    }
}

private struct TokenBadge: View {
    let token: String
    let hint: String

    init(_ token: String, hint: String = "") {
        self.token = token
        self.hint = hint
    }

    var body: some View {
        Text(token)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .help(hint)
    }
}
