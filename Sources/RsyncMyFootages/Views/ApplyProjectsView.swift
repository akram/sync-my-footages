import SwiftUI

/// Scans a destination for PROJECT.md files, renames directories with project titles,
/// and merges directories that share the same title
struct ApplyProjectsView: View {
    @Environment(AppState.self) private var appState
    @State private var showFolderPicker = false
    @State private var selectedDirectory: URL?
    @State private var projects: [ProjectFile] = []
    @State private var result: ProjectManager.ApplyResult?
    @State private var isApplying = false
    @State private var separator = " - "

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Apply Projects")
                        .font(.title3.bold())
                    Text("Scan a folder for PROJECT.md files, rename directories with project titles, and merge same-title folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Folder selection
                    GroupBox {
                        HStack {
                            if let dir = selectedDirectory {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(dir.path)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            } else {
                                Text("No folder selected")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Choose folder...") {
                                showFolderPicker = true
                            }
                        }
                    } label: {
                        Label("Folder", systemImage: "folder")
                    }

                    // Separator config
                    GroupBox {
                        HStack {
                            Text("Separator between date and title:")
                                .font(.callout)
                            TextField("", text: $separator)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .font(.callout.monospaced())
                            Text("→ 20251206\(separator)RC Car Vlog")
                                .font(.caption.monospaced())
                                .foregroundStyle(.blue)
                        }
                    } label: {
                        Label("Format", systemImage: "textformat")
                    }

                    // Found projects
                    if !projects.isEmpty {
                        GroupBox {
                            ForEach(projects) { project in
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading) {
                                        Text(project.title)
                                            .font(.callout.bold())
                                        Text(URL(fileURLWithPath: project.directoryPath).lastPathComponent)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    // Show if rename is needed
                                    let dirName = URL(fileURLWithPath: project.directoryPath).lastPathComponent
                                    if dirName.contains(project.sanitizedTitle) {
                                        Text("OK")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("→ \(dirName)\(separator)\(project.sanitizedTitle)")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } label: {
                            Label("\(projects.count) project(s) found", systemImage: "doc.text.magnifyingglass")
                        }
                    }

                    // Result
                    if let result {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                if !result.renamed.isEmpty {
                                    ForEach(result.renamed, id: \.from) { item in
                                        HStack {
                                            Image(systemName: "arrow.right")
                                                .foregroundStyle(.blue)
                                            Text(item.from)
                                                .font(.caption.monospaced())
                                                .strikethrough()
                                                .foregroundStyle(.secondary)
                                            Text(item.to)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                if !result.merged.isEmpty {
                                    ForEach(result.merged, id: \.from) { item in
                                        HStack {
                                            Image(systemName: "arrow.triangle.merge")
                                                .foregroundStyle(.green)
                                            Text(item.from)
                                                .font(.caption.monospaced())
                                            Text("→ merged into \(item.into)")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                if !result.errors.isEmpty {
                                    ForEach(result.errors, id: \.self) { error in
                                        Label(error, systemImage: "xmark.circle")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                                if result.renamed.isEmpty && result.merged.isEmpty && result.errors.isEmpty {
                                    Label("All directories already have correct names", systemImage: "checkmark.circle")
                                        .font(.callout)
                                        .foregroundStyle(.green)
                                }
                            }
                        } label: {
                            Label("Result", systemImage: "checkmark.circle")
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                Button("Apply") {
                    apply()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDirectory == nil || projects.isEmpty || isApplying)
            }
            .padding(20)
            .background(.bar)
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { res in
            if case .success(let url) = res {
                selectedDirectory = url
                scanForProjects(in: url)
            }
        }
    }

    private func scanForProjects(in directory: URL) {
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
        projects = ProjectManager.scan(directory: directory)
        result = nil
    }

    private func apply() {
        guard let dir = selectedDirectory else { return }
        let accessing = dir.startAccessingSecurityScopedResource()
        defer { if accessing { dir.stopAccessingSecurityScopedResource() } }
        isApplying = true
        result = ProjectManager.applyProjects(in: dir, separator: separator)
        projects = ProjectManager.scan(directory: dir)
        isApplying = false
    }
}
