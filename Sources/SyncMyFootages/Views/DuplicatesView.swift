import SwiftUI

struct DuplicatesView: View {
    @State private var scanResult: DuplicateScanner.ScanResult?
    @State private var isScanning = false
    @State private var scanProgress = ""
    @State private var scanPercent = 0.0
    @State private var showFolderPicker = false
    @State private var scanDirectory: URL?
    @State private var selectedForDeletion: Set<String> = []  // paths to delete

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Duplicate Scanner")
                    .font(.title3.bold())
                Spacer()
                Button("Scan folder...") {
                    showFolderPicker = true
                }
                .disabled(isScanning)
            }
            .padding(20)
            .background(.bar)

            Divider()

            // Content
            if isScanning {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView(value: scanPercent)
                        .frame(width: 300)
                    Text(scanProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let result = scanResult {
                if result.duplicates.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No duplicates found",
                        systemImage: "checkmark.circle",
                        description: Text("\(result.totalFilesScanned) files scanned")
                    )
                    Spacer()
                } else {
                    resultView(result)
                }
            } else {
                Spacer()
                ContentUnavailableView(
                    "Select a folder to scan",
                    systemImage: "magnifyingglass",
                    description: Text("The scanner will find duplicate footage files by SHA256 hash")
                )
                Spacer()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                scanDirectory = url
                startScan(url)
            }
        }
    }

    // MARK: - Result view

    private func resultView(_ result: DuplicateScanner.ScanResult) -> some View {
        VStack(spacing: 0) {
            // Summary bar
            HStack(spacing: 20) {
                StatLabel(label: "Scanned", value: "\(result.totalFilesScanned) files")
                StatLabel(label: "Duplicate groups", value: "\(result.duplicates.count)")
                StatLabel(label: "Extra copies", value: "\(result.totalDuplicateFiles)")
                StatLabel(label: "Wasted space", value: ByteCountFormatter.string(fromByteCount: result.totalWastedBytes, countStyle: .file), color: .red)
            }
            .padding(16)
            .background(.bar)

            Divider()

            // Duplicate groups list
            List {
                ForEach(result.duplicates) { group in
                    duplicateGroupView(group)
                }
            }

            if !selectedForDeletion.isEmpty {
                Divider()
                deleteFooter
            }
        }
    }

    private func duplicateGroupView(_ group: DuplicateScanner.DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(.orange)
                Text(group.filename)
                    .font(.callout.bold())
                Spacer()
                Text("\(group.count) copies")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                Text("wasting \(ByteCountFormatter.string(fromByteCount: group.wastedBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("SHA256: \(group.sha256.prefix(24))...")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            ForEach(Array(group.paths.enumerated()), id: \.offset) { index, path in
                HStack(spacing: 6) {
                    if index == 0 {
                        // First copy = keep
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        // Extra copies = can be deleted
                        Button {
                            toggleDeletion(path)
                        } label: {
                            Image(systemName: selectedForDeletion.contains(path) ? "trash.circle.fill" : "circle")
                                .foregroundStyle(selectedForDeletion.contains(path) ? .red : .secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }

                    Text(shortenPath(path))
                        .font(.caption.monospaced())
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    if index == 0 {
                        Text("KEEP")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Delete footer

    private var deleteFooter: some View {
        HStack {
            Text("\(selectedForDeletion.count) files selected for deletion")
                .font(.caption)

            let totalToFree = estimateFreedBytes()
            Text("(\(ByteCountFormatter.string(fromByteCount: totalToFree, countStyle: .file)) to free)")
                .font(.caption)
                .foregroundStyle(.red)

            Spacer()

            Button("Select all extras") {
                selectAllExtras()
            }
            .font(.caption)
            .buttonStyle(.borderless)

            Button("Delete selected") {
                deleteSelected()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(16)
        .background(.bar)
    }

    // MARK: - Actions

    private func startScan(_ url: URL) {
        isScanning = true
        scanResult = nil
        selectedForDeletion = []

        Task {
            let result = await DuplicateScanner.scan(directory: url) { message, percent in
                Task { @MainActor in
                    scanProgress = message
                    scanPercent = percent
                }
            }
            scanResult = result
            isScanning = false
        }
    }

    private func toggleDeletion(_ path: String) {
        if selectedForDeletion.contains(path) {
            selectedForDeletion.remove(path)
        } else {
            selectedForDeletion.insert(path)
        }
    }

    private func selectAllExtras() {
        guard let result = scanResult else { return }
        for group in result.duplicates {
            // Skip first path (keep), select the rest
            for path in group.paths.dropFirst() {
                selectedForDeletion.insert(path)
            }
        }
    }

    private func estimateFreedBytes() -> Int64 {
        guard let result = scanResult else { return 0 }
        var total: Int64 = 0
        for group in result.duplicates {
            for path in group.paths where selectedForDeletion.contains(path) {
                total += group.fileSize
            }
        }
        return total
    }

    private func deleteSelected() {
        let fm = FileManager.default
        for path in selectedForDeletion {
            try? fm.removeItem(atPath: path)
        }
        selectedForDeletion = []

        // Re-scan
        if let dir = scanDirectory {
            startScan(dir)
        }
    }

    private func shortenPath(_ path: String) -> String {
        if let dir = scanDirectory {
            return path.replacingOccurrences(of: dir.path, with: "...")
        }
        return path
    }
}

private struct StatLabel: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
