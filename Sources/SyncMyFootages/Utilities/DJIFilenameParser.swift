import Foundation

/// Parses DJI filenames like DJI_20251222073342_0001_D.MP4
enum DJIFilenameParser {
    struct ParsedFilename: Sendable, Hashable {
        let captureDate: Date
        let sequenceNumber: Int
        /// Color profile suffix: D = D-Log, N = Normal, etc.
        let colorProfile: String
        let fileExtension: String
        /// Groups related files: "20251222073342_0001_D"
        let clipID: String
    }

    // DJI_YYYYMMDDHHMMSS_NNNN_X.EXT
    private nonisolated(unsafe) static let pattern = /^DJI_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})_(\d{4})_([A-Za-z0-9]+)\.(\w+)$/

    private static let calendar = Calendar(identifier: .gregorian)

    static func parse(_ filename: String) -> ParsedFilename? {
        guard let match = filename.wholeMatch(of: pattern) else { return nil }

        let year = Int(match.1) ?? 0
        let month = Int(match.2) ?? 0
        let day = Int(match.3) ?? 0
        let hour = Int(match.4) ?? 0
        let minute = Int(match.5) ?? 0
        let second = Int(match.6) ?? 0
        let sequence = Int(match.7) ?? 0
        let suffix = String(match.8)
        let ext = String(match.9)

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone.current

        guard let date = calendar.date(from: components) else { return nil }

        let clipID = "\(match.1)\(match.2)\(match.3)\(match.4)\(match.5)\(match.6)_\(match.7)_\(suffix)"

        return ParsedFilename(
            captureDate: date,
            sequenceNumber: sequence,
            colorProfile: suffix,
            fileExtension: ext,
            clipID: clipID
        )
    }

    /// Check if a filename matches DJI naming pattern
    static func isDJIFile(_ filename: String) -> Bool {
        filename.wholeMatch(of: pattern) != nil
    }
}
