import SwiftUI

struct SyncProgressView: View {
    let job: SyncJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.device.deviceType.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(job.status.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: job.progress.overallFraction)

            if let currentFile = job.progress.currentFile {
                Text(currentFile)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Text("\(job.progress.filesTransferred)/\(job.progress.totalFiles) files")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatBytes(job.progress.bytesTransferred))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
