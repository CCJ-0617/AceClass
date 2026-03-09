import Foundation

/// Manages local caching of external video files for smoother playback.
/// For videos smaller than a configured threshold (default 5GB), copy once to
/// Application Support/AceClass/Cache/Videos and reuse until the source file changes
/// (detected via file size + modification date). A simple JSON manifest tracks metadata.
final class VideoCacheManager {
    static let shared = VideoCacheManager()
    private init() { loadManifest() }

    private final class UncheckedSendableBox<Value>: @unchecked Sendable {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

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

    /// Tracks original paths of videos currently being played — protected from eviction/clear.
    private var activePlaybackPaths: Set<String> = []

    /// Tracks original paths currently being copied to prevent duplicate concurrent copies.
    private var inFlightCopies: Set<String> = []
    private var inFlightContinuations: [String: [CheckedContinuation<URL, Error>]] = [:]

    // MARK: Active Playback Tracking

    /// Call when a cached URL is used for playback — prevents eviction of this file.
    func markActive(originalPath: String) {
        queue.sync { _ = activePlaybackPaths.insert(originalPath) }
    }

    /// Call when playback stops or switches to another video.
    func markInactive(originalPath: String) {
        queue.sync { _ = activePlaybackPaths.remove(originalPath) }
    }

    /// Returns true if the given original path is currently in active playback.
    private func isActive(_ originalPath: String) -> Bool {
        activePlaybackPaths.contains(originalPath)
    }

    // MARK: Public API
    /// Returns a local URL for playback. May trigger a copy (awaitable).
    /// Concurrent calls for the same file coalesce — only one copy runs.
    func preparePlaybackURL(for original: URL) async throws -> URL {
        guard enabled else { return original }
        let attrs = try fm.attributesOfItem(atPath: original.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size <= 0 || size > maxItemSizeBytes { return original }
        let modDate = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        let key = original.path

        // Check cache hit (thread-safe)
        let cachedHit: URL? = queue.sync {
            guard let e = manifest[key],
                  e.fileSize == size,
                  abs(e.modTime - modDate.timeIntervalSince1970) < 1 else { return nil }
            let cachedURL = cacheDir.appendingPathComponent(e.cacheFileName)
            guard fm.fileExists(atPath: cachedURL.path) else {
                // Stale entry — cached file was deleted externally
                manifest.removeValue(forKey: key)
                saveManifest()
                ACLog("Removed stale cache entry for: \(original.lastPathComponent)", level: .warn)
                return nil
            }
            var updated = e
            updated.lastAccess = Date().timeIntervalSince1970
            manifest[key] = updated
            saveManifest()
            return cachedURL
        }
        if let hit = cachedHit {
            ACLog("Cache hit for video: \(original.lastPathComponent)", level: .debug)
            return hit
        }

        // Check if a copy is already in flight — coalesce
        let shouldWait: Bool = queue.sync {
            if inFlightCopies.contains(key) {
                return true
            }
            inFlightCopies.insert(key)
            return false
        }

        if shouldWait {
            ACLog("Waiting for in-flight cache copy: \(original.lastPathComponent)", level: .debug)
            return try await withCheckedThrowingContinuation { continuation in
                let box = UncheckedSendableBox(self)
                queue.async {
                    box.value.inFlightContinuations[key, default: []].append(continuation)
                }
            }
        }

        // Perform the copy
        ACLog("Caching video (size=\(String(format: "%.2f", Double(size)/1_048_576)) MB): \(original.lastPathComponent)", level: .info)
        let cacheFileName = cacheFileNameFor(original: original, size: size, mod: modDate)
        let dest = cacheDir.appendingPathComponent(cacheFileName)
        try? fm.removeItem(at: dest)
        let localFM = fm
        let srcPath = original.path
        let dstPath = dest.path

        do {
            try await Task.detached(priority: .utility) {
                try localFM.copyItem(atPath: srcPath, toPath: dstPath)
            }.value
        } catch {
            // Copy failed — resume waiters with error and clean up
            let waiters: [CheckedContinuation<URL, Error>] = queue.sync {
                inFlightCopies.remove(key)
                return inFlightContinuations.removeValue(forKey: key) ?? []
            }
            for w in waiters { w.resume(throwing: error) }
            throw error
        }

        let entry = Entry(originalPath: key, cacheFileName: cacheFileName, fileSize: size, modTime: modDate.timeIntervalSince1970, lastAccess: Date().timeIntervalSince1970)

        let waiters: [CheckedContinuation<URL, Error>] = queue.sync {
            manifest[key] = entry
            saveManifest()
            enforceSizeLimit()
            inFlightCopies.remove(key)
            return inFlightContinuations.removeValue(forKey: key) ?? []
        }
        for w in waiters { w.resume(returning: dest) }

        return dest
    }

    // MARK: Helpers
    private func cacheFileNameFor(original: URL, size: Int64, mod: Date) -> String {
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        let stamp = Int(mod.timeIntervalSince1970)
        return "\(base)_\(stamp)_\(size).\(ext)"
    }

    private func totalCacheSize() -> Int64 { manifest.values.reduce(0) { $0 + $1.fileSize } }

    /// Evicts least-recently-accessed entries to stay within the size cap.
    /// Skips files that are currently in active playback.
    private func enforceSizeLimit() {
        let over = totalCacheSize() - maxTotalCacheBytes
        if over <= 0 { return }
        let ordered = manifest.values.sorted { $0.lastAccess < $1.lastAccess }
        var toFree = over
        for e in ordered {
            if toFree <= 0 { break }
            // Never evict a file that is currently being played
            if isActive(e.originalPath) {
                ACLog("Skipping eviction for active playback: \(e.cacheFileName)", level: .debug)
                continue
            }
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

    /// Clears all cached files except those currently in active playback.
    /// Returns the number of skipped (active) files.
    @discardableResult
    func clearCache() async -> Int {
        let (entries, active): ([Entry], Set<String>) = queue.sync {
            (Array(manifest.values), activePlaybackPaths)
        }
        var skipped = 0
        for e in entries {
            if active.contains(e.originalPath) {
                ACLog("Skipping clear for active playback: \(e.cacheFileName)", level: .debug)
                skipped += 1
                continue
            }
            let fileURL = cacheDir.appendingPathComponent(e.cacheFileName)
            try? fm.removeItem(at: fileURL)
        }
        queue.sync {
            // Remove only non-active entries from manifest
            for e in entries where !active.contains(e.originalPath) {
                manifest.removeValue(forKey: e.originalPath)
            }
            saveManifest()
        }
        ACLog("Video cache cleared (skipped \(skipped) active files)", level: .info)
        return skipped
    }
}
