import Foundation

/// Persistent cache of SHA256 hashes indexed by filename + size + modification date.
/// Avoids re-hashing files that haven't changed.
actor HashCache {
    static let shared = HashCache()

    private var cache: [String: String] = [:]  // key → sha256
    private let cacheURL = Constants.centralJournalDirectory.appendingPathComponent("hash-cache.json")
    private var isDirty = false

    init() {
        // Load synchronously in init — safe because actor init is nonisolated
        if let data = try? Data(contentsOf: cacheURL),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = loaded
        }
    }

    /// Build a cache key from file attributes
    private static func cacheKey(filename: String, size: Int64, modDate: Date) -> String {
        let timestamp = Int(modDate.timeIntervalSince1970)
        return "\(filename)|\(size)|\(timestamp)"
    }

    /// Get cached hash or compute and cache it
    func hashForFile(at url: URL) async throws -> String {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int64 ?? 0
        let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
        let filename = url.lastPathComponent

        let key = Self.cacheKey(filename: filename, size: size, modDate: modDate)

        // Check cache
        if let cached = cache[key] {
            return cached
        }

        // Compute hash
        let sha256 = try await HashingService.sha256(of: url)

        // Store in cache
        cache[key] = sha256
        isDirty = true

        // Save periodically (every 50 new entries)
        if cache.count % 50 == 0 {
            saveToDisk()
        }

        return sha256
    }

    /// Save cache to disk
    func saveToDisk() {
        guard isDirty else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            isDirty = false
        } catch {
            // Silently fail — cache is optional
        }
    }

    /// Load cache from disk
    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheURL),
              let loaded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        cache = loaded
    }

    /// Number of cached entries
    var count: Int { cache.count }
}
