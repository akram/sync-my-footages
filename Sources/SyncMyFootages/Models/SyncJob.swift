import Foundation

/// Represents an active or completed sync operation
struct SyncJob: Identifiable, Sendable {
    let id: UUID
    let device: DJIDevice
    let destinationPath: String
    let startTime: Date
    var status: SyncStatus
    var progress: SyncProgress

    init(device: DJIDevice, destinationPath: String) {
        self.id = UUID()
        self.device = device
        self.destinationPath = destinationPath
        self.startTime = Date()
        self.status = .preparing
        self.progress = SyncProgress()
    }
}

enum SyncStatus: Sendable {
    case preparing
    case scanning
    case syncing
    case hashing
    case verifying
    case completed
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .scanning, .syncing, .hashing, .verifying:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    var label: String {
        switch self {
        case .preparing: return "Preparing..."
        case .scanning: return "Scanning files..."
        case .syncing: return "Syncing..."
        case .hashing: return "Computing checksums..."
        case .verifying: return "Verifying..."
        case .completed: return "Completed"
        case .failed(let msg): return "Failed: \(msg)"
        case .cancelled: return "Cancelled"
        }
    }
}

struct SyncProgress: Sendable {
    var currentFile: String?
    var bytesTransferred: Int64 = 0
    var totalBytes: Int64 = 0
    var filesTransferred: Int = 0
    var totalFiles: Int = 0

    var overallFraction: Double {
        guard totalFiles > 0 else { return filesTransferred == 0 ? 1.0 : 0 }
        return Double(filesTransferred) / Double(totalFiles)
    }

    var bytesFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }
}
