import Foundation

/// A single footage file on a capture device
struct FootageFile: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let filename: String
    let fileExtension: String
    let fileSize: Int64
    let captureDate: Date?
    let sequenceNumber: Int?
    let colorProfile: String?
    let clipID: String?

    /// Groups related files (MP4 + LRF + WAV with same timestamp/sequence)
    var clipGroupKey: String? {
        clipID
    }

    init(url: URL, parsed: DJIFilenameParser.ParsedFilename?, fileSize: Int64) {
        self.id = url.path
        self.url = url
        self.filename = url.lastPathComponent
        self.fileExtension = url.pathExtension.uppercased()
        self.fileSize = fileSize
        self.captureDate = parsed?.captureDate
        self.sequenceNumber = parsed?.sequenceNumber
        self.colorProfile = parsed?.colorProfile
        self.clipID = parsed?.clipID
    }
}
