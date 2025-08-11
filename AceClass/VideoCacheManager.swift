import Foundation

/// Manages local caching of external video files for smoother playback.
/// For videos smaller than a configured threshold (default 5GB), copy once to
/// Application Support/AceClass/Cache/Videos and reuse until the source file changes
/// (detected via file size + modification date). A simple JSON manifest tracks metadata.
final class VideoCacheManager {
    static let shared = VideoCacheManager()
    private init() { loadManifest() }

    // MARK: Configuration
    var enabled: Bool = true
    var maxItemSizeBytes: Int64 = 5 * 1024 * 1024 * 1024 // 5 GB
    var maxTotalCacheBytes: Int64 = 20 * 1024 * 1024 * 1024 // 20 GB overall soft cap

    // MARK: Paths
    private let fm = FileManager.default
    private lazy var cacheDir: URL = {
        let base = LocalMetadataStorage.baseDirectory.appendingPathComponent("Cache/Videos", isDirectory: true)
        if !fm.fileExists(atPath: base.path) { try? fm.createDirectory(at: base, withIntermediateDirectories: true) }
        return base
    }()
    private var manifestURL: URL { cacheDir.appendingPathComponent("VideoCacheManifest.json") }

    // MARK: Manifest
    private struct Entry: Codable { let originalPath: String; let cacheFileName: String; let fileSize: Int64; let modTime: TimeInterval; var lastAccess: TimeInterval }
    private var manifest: [String: Entry] = [:] // key = originalPath
    private let queue = DispatchQueue(label: "aceclass.videocache", qos: .utility)

    // MARK: Public API
    /// Returns a local URL for playback. May trigger a copy (awaitable).
    func preparePlaybackURL(for original: URL) async throws -> URL {
        guard enabled else { return original }
        let attrs = try fm.attributesOfItem(atPath: original.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size <= 0 || size > maxItemSizeBytes { return original }
        let modDate = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        let key = original.path
        if let e = manifest[key] {
            if e.fileSize == size && abs(e.modTime - modDate.timeIntervalSince1970) < 1 {
                let cachedURL = cacheDir.appendingPathComponent(e.cacheFileName)
                if fm.fileExists(atPath: cachedURL.path) {
                    touchAccess(for: key)
                    ACLog("Cache hit for video: \(original.lastPathComponent)", level: .debug)
                    return cachedURL
                }
            }
        }
        ACLog("Caching video (size=\(String(format: "%.2f", Double(size)/1_048_576)) MB): \(original.lastPathComponent)", level: .info)
        let cacheFileName = cacheFileNameFor(original: original, size: size, mod: modDate)
        let dest = cacheDir.appendingPathComponent(cacheFileName)
        try? fm.removeItem(at: dest)
        let localFM = fm
        let srcPath = original.path
        let dstPath = dest.path
        try await Task.detached(priority: .utility) {
            try localFM.copyItem(atPath: srcPath, toPath: dstPath)
        }.value
        let entry = Entry(originalPath: key, cacheFileName: cacheFileName, fileSize: size, modTime: modDate.timeIntervalSince1970, lastAccess: Date().timeIntervalSince1970)
        queue.async { [weak self] in
            self?.manifest[key] = entry
            self?.saveManifest()
            self?.enforceSizeLimit()
        }
        return dest
    }

    // MARK: Helpers
    private func cacheFileNameFor(original: URL, size: Int64, mod: Date) -> String {
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        let stamp = Int(mod.timeIntervalSince1970)
        return "\(base)_\(stamp)_\(size).\(ext)"
    }
    private func touchAccess(for key: String) {
        queue.async { [weak self] in
            guard let self, var e = self.manifest[key] else { return }
            e.lastAccess = Date().timeIntervalSince1970
            self.manifest[key] = e
            self.saveManifest()
        }
    }
    private func totalCacheSize() -> Int64 { manifest.values.reduce(0) { $0 + $1.fileSize } }
    private func enforceSizeLimit() {
        let over = totalCacheSize() - maxTotalCacheBytes
        if over <= 0 { return }
        let ordered = manifest.values.sorted { $0.lastAccess < $1.lastAccess }
        var toFree = over
        for e in ordered {
            if toFree <= 0 { break }
            let fileURL = cacheDir.appendingPathComponent(e.cacheFileName)
            try? fm.removeItem(at: fileURL)
            manifest.removeValue(forKey: e.originalPath)
            toFree -= e.fileSize
        }
        saveManifest()
        ACLog("Cache eviction complete. Freed ~\(String(format: "%.2f", Double(over - toFree)/1_048_576)) MB", level: .debug)
    }
    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) { manifest = decoded }
    }
    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - Public Utilities
    func cacheStats() -> (count: Int, totalBytes: Int64) {
        var snapshot: (Int, Int64) = (0,0)
        queue.sync {
            snapshot.0 = manifest.count
            snapshot.1 = manifest.values.reduce(0) { $0 + $1.fileSize }
        }
        return snapshot
    }

    func clearCache() async {
        // Snapshot entries
        let entries: [Entry] = queue.sync { Array(manifest.values) }
        for e in entries {
            let fileURL = cacheDir.appendingPathComponent(e.cacheFileName)
            try? fm.removeItem(at: fileURL)
        }
        queue.sync {
            manifest.removeAll()
            saveManifest()
        }
        ACLog("Video cache cleared", level: .info)
    }
}
