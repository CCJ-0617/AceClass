import CryptoKit
import Foundation

/// Persists lightweight course metadata locally while allowing best-effort sync
/// back to the selected course folder on external storage.
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

    static func saveVideos(_ videos: [VideoItem], for storageKey: String) {
        let fileURL = videoMetadataURL(for: storageKey)

        do {
            let data = try makeVideoEncoder().encode(videos)
            try data.write(to: fileURL, options: .atomic)
            ACLog("成功將影片元數據儲存到本地: \(fileURL.path)", level: .info)
        } catch {
            ACLog("儲存影片元數據到本地失敗: \(error.localizedDescription)", level: .error)
        }
    }

    static func loadVideos(for storageKey: String) -> [VideoItem] {
        let fileURL = videoMetadataURL(for: storageKey)

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let videos = try? JSONDecoder().decode([VideoItem].self, from: data) else {
            return []
        }

        return videos
    }

    static func saveCourseMetadata(_ metadata: CourseMetadata, for storageKey: String) {
        let fileURL = courseMetadataURL(for: storageKey)

        do {
            let data = try makeMetadataEncoder().encode(metadata)
            try data.write(to: fileURL, options: .atomic)
            ACLog("成功將課程元數據儲存到本地: \(fileURL.lastPathComponent)", level: .info)
        } catch {
            ACLog("儲存課程元數據到本地失敗: \(error.localizedDescription)", level: .error)
        }
    }

    static func loadCourseMetadata(for storageKey: String) -> CourseMetadata? {
        let fileURL = courseMetadataURL(for: storageKey)

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

    static func tryCopyMetadataToExternalLocation(for storageKey: String, folderURL: URL) {
        guard shouldAttemptWriteToExternalDrives, !disableExternalMetadataSync else {
            ACLog("跳過複製到外部儲存裝置：功能關閉", level: .trace)
            return
        }

        let now = Date()
        guard shouldProceedWithExternalCopy(for: storageKey, now: now) else {
            ACLog("節流：距離上次外部複製不足 \(Int(externalCopyThrottle)) 秒，跳過", level: .trace)
            return
        }

        let localURL = videoMetadataURL(for: storageKey)
        let externalURL = folderURL.appendingPathComponent("videos.json")

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            ACLog("本地元數據檔案不存在，跳過複製", level: .warn)
            return
        }

        do {
            if FileManager.default.fileExists(atPath: externalURL.path) {
                try FileManager.default.removeItem(at: externalURL)
            }
            try FileManager.default.copyItem(at: localURL, to: externalURL)
            markExternalCopy(for: storageKey, at: now)
            ACLog("成功複製元數據到外部位置: \(externalURL.path)", level: .info)
        } catch {
            ACLog("複製元數據到外部位置失敗 (非關鍵錯誤): \(error.localizedDescription)", level: .warn)
        }
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

    private static func videoMetadataURL(for storageKey: String) -> URL {
        coursesDirectory.appendingPathComponent("\(storageKey).json")
    }

    private static func courseMetadataURL(for storageKey: String) -> URL {
        courseMetadataDirectory.appendingPathComponent("\(storageKey).json")
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

    private static func shouldProceedWithExternalCopy(for storageKey: String, now: Date) -> Bool {
        coordinationQueue.sync {
            guard let previous = lastExternalCopyTimes[storageKey] else { return true }
            return now.timeIntervalSince(previous) >= externalCopyThrottle
        }
    }

    private static func markExternalCopy(for storageKey: String, at date: Date) {
        coordinationQueue.sync {
            lastExternalCopyTimes[storageKey] = date
        }
    }
}
