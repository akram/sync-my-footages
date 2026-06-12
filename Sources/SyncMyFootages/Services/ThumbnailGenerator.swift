import Foundation
import AVFoundation
import AppKit

/// Generates thumbnails from video files using AVFoundation
@MainActor
enum ThumbnailGenerator {
    /// Generate a thumbnail for a video file at the given time (default: 1 second in)
    static func generateThumbnail(
        for videoURL: URL,
        atTime time: CMTime = CMTime(seconds: 1, preferredTimescale: 600),
        maxDimension: CGFloat = Constants.thumbnailMaxDimension
    ) async -> NSImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    /// Generate and cache a thumbnail, returning the cache file path
    static func cachedThumbnail(
        for videoURL: URL,
        sha256: String
    ) async -> URL? {
        let cacheDir = Constants.centralJournalDirectory.appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let cachedPath = cacheDir.appendingPathComponent("\(sha256).jpg")

        if FileManager.default.fileExists(atPath: cachedPath.path) {
            return cachedPath
        }

        guard let image = await generateThumbnail(for: videoURL) else { return nil }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }

        try? jpegData.write(to: cachedPath)
        return cachedPath
    }
}
