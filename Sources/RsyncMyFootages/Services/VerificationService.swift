import Foundation

/// Verifies integrity of synced files at 3 levels
enum VerificationService {
    enum Level: Int, CaseIterable, Sendable {
        case quick = 1    // path exists
        case medium = 2   // path exists + size matches
        case full = 3     // SHA256 match
    }

    struct Result: Sendable {
        let level: Level
        let passed: Bool
        let details: String
    }

    /// Verify a single file at the given level
    static func verify(
        path: String,
        expectedSize: Int64,
        expectedSHA256: String,
        level: Level
    ) async -> Result {
        let fm = FileManager.default

        // Level 1: path exists
        guard fm.fileExists(atPath: path) else {
            return Result(level: level, passed: false, details: "File not found: \(path)")
        }

        guard level.rawValue >= Level.medium.rawValue else {
            return Result(level: .quick, passed: true, details: "File exists")
        }

        // Level 2: size matches
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let actualSize = attrs[.size] as? Int64 else {
            return Result(level: .medium, passed: false, details: "Cannot read file attributes")
        }

        guard actualSize == expectedSize else {
            return Result(
                level: .medium,
                passed: false,
                details: "Size mismatch: expected \(expectedSize), got \(actualSize)"
            )
        }

        guard level.rawValue >= Level.full.rawValue else {
            return Result(level: .medium, passed: true, details: "File exists, size matches")
        }

        // Level 3: SHA256 matches
        do {
            let actualHash = try await HashingService.sha256(of: url)
            if actualHash == expectedSHA256 {
                return Result(level: .full, passed: true, details: "SHA256 verified")
            } else {
                return Result(
                    level: .full,
                    passed: false,
                    details: "SHA256 mismatch: expected \(expectedSHA256.prefix(16))..., got \(actualHash.prefix(16))..."
                )
            }
        } catch {
            return Result(level: .full, passed: false, details: "Hash error: \(error.localizedDescription)")
        }
    }
}
