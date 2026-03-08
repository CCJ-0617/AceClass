import CryptoKit
import Foundation

/// Persists AceClass metadata next to the course videos so the same course data
/// can be discovered regardless of which parent folder the user selects later.
/// Application Support remains as a backward-compatible fallback and migration source.
final class LocalMetadataStorage {
    // MARK: - Public Flags

    static var shouldAttemptWriteToExternalDrives: Bool = true
    static var disableExternalMetadataSync: Bool = false

    struct CourseMetadata: Codable {
        var targetDate: Date?
        var targetDescription: String
    }

    // MARK: - Private State

    private static let externalCopyThrottle: TimeInterval = 30
    private static let coordinationQueue = DispatchQueue(label: "aceclass.metadata.coordination", qos: .utility)
    private static var lastExternalCopyTimes: [String: Date] = [:]

    // MARK: - Directories

    static let baseDirectory: URL = {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let aceclassDir = appSupportDir.appendingPathComponent("AceClass", isDirectory: true)

        if !fileManager.fileExists(atPath: aceclassDir.path) {
            try? fileManager.createDirectory(at: aceclassDir, withIntermediateDirectories: true)
        }

        return aceclassDir
    }()

    static let coursesDirectory: URL = {
        let directory = baseDirectory.appendingPathComponent("Courses", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    static let courseMetadataDirectory: URL = {
        let directory = baseDirectory.appendingPathComponent("CourseMetadata", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    static let captionsDirectory: URL = {
        let directory = baseDirectory.appendingPathComponent("Captions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    // MARK: - Stable Keys

    static func storageKey(for folderURL: URL) -> String {
        let normalizedPath = normalizedPath(for: folderURL)
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        let readableName = sanitizedPathComponent(folderURL.lastPathComponent)
        return "\(readableName)_\(digest)"
    }

    static func saveVideos(_ videos: [VideoItem], for folderURL: URL) {
        let fileURL = videoMetadataURL(in: folderURL)
        let fallbackURL = videoMetadataURL(for: storageKey(for: folderURL))

        do {
            let data = try makeVideoEncoder().encode(videos)
            try data.write(to: fileURL, options: .atomic)
            ACLog("成功將影片元數據儲存到課程資料夾: \(fileURL.path)", level: .info)

            // Keep a local compatibility copy so older app flows and caches continue to work.
            try? data.write(to: fallbackURL, options: .atomic)
        } catch {
            ACLog("儲存影片元數據到課程資料夾失敗: \(error.localizedDescription)", level: .error)

            do {
                let data = try makeVideoEncoder().encode(videos)
                try data.write(to: fallbackURL, options: .atomic)
                ACLog("改為儲存影片元數據到本地 fallback: \(fallbackURL.path)", level: .warn)
            } catch {
                ACLog("儲存影片元數據 fallback 也失敗: \(error.localizedDescription)", level: .error)
            }
        }
    }

    static func loadVideos(for folderURL: URL) -> [VideoItem] {
        let preferredURL = videoMetadataURL(in: folderURL)
        let fallbackURL = videoMetadataURL(for: storageKey(for: folderURL))

        if let videos = decodeVideos(from: preferredURL) {
            return videos
        }

        guard let videos = decodeVideos(from: fallbackURL) else {
            return []
        }

        // Migrate legacy local metadata back next to the videos when possible.
        saveVideos(videos, for: folderURL)
        return videos
    }

    static func saveCourseMetadata(_ metadata: CourseMetadata, for folderURL: URL) {
        let fileURL = courseMetadataURL(in: folderURL)
        let fallbackURL = courseMetadataURL(for: storageKey(for: folderURL))

        do {
            let data = try makeMetadataEncoder().encode(metadata)
            try data.write(to: fileURL, options: .atomic)
            ACLog("成功將課程元數據儲存到課程資料夾: \(fileURL.path)", level: .info)

            try? data.write(to: fallbackURL, options: .atomic)
        } catch {
            ACLog("儲存課程元數據到課程資料夾失敗: \(error.localizedDescription)", level: .error)

            do {
                let data = try makeMetadataEncoder().encode(metadata)
                try data.write(to: fallbackURL, options: .atomic)
                ACLog("改為儲存課程元數據到本地 fallback: \(fallbackURL.lastPathComponent)", level: .warn)
            } catch {
                ACLog("儲存課程元數據 fallback 也失敗: \(error.localizedDescription)", level: .error)
            }
        }
    }

    static func loadCourseMetadata(for folderURL: URL) -> CourseMetadata? {
        let preferredURL = courseMetadataURL(in: folderURL)
        let fallbackURL = courseMetadataURL(for: storageKey(for: folderURL))

        if let metadata = decodeCourseMetadata(from: preferredURL) {
            return metadata
        }

        guard let metadata = decodeCourseMetadata(from: fallbackURL) else {
            return nil
        }

        saveCourseMetadata(metadata, for: folderURL)
        return metadata
    }

    static func saveCaptions(_ captions: [CaptionSegment], for folderURL: URL, relativePath: String) {
        let preferredURL = captionsURL(in: folderURL, relativePath: relativePath)
        let fallbackURL = captionsURL(for: storageKey(for: folderURL), relativePath: relativePath)

        do {
            try ensureParentDirectoryExists(for: preferredURL)
            let data = try makeVideoEncoder().encode(captions)
            try data.write(to: preferredURL, options: .atomic)
            try? data.write(to: fallbackURL, options: .atomic)
            ACLog("成功儲存字幕快取: \(preferredURL.path)", level: .info)
        } catch {
            ACLog("儲存字幕快取失敗: \(error.localizedDescription)", level: .warn)

            do {
                let data = try makeVideoEncoder().encode(captions)
                try data.write(to: fallbackURL, options: .atomic)
                ACLog("改為儲存字幕快取到本地 fallback: \(fallbackURL.lastPathComponent)", level: .warn)
            } catch {
                ACLog("儲存字幕 fallback 也失敗: \(error.localizedDescription)", level: .error)
            }
        }
    }

    static func loadCaptions(for folderURL: URL, relativePath: String) -> [CaptionSegment]? {
        let preferredURL = captionsURL(in: folderURL, relativePath: relativePath)
        let fallbackURL = captionsURL(for: storageKey(for: folderURL), relativePath: relativePath)

        if let captions = decodeCaptions(from: preferredURL) {
            return captions
        }

        guard let captions = decodeCaptions(from: fallbackURL) else {
            return nil
        }

        saveCaptions(captions, for: folderURL, relativePath: relativePath)
        return captions
    }

    // MARK: - Helpers

    private static func normalizedPath(for folderURL: URL) -> String {
        folderURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let components = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return components.isEmpty ? "course" : components.joined(separator: "-")
    }

    private static func videoMetadataURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("videos.json")
    }

    private static func courseMetadataURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent(".aceclass-course.json")
    }

    private static func captionsDirectoryURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent(".aceclass-captions", isDirectory: true)
    }

    private static func videoMetadataURL(for storageKey: String) -> URL {
        coursesDirectory.appendingPathComponent("\(storageKey).json")
    }

    private static func courseMetadataURL(for storageKey: String) -> URL {
        courseMetadataDirectory.appendingPathComponent("\(storageKey).json")
    }

    private static func captionsURL(in folderURL: URL, relativePath: String) -> URL {
        captionsDirectoryURL(in: folderURL)
            .appendingPathComponent("\(hashedRelativePath(relativePath)).json")
    }

    private static func captionsURL(for storageKey: String, relativePath: String) -> URL {
        captionsDirectory.appendingPathComponent("\(storageKey)-\(hashedRelativePath(relativePath)).json")
    }

    private static func makeVideoEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeMetadataEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeMetadataDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func decodeVideos(from fileURL: URL) -> [VideoItem]? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let videos = try? JSONDecoder().decode([VideoItem].self, from: data) else {
            return nil
        }

        return videos
    }

    private static func decodeCourseMetadata(from fileURL: URL) -> CourseMetadata? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            return try makeMetadataDecoder().decode(CourseMetadata.self, from: data)
        } catch {
            ACLog("讀取課程元數據失敗: \(error.localizedDescription)", level: .warn)
            return nil
        }
    }

    private static func decodeCaptions(from fileURL: URL) -> [CaptionSegment]? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let captions = try? JSONDecoder().decode([CaptionSegment].self, from: data) else {
            return nil
        }

        return captions
    }

    private static func hashedRelativePath(_ relativePath: String) -> String {
        SHA256.hash(data: Data(relativePath.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func ensureParentDirectoryExists(for fileURL: URL) throws {
        let parent = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }
}
