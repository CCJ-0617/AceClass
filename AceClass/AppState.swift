import SwiftUI
import AVKit
import Combine

class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var courses: [Course] = []
    @Published var selectedCourseID: UUID? {
        didSet {
            if oldValue != selectedCourseID {
                // 將狀態變更異步派發，避免在 View 更新期間發布變更
                DispatchQueue.main.async {
                    self.selectVideo(nil)
                    if let course = self.selectedCourse {
                        self.loadVideos(for: course)
                    }
                }
            }
        }
    }
    @Published var currentVideo: VideoItem?
    @Published var currentVideoURL: URL? // *** 改為只發布 URL ***
    @Published var isVideoPlayerFullScreen = false
    @Published var sourceFolderURL: URL?
    @Published var showFullDiskAccessAlert = false

    // MARK: - Private Properties
    private let bookmarkKey = "selectedFolderBookmark"
    private var securityScopedURL: URL? // 持有主資料夾的安全作用域存取權
    private var currentlyAccessedVideoURL: URL? // 持有當前播放影片的精細存取權

    // MARK: - Computed Properties
    var selectedCourse: Course? {
        guard let id = selectedCourseID else { return nil }
        return courses.first(where: { $0.id == id })
    }

    var selectedCourseIndex: Int? {
        courses.firstIndex(where: { $0.id == selectedCourseID })
    }
    
    // MARK: - Initializer & Deinitializer
    init() {
        loadBookmark()
        
        // 如果沒有選擇資料夾，在啟動一段時間後檢查完整磁碟權限
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.sourceFolderURL == nil && !self.hasFullDiskAccess() {
                self.showFullDiskAccessAlert = true
            }
        }
    }

    deinit {
        // App 結束時，清理所有安全作用域存取權
        if let url = currentlyAccessedVideoURL {
            url.stopAccessingSecurityScopedResource()
            currentlyAccessedVideoURL = nil
            print("AppState deinit: 已停止影片檔案安全作用域存取")
        }
        stopAccessingResources()
    }

    // MARK: - Video & Player Logic
    func selectVideo(_ video: VideoItem?) {
        // 1. 在執行任何操作前，先停止存取上一個影片的 URL
        if let previousURL = currentlyAccessedVideoURL {
            previousURL.stopAccessingSecurityScopedResource()
            currentlyAccessedVideoURL = nil
            print("已停止存取先前的影片資源: \(previousURL.path)")
        }
        
        // 2. 如果是取消選擇目前影片，或傳入 nil，則清空 URL 後直接返回
        if video == nil || currentVideo?.id == video?.id {
            self.currentVideoURL = nil
            self.currentVideo = nil
            return
        }
        
        self.currentVideo = video
        
        guard let course = selectedCourse, let videoToPlay = video else {
            self.currentVideoURL = nil
            return
        }

        // *** 修正：透過列舉目錄內容來取得具有正確安全作用域的 URL ***
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: course.folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            guard let videoURL = fileURLs.first(where: { $0.lastPathComponent == videoToPlay.fileName }) else {
                print("ERROR: 在課程資料夾中找不到對應的影片檔案: \(videoToPlay.fileName)")
                self.currentVideoURL = nil
                self.currentVideo = nil
                return
            }
            
            // 3. 在發布 URL 前，為這個特定的影片檔案啟動安全作用域存取
            guard videoURL.startAccessingSecurityScopedResource() else {
                print("CRITICAL: 無法為影片檔案啟動安全作用域存取: \(videoURL.path)")
                self.currentVideoURL = nil
                self.currentVideo = nil
                return
            }
            
            // 4. 儲存此 URL，以便之後可以釋放其存取權，然後發布它
            self.currentlyAccessedVideoURL = videoURL
            self.currentVideoURL = videoURL
            print("已啟動影片資源存取並發布 URL: \(videoURL.path)")
            
            markVideoAsWatched(videoToPlay)

        } catch {
            print("ERROR: 無法列舉課程資料夾內容以尋找影片: \(error.localizedDescription)")
            self.currentVideoURL = nil
            self.currentVideo = nil
        }
    }

    private func markVideoAsWatched(_ video: VideoItem) {
        guard let courseIndex = selectedCourseIndex,
              let videoIndex = courses[courseIndex].videos.firstIndex(where: { $0.id == video.id }),
              !courses[courseIndex].videos[videoIndex].watched else {
            return
        }
        
        courses[courseIndex].videos[videoIndex].watched = true
        saveVideos(for: courses[courseIndex].id)
    }

    func toggleFullScreen() {
        withAnimation {
            isVideoPlayerFullScreen.toggle()
        }
    }

    // MARK: - Data Handling & Permissions
    
    func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            
            // 使用安全作用域書籤來持久化權限
            do {
                let bookmarkData = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
                print("已儲存資料夾書籤資料。")
                
                // 使用新資料夾重新載入所有內容
                loadBookmark()
                self.selectedCourseID = nil
                self.currentVideo = nil
            } catch {
                print("儲存資料夾書籤失敗: \(error.localizedDescription)")
            }
            
        case .failure(let error):
            print("選擇資料夾失敗: \(error.localizedDescription)")
        }
    }

    func loadBookmark() {
        stopAccessingResources() // 釋放任何先前的書籤權限

        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            print("找不到書籤資料。")
            return
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("書籤已過期，需要重新選擇資料夾。")
                self.sourceFolderURL = nil
                self.courses = []
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return
            }
            
            if url.startAccessingSecurityScopedResource() {
                print("成功透過書籤取得安全作用域存取權限: \(url.path)")
                self.securityScopedURL = url
                self.sourceFolderURL = url
                self.loadCourses(from: url)
            } else {
                print("無法透過書籤取得安全作用域存取權限。")
                self.showFullDiskAccessAlert = true
            }
        } catch {
            print("解析書籤失敗: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    func stopAccessingResources() {
        if let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
            print("AppState: 已停止主資料夾安全作用域存取權限")
        }
    }

    func loadCourses(from sourceURL: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            let courseFolders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            
            DispatchQueue.main.async {
                self.courses = courseFolders.map { Course(folderURL: $0, videos: []) }
                print("已載入 \(self.courses.count) 個課程。")
                // 如果沒有選擇任何課程，則自動選擇第一個
                if self.selectedCourseID == nil {
                    self.selectedCourseID = self.courses.first?.id
                }
            }
        } catch {
            print("讀取課程資料夾失敗: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.showFullDiskAccessAlert = true
            }
        }
    }

    func loadVideos(for course: Course) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }) else { return }
        
        let jsonURL = course.folderURL.appendingPathComponent("videos.json")
        var loadedVideos: [VideoItem] = []
        if let data = try? Data(contentsOf: jsonURL),
           let decodedVideos = try? JSONDecoder().decode([VideoItem].self, from: data) {
            loadedVideos = decodedVideos
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: course.folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let videoFiles = contents.filter { $0.pathExtension.lowercased() == "mp4" }
            
            var updatedVideos: [VideoItem] = []
            let loadedFileNames = Set(loadedVideos.map { $0.fileName })

            // 加入 JSON 中已有的影片
            updatedVideos.append(contentsOf: loadedVideos)

            // 加入資料夾中新增的影片
            for fileURL in videoFiles {
                if !loadedFileNames.contains(fileURL.lastPathComponent) {
                    updatedVideos.append(VideoItem(fileName: fileURL.lastPathComponent))
                }
            }
            
            // 移除在 JSON 中但已從資料夾刪除的影片
            let fileNamesOnDisk = Set(videoFiles.map { $0.lastPathComponent })
            updatedVideos.removeAll { !fileNamesOnDisk.contains($0.fileName) }

            // 依日期排序
            updatedVideos.sort {
                guard let date1 = $0.date, let date2 = $1.date else {
                    return $0.fileName < $1.fileName
                }
                return date1 < date2
            }
            
            DispatchQueue.main.async {
                self.courses[courseIndex].videos = updatedVideos
                print("為課程 \(course.folderURL.lastPathComponent) 載入/更新了 \(updatedVideos.count) 個影片。")
                self.saveVideos(for: course.id)
            }
        } catch {
            print("讀取影片檔案失敗: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.showFullDiskAccessAlert = true
            }
        }
    }

    func saveVideos(for courseID: UUID) {
        guard let course = courses.first(where: { $0.id == courseID }) else { return }
        
        let jsonURL = course.folderURL.appendingPathComponent("videos.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(course.videos)
            try data.write(to: jsonURL)
            print("已將影片資料儲存至 \(jsonURL.path)")
        } catch {
            print("儲存影片資料失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - Full Disk Access Helpers
    
    func hasFullDiskAccess() -> Bool {
        let testPath = ("~/Library/Application Support" as NSString).expandingTildeInPath
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: testPath)
            print("完整磁碟取用權限：已取得")
            return true
        } catch {
            print("完整磁碟取用權限檢查失敗: \(error.localizedDescription)")
            return false
        }
    }
    
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess") {
            NSWorkspace.shared.open(url)
        }
    }
}
