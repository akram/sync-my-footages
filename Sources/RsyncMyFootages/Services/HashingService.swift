import Foundation
import CryptoKit

/// Computes SHA256 hashes for large files using streaming
enum HashingService {
    /// Compute SHA256 of a file, streaming in chunks to handle large video files
    static func sha256(of fileURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let handle = try FileHandle(forReadingFrom: fileURL)
                    defer { handle.closeFile() }

                    var hasher = SHA256()
                    let bufferSize = Constants.hashBufferSize

                    while true {
                        let data = handle.readData(ofLength: bufferSize)
                        if data.isEmpty { break }
                        hasher.update(data: data)
                    }

                    let digest = hasher.finalize()
                    let hex = digest.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: hex)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Compute SHA256 of a file with progress reporting
    static func sha256(
        of fileURL: URL,
        fileSize: Int64,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let handle = try FileHandle(forReadingFrom: fileURL)
                    defer { handle.closeFile() }

                    var hasher = SHA256()
                    let bufferSize = Constants.hashBufferSize
                    var bytesRead: Int64 = 0

                    while true {
                        let data = handle.readData(ofLength: bufferSize)
                        if data.isEmpty { break }
                        hasher.update(data: data)
                        bytesRead += Int64(data.count)
                        if fileSize > 0 {
                            progressHandler(Double(bytesRead) / Double(fileSize))
                        }
                    }

                    let digest = hasher.finalize()
                    let hex = digest.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: hex)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
