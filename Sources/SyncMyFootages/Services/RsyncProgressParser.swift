import Foundation

/// Parses openrsync --progress output lines into structured progress data
enum RsyncProgressParser {
    /// Result of parsing a single line of rsync output
    enum ParsedLine: Sendable {
        /// A new file being transferred: ">f....... filename"
        case fileStart(String)
        /// Progress update with bytes and overall count
        case progress(bytesTransferred: Int64, percentage: Int, transferNumber: Int, filesRemaining: Int, totalFiles: Int)
        /// Dry-run file listing: "filename size"
        case dryRunFile(name: String, size: Int64)
    }

    // ">f....... DJI_20251222073342_0001_D.MP4" or ">f+++++++++ ..."
    private nonisolated(unsafe) static let fileStartPattern = /^>f[\.\+]+\s+(.+)$/

    // "    12345678  45%  1.23MB/s  0:01:23 (xfer#5, to-check=100/500)"
    private nonisolated(unsafe) static let progressPattern = /^\s*(\d[\d,]*)\s+(\d+)%\s+.*\(xfer#(\d+),\s*to-check=(\d+)\/(\d+)\)/

    /// Parse a single line of rsync output
    static func parse(_ line: String) -> ParsedLine? {
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return nil }

        // Try file start match
        if let match = trimmed.firstMatch(of: fileStartPattern) {
            return .fileStart(String(match.1))
        }

        // Try progress match
        if let match = trimmed.firstMatch(of: progressPattern) {
            let bytesStr = String(match.1).replacingOccurrences(of: ",", with: "")
            let bytes = Int64(bytesStr) ?? 0
            let pct = Int(match.2) ?? 0
            let xferNum = Int(match.3) ?? 0
            let remaining = Int(match.4) ?? 0
            let total = Int(match.5) ?? 0

            return .progress(
                bytesTransferred: bytes,
                percentage: pct,
                transferNumber: xferNum,
                filesRemaining: remaining,
                totalFiles: total
            )
        }

        return nil
    }

    /// Parse dry-run output line: "filename size"
    /// Used with --out-format='%n %l'
    static func parseDryRunLine(_ line: String) -> ParsedLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Find last space-separated component as size
        let components = trimmed.split(separator: " ")
        guard components.count >= 2,
              let size = Int64(components.last!) else {
            return nil
        }

        let name = components.dropLast().joined(separator: " ")
        guard !name.isEmpty else { return nil }

        return .dryRunFile(name: name, size: size)
    }
}
