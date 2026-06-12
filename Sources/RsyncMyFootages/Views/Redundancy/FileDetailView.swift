import SwiftUI

struct FileDetailView: View {
    let item: (sha256: String, filename: String, copyCount: Int, disks: [String])
    let journalManager: JournalManager?
    @State private var entries: [JournalEntry] = []
    @State private var verificationResults: [String: VerificationService.Result] = [:]
    @State private var thumbnail: NSImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Thumbnail
                HStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(height: 200)
                            .overlay {
                                Image(systemName: "film")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                    }
                    Spacer()
                }

                // File info
                GroupBox("File Info") {
                    LabeledContent("Filename", value: item.filename)
                    LabeledContent("SHA256") {
                        Text(item.sha256)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    if let first = entries.first {
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: first.fileSize, countStyle: .file))
                        LabeledContent("Captured", value: first.captureDate.formatted())
                        LabeledContent("Device", value: first.deviceType)
                    }
                    LabeledContent("Copies", value: "\(item.copyCount)")
                }

                // Copies across disks
                GroupBox("Copies") {
                    ForEach(entries, id: \.compositeKey) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.diskName)
                                    .font(.body.bold())
                                Text(entry.currentPath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if let verDate = entry.lastVerifiedDate {
                                    HStack(spacing: 4) {
                                        Image(systemName: entry.lastVerificationPassed == true ? "checkmark.circle" : "xmark.circle")
                                            .foregroundStyle(entry.lastVerificationPassed == true ? .green : .red)
                                        Text("Verified \(verDate.formatted(.relative(presentation: .named)))")
                                            .font(.caption2)
                                    }
                                }
                            }

                            Spacer()

                            // Verification status
                            if let result = verificationResults[entry.compositeKey] {
                                Image(systemName: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                                    .foregroundStyle(result.passed ? .green : .red)
                                    .help(result.details)
                            }

                            Button("Verify") {
                                Task {
                                    let result = await VerificationService.verify(
                                        path: entry.currentPath,
                                        expectedSize: entry.fileSize,
                                        expectedSHA256: entry.sha256,
                                        level: .medium
                                    )
                                    verificationResults[entry.compositeKey] = result
                                    try? journalManager?.recordVerification(
                                        sha256: entry.sha256,
                                        diskIdentifier: entry.diskIdentifier,
                                        level: result.level.rawValue,
                                        passed: result.passed
                                    )
                                }
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding()
        }
        .onAppear { loadEntries() }
    }

    private func loadEntries() {
        entries = (try? journalManager?.findByHash(item.sha256)) ?? []

        // Load thumbnail from first available copy
        if let firstVideoEntry = entries.first(where: { $0.fileExtension == "MP4" || $0.fileExtension == "mp4" }) {
            let url = URL(fileURLWithPath: firstVideoEntry.currentPath)
            Task {
                if let img = await ThumbnailGenerator.generateThumbnail(for: url) {
                    thumbnail = img
                }
            }
        }
    }
}
