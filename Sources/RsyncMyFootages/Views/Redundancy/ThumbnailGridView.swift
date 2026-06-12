import SwiftUI

struct ThumbnailGridView: View {
    @Environment(AppState.self) private var appState
    @State private var report: [(sha256: String, filename: String, copyCount: Int, disks: [String])] = []
    @State private var thumbnails: [String: NSImage] = [:]

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200))]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(report, id: \.sha256) { item in
                    ThumbnailCard(
                        item: item,
                        thumbnail: thumbnails[item.sha256]
                    )
                }
            }
            .padding()
        }
        .onAppear { loadReport() }
    }

    private func loadReport() {
        guard let manager = appState.journalManager else { return }
        report = (try? manager.redundancyReport()) ?? []

        // Lazy load thumbnails for video files
        for item in report {
            guard item.filename.uppercased().hasSuffix(".MP4") else { continue }
            let entries = (try? manager.findByHash(item.sha256)) ?? []
            guard let entry = entries.first else { continue }

            let url = URL(fileURLWithPath: entry.currentPath)
            let sha = item.sha256
            Task {
                if let img = await ThumbnailGenerator.generateThumbnail(for: url) {
                    thumbnails[sha] = img
                }
            }
        }
    }
}

struct ThumbnailCard: View {
    let item: (sha256: String, filename: String, copyCount: Int, disks: [String])
    let thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(height: 100)
                    .clipped()
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(height: 100)
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
            }

            Text(item.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                Image(systemName: item.copyCount == 1 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(item.copyCount == 1 ? .red : .green)
                Text("\(item.copyCount) cop\(item.copyCount > 1 ? "ies" : "y")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 1)
    }
}
