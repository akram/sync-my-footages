import Foundation

/// Configurable mapping between file extensions and type folder names
/// Persisted in UserDefaults
struct FileTypeMapping: Codable, Sendable {
    /// A single type category with its folder name and associated extensions
    struct Category: Codable, Identifiable, Hashable, Sendable {
        var id: String { folderName }
        var folderName: String
        var extensions: [String]  // uppercase, e.g. ["MP4", "MOV"]
    }

    var categories: [Category]
    var fallbackFolder: String  // folder name for unknown extensions

    /// Default mapping
    static let defaultMapping = FileTypeMapping(
        categories: [
            Category(folderName: "videos", extensions: ["MP4", "MOV"]),
            Category(folderName: "lowres", extensions: ["LRF"]),
            Category(folderName: "audios", extensions: ["WAV", "AAC", "MP3"]),
            Category(folderName: "photos", extensions: ["JPG", "JPEG", "DNG", "PNG", "TIFF"]),
        ],
        fallbackFolder: "others"
    )

    /// Get the folder name for a given file extension
    func folderName(for extension_: String) -> String {
        let ext = extension_.uppercased()
        for category in categories {
            if category.extensions.contains(ext) {
                return category.folderName
            }
        }
        return fallbackFolder
    }

    /// All known extensions across all categories
    var allExtensions: Set<String> {
        Set(categories.flatMap(\.extensions))
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "fileTypeMapping"

    static func load() -> FileTypeMapping {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let mapping = try? JSONDecoder().decode(FileTypeMapping.self, from: data) else {
            return defaultMapping
        }
        return mapping
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
