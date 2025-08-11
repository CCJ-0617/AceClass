import Foundation
import SwiftUI

/// This class provides a way to store metadata locally while still accessing content on external drives
class LocalMetadataStorage {
    // MARK: - Properties
    
    /// Controls whether the app should try to write metadata to external drives
    /// If true, the app will attempt to write metadata files to both local storage and external drives
    /// If false, metadata will only be stored locally
    static var shouldAttemptWriteToExternalDrives: Bool = true
    static var disableExternalMetadataSync: Bool = false
    private static var lastExternalCopyTime: Date = .distantPast
    private static let externalCopyThrottle: TimeInterval = 30 // seconds between external copies per course
    
    /// Base directory for all AceClass metadata
    static let baseDirectory: URL = {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let aceclassDir = appSupportDir.appendingPathComponent("AceClass", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: aceclassDir.path) {
            try? fileManager.createDirectory(at: aceclassDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        return aceclassDir
    }()
    
    /// Directory for course metadata
    static let coursesDirectory: URL = {
        let coursesDir = baseDirectory.appendingPathComponent("Courses", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: coursesDir.path) {
            try? FileManager.default.createDirectory(at: coursesDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        return coursesDir
    }()
    
    // MARK: - Methods
    
    /// Get the local metadata file URL for a course
    /// - Parameter courseID: The UUID of the course
    /// - Returns: URL for the local metadata file
    static func metadataURL(for courseID: UUID) -> URL {
        return coursesDirectory.appendingPathComponent("\(courseID.uuidString).json")
    }
    
    /// Save video metadata for a course to local storage
    /// - Parameters:
    ///   - videos: Array of videos to save
    ///   - courseID: The UUID of the course
    static func saveVideos(_ videos: [VideoItem], for courseID: UUID) {
        let fileURL = metadataURL(for: courseID)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(videos)
            try data.write(to: fileURL, options: .atomic)
            ACLog("成功將影片元數據儲存到本地: \(fileURL.path)", level: .info)
        } catch {
            ACLog("儲存影片元數據到本地失敗: \(error.localizedDescription)", level: .error)
        }
    }
    
    /// Load video metadata for a course from local storage or create new if not exists
    /// - Parameters:
    ///   - courseID: The UUID of the course
    /// - Returns: Array of videos loaded from local storage or empty array
    static func loadVideos(for courseID: UUID) -> [VideoItem] {
        let fileURL = metadataURL(for: courseID)
        
        // If file exists, try to load it
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let videos = try? JSONDecoder().decode([VideoItem].self, from: data) {
            return videos
        }
        
        // Return empty array if no metadata exists
        return []
    }
    
    /// Attempt to copy local metadata to the course folder on external drive (best effort)
    /// - Parameters:
    ///   - courseID: The UUID of the course
    ///   - folderURL: The URL of the course folder on the external drive
    static func tryCopyMetadataToExternalLocation(for courseID: UUID, folderURL: URL) {
        // Only proceed if writing to external drives is enabled and not disabled globally
        guard shouldAttemptWriteToExternalDrives, !disableExternalMetadataSync else {
            ACLog("跳過複製到外部儲存裝置：功能關閉 (shouldAttemptWriteToExternalDrives=\(shouldAttemptWriteToExternalDrives) disableExternalMetadataSync=\(disableExternalMetadataSync))", level: .trace)
            return
        }
        // Throttle frequency
        let now = Date()
        if now.timeIntervalSince(lastExternalCopyTime) < externalCopyThrottle {
            ACLog("節流：距離上次外部複製不足 \(Int(externalCopyThrottle)) 秒，跳過", level: .trace)
            return
        }
        
        let localURL = metadataURL(for: courseID)
        let externalURL = folderURL.appendingPathComponent("videos.json")
        
        // Only attempt to copy if local file exists
        guard FileManager.default.fileExists(atPath: localURL.path) else { 
            ACLog("本地元數據檔案不存在，跳過複製", level: .warn)
            return 
        }
        
        // Try to copy the file, using existing security scoped access
        // The parent should have already granted access to the folder
        do {
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: externalURL.path) {
                try FileManager.default.removeItem(at: externalURL)
            }
            try FileManager.default.copyItem(at: localURL, to: externalURL)
            lastExternalCopyTime = Date()
            ACLog("成功複製元數據到外部位置: \(externalURL.path)", level: .info)
        } catch {
            ACLog("複製元數據到外部位置失敗 (非關鍵錯誤): \(error.localizedDescription)", level: .warn)
            ACLog("這通常是因為權限問題或外部儲存裝置無法寫入", level: .trace)
        }
    }
}
