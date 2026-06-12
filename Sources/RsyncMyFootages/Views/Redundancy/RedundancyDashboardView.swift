import SwiftUI
import SwiftData

struct RedundancyDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var report: [(sha256: String, filename: String, copyCount: Int, disks: [String])] = []
    @State private var filter: RedundancyFilter = .all
    @State private var searchText = ""
    @State private var selectedHash: String?

    enum RedundancyFilter: String, CaseIterable {
        case all = "All Files"
        case atRisk = "At Risk (1 copy)"
        case redundant = "Redundant (2+ copies)"
    }

    var filteredReport: [(sha256: String, filename: String, copyCount: Int, disks: [String])] {
        var items = report

        switch filter {
        case .all: break
        case .atRisk: items = items.filter { $0.copyCount == 1 }
        case .redundant: items = items.filter { $0.copyCount >= 2 }
        }

        if !searchText.isEmpty {
            items = items.filter { $0.filename.localizedCaseInsensitiveContains(searchText) }
        }

        return items
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Stats bar
                HStack {
                    StatBadge(label: "Total", value: "\(report.count)")
                    StatBadge(
                        label: "At Risk",
                        value: "\(report.filter { $0.copyCount == 1 }.count)",
                        color: .red
                    )
                    StatBadge(
                        label: "Safe",
                        value: "\(report.filter { $0.copyCount >= 2 }.count)",
                        color: .green
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Filter picker
                Picker("Filter", selection: $filter) {
                    ForEach(RedundancyFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 4)

                // File list
                List(selection: $selectedHash) {
                    ForEach(filteredReport, id: \.sha256) { item in
                        FileRowView(item: item)
                            .tag(item.sha256)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search files...")
        } detail: {
            if let hash = selectedHash,
               let item = report.first(where: { $0.sha256 == hash }) {
                FileDetailView(item: item, journalManager: appState.journalManager)
            } else {
                ContentUnavailableView(
                    "Select a file",
                    systemImage: "doc.viewfinder",
                    description: Text("Choose a file to see its copies across disks")
                )
            }
        }
        .navigationTitle("Redundancy Dashboard")
        .onAppear { loadReport() }
        .refreshable { loadReport() }
    }

    private func loadReport() {
        guard let manager = appState.journalManager else { return }
        report = (try? manager.redundancyReport()) ?? []
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FileRowView: View {
    let item: (sha256: String, filename: String, copyCount: Int, disks: [String])

    var body: some View {
        HStack {
            Image(systemName: item.copyCount == 1 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(item.copyCount == 1 ? .red : .green)

            VStack(alignment: .leading) {
                Text(item.filename)
                    .font(.body)
                Text("\(item.copyCount) cop\(item.copyCount > 1 ? "ies" : "y") on \(item.disks.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
