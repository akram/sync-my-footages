import SwiftUI

/// Window to configure and launch a sync operation for a specific device
struct SyncConfigView: View {
    @Environment(AppState.self) private var appState

    let device: DJIDevice

    @State private var selectedDestinations: Set<String> = [] {
        didSet { saveSelectedDestinations() }
    }
    @State private var customDestinations: [CustomDestination] = []
    @State private var verificationLevel: Int = 2
    @State private var autoHash = true
    @State private var scannedFiles: [FootageFile] = []
    @State private var isScanning = false
    @State private var showAddFolder = false

    // Analysis state
    @State private var analysisResults: [String: DestinationAnalyzer.AnalysisResult] = [:]
    @State private var isAnalyzing = false
    @State private var analyzeProgress = ""
    @State private var analyzePercent = 0.0

    // Misplaced file actions: path → action
    @State private var misplacedActions: [String: MisplacedAction] = [:]


    enum MisplacedAction: String, CaseIterable {
        case skip = "Leave in place"
        case move = "Move to pattern"
    }

    struct CustomDestination: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let path: String
    }

    private var totalSize: Int64 {
        scannedFiles.reduce(0) { $0 + $1.fileSize }
    }

    private var videoCount: Int {
        scannedFiles.filter { Constants.videoExtensions.contains($0.fileExtension) }.count
    }

    private var hasDestinations: Bool {
        !selectedDestinations.isEmpty
    }

    private var hasAnalysis: Bool {
        !analysisResults.isEmpty
    }


    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceSection
                    destinationsSection
                    if hasAnalysis {
                        analysisSection
                    }
                    optionsSection
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 620)
        .onAppear {
            loadSelectedDestinations()
            scanDevice()
        }
        .fileImporter(isPresented: $showAddFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let dest = CustomDestination(name: url.lastPathComponent, path: url.path)
                customDestinations.append(dest)
                selectedDestinations.insert(url.path)
            }
        }
        .onChange(of: selectedDestinations) {
            // Re-analyze when destinations change
            if !scannedFiles.isEmpty && !selectedDestinations.isEmpty {
                analyzeDestinations()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: device.deviceType.iconName)
                .font(.title)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("Sync \(device.deviceType.rawValue)")
                    .font(.title3.bold())
                HStack(spacing: 4) {
                    Text(device.volumeName)
                    if device.storageType != .unknown {
                        Text("(\(device.storageType.rawValue))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(.bar)
    }

    // MARK: - Source section

    private var sourceSection: some View {
        GroupBox {
            if isScanning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning files...")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("\(scannedFiles.count) files", systemImage: "doc.on.doc")
                        Spacer()
                        Label("\(videoCount) videos", systemImage: "film")
                        Spacer()
                        Label(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file), systemImage: "externaldrive")
                    }
                    .font(.callout)

                    let groups = FileOrganizer.groupByDate(scannedFiles)
                    if !groups.isEmpty {
                        Divider()
                        ForEach(groups, id: \.date) { group in
                            HStack {
                                Text(group.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption.bold())
                                Spacer()
                                Text("\(group.files.count) files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(
                                    fromByteCount: group.files.reduce(0) { $0 + $1.fileSize },
                                    countStyle: .file
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Source", systemImage: "camera")
        }
    }

    // MARK: - Destinations section

    private var destinationsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(appState.destinationDisks) { disk in
                    destinationRow(
                        name: disk.name,
                        path: disk.path,
                        isAvailable: disk.isAvailable,
                        isBackup: disk.isBackup,
                        isSelected: selectedDestinations.contains(disk.path),
                        toggle: { toggleDestination(disk.path) }
                    )
                }

                ForEach(customDestinations) { dest in
                    destinationRow(
                        name: dest.name,
                        path: dest.path,
                        isAvailable: FileManager.default.fileExists(atPath: dest.path),
                        isBackup: false,
                        isSelected: selectedDestinations.contains(dest.path),
                        toggle: { toggleDestination(dest.path) }
                    )
                }

                Button {
                    showAddFolder = true
                } label: {
                    Label("Add destination...", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)

                if !hasDestinations {
                    Text("Select at least one destination to sync.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } label: {
            Label("Destinations", systemImage: "externaldrive")
        }
    }

    // MARK: - Analysis section

    private var analysisSection: some View {
        GroupBox {
            if isAnalyzing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: analyzePercent)
                    Text(analyzeProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(analysisResults.keys.sorted()), id: \.self) { destPath in
                        if let result = analysisResults[destPath] {
                            destAnalysisView(destPath: destPath, result: result)
                        }
                    }
                }
            }
        } label: {
            Label("Analysis", systemImage: "magnifyingglass")
        }
    }

    private func destAnalysisView(destPath: String, result: DestinationAnalyzer.AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(URL(fileURLWithPath: destPath).lastPathComponent)
                .font(.callout.bold())

            // Summary badges
            HStack(spacing: 12) {
                badge("\(result.newCount) new", icon: "plus.circle.fill", color: .blue)
                badge("\(result.skippedCount) already synced", icon: "checkmark.circle.fill", color: .green)
                if result.misplacedCount > 0 {
                    badge("\(result.misplacedCount) misplaced", icon: "exclamationmark.triangle.fill", color: .orange)
                }
            }
            .font(.caption)

            if result.newCount > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: result.newBytes, countStyle: .file)) to copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Misplaced files — user chooses per file or bulk
            if result.misplacedCount > 0 {
                Divider()

                HStack {
                    Text("Misplaced files")
                        .font(.caption.bold())
                    Spacer()
                    Button("All: leave") { bulkMisplacedAction(.skip, result: result) }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    Button("All: move") { bulkMisplacedAction(.move, result: result) }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                }

                ForEach(result.misplaced, id: \.file.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.file.filename)
                            .font(.caption.monospaced())
                        HStack(spacing: 4) {
                            Text("Found at:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(shortenPath(item.currentPath))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        HStack(spacing: 4) {
                            Text("Expected:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(shortenPath(item.expectedPath))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Picker("", selection: misplacedBinding(for: item.currentPath)) {
                            ForEach(MisplacedAction.allCases, id: \.self) { action in
                                Text(action.rawValue).tag(action)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func badge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .foregroundStyle(color)
    }

    private func shortenPath(_ path: String) -> String {
        // Remove the destination root to show relative path
        for dest in selectedDestinations {
            if path.hasPrefix(dest) {
                return "..." + path.dropFirst(dest.count)
            }
        }
        return path
    }

    private func misplacedBinding(for path: String) -> Binding<MisplacedAction> {
        Binding(
            get: { misplacedActions[path] ?? .skip },
            set: { misplacedActions[path] = $0 }
        )
    }

    private func bulkMisplacedAction(_ action: MisplacedAction, result: DestinationAnalyzer.AnalysisResult) {
        for item in result.misplaced {
            misplacedActions[item.currentPath] = action
        }
    }

    // MARK: - Destination row

    private func destinationRow(
        name: String,
        path: String,
        isAvailable: Bool,
        isBackup: Bool,
        isSelected: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.borderless)

            Image(systemName: isAvailable ? "externaldrive.fill" : "externaldrive.badge.xmark")
                .foregroundStyle(isAvailable ? .green : .red)

            VStack(alignment: .leading) {
                HStack {
                    Text(name)
                        .font(.callout)
                    if isBackup {
                        Text("BACKUP")
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if !isAvailable {
                Text("Unavailable")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .opacity(isAvailable ? 1 : 0.6)
    }

    private func toggleDestination(_ path: String) {
        if selectedDestinations.contains(path) {
            selectedDestinations.remove(path)
            analysisResults.removeValue(forKey: path)
        } else {
            selectedDestinations.insert(path)
        }
    }

    // MARK: - Options section

    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Verification after sync", selection: $verificationLevel) {
                    Text("Quick (path exists)").tag(1)
                    Text("Medium (path + size)").tag(2)
                    Text("Full (SHA256 checksum)").tag(3)
                }

                Toggle("Compute SHA256 hashes (required for journal)", isOn: $autoHash)
            }
        } label: {
            Label("Options", systemImage: "gearshape")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if hasAnalysis {
                let totalNew = analysisResults.values.reduce(0) { $0 + $1.newCount }
                let totalSkipped = analysisResults.values.reduce(0) { $0 + $1.skippedCount }
                let totalMoves = misplacedActions.values.filter { $0 == .move }.count
                VStack(alignment: .leading) {
                    Text("\(totalNew) to copy, \(totalSkipped) skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if totalMoves > 0 {
                        Text("\(totalMoves) to move")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button("Cancel") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)

            Button("Start Sync") {
                startSync()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!hasDestinations || isScanning || isAnalyzing || scannedFiles.isEmpty)
        }
        .padding(20)
        .background(.bar)
    }

    // MARK: - Actions

    private func scanDevice() {
        isScanning = true
        Task {
            let files = (try? FileOrganizer.scanDevice(device)) ?? []
            scannedFiles = files
            isScanning = false
        }
    }

    private func analyzeDestinations() {
        isAnalyzing = true
        analysisResults = [:]
        let pattern = FileOrganizer.currentPattern()

        Task {
            for destPath in selectedDestinations {
                let destURL = URL(fileURLWithPath: destPath)
                let result = await DestinationAnalyzer.analyze(
                    sourceFiles: scannedFiles,
                    destination: destURL,
                    deviceType: device.deviceType,
                    pattern: pattern
                ) { message, percent in
                    Task { @MainActor in
                        analyzeProgress = message
                        analyzePercent = percent
                    }
                }
                analysisResults[destPath] = result
            }
            isAnalyzing = false
        }
    }

    private func startSync() {
        for destPath in selectedDestinations {
            let analysis = analysisResults[destPath]

            // Move misplaced files first (rename on same disk = instant)
            let filesToMove = analysis?.misplaced.filter { item in
                misplacedActions[item.currentPath] == .move
            } ?? []

            let fm = FileManager.default
            for item in filesToMove {
                let expectedURL = URL(fileURLWithPath: item.expectedPath)
                let parentDir = expectedURL.deletingLastPathComponent()
                try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                try? fm.moveItem(
                    at: URL(fileURLWithPath: item.currentPath),
                    to: expectedURL
                )
            }

            // Only copy files identified as "new" by the analysis
            if let analysis {
                if analysis.newFiles.isEmpty {
                    // Nothing to copy — all files already present
                    continue
                }
                appState.syncDevice(device, to: destPath, onlyFiles: analysis.newFiles)
            } else {
                // No analysis available (shouldn't happen) — fallback to full sync
                appState.syncDevice(device, to: destPath)
            }
        }
        NSApp.keyWindow?.close()
    }

    // MARK: - Destination persistence per device

    private var destinationsKey: String {
        "syncDestinations_\(device.deviceType.rawValue)"
    }

    private func saveSelectedDestinations() {
        let paths = Array(selectedDestinations)
        UserDefaults.standard.set(paths, forKey: destinationsKey)
    }

    private func loadSelectedDestinations() {
        if let saved = UserDefaults.standard.stringArray(forKey: destinationsKey) {
            selectedDestinations = Set(saved)
        }
    }
}
