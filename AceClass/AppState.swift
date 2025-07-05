import SwiftUI
import AVKit
import Combine

class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var courses: [Course] = []
    @Published var selectedCourseID: UUID? {
        didSet {
            // Use the implicit oldValue provided by didSet
            if oldValue != selectedCourseID {
                // Dispatch state changes asynchronously to avoid view update conflicts
                DispatchQueue.main.async {
                    self.selectVideo(nil) // Clear the previous video selection
                    if let course = self.selectedCourse {
                        self.loadVideos(for: course)
                    }
                }
            }
        }
    }
    @Published var currentVideo: VideoItem?
    @Published var currentVideoURL: URL? // Publish only the URL
    @Published var isVideoPlayerFullScreen = false
    @Published var sourceFolderURL: URL?

    // MARK: - Private Properties
    private let bookmarkKey = "selectedFolderBookmark"
    private var securityScopedURL: URL? // 持有主資料夾的安全作用域存取權
    private var currentlyAccessedVideoURL: URL? // 持有當前播放影片的獨立安全作用域存取權

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
        
        // 將狀態更新分離出來，確保不會在 View 更新期間觸發
        DispatchQueue.main.async {
            self.currentVideo = video
        }
        
        guard let course = selectedCourse, let videoToPlay = video else {
            DispatchQueue.main.async {
                self.currentVideoURL = nil
            }
            return
        }

        // 確保我們有根文件夾的安全作用域存取權限
        guard securityScopedURL != nil else {
            print("CRITICAL: 無法播放影片，因為沒有主資料夾的安全作用域存取權限")
            DispatchQueue.main.async {
                self.currentVideoURL = nil
            }
            return
        }

        // 切換到後台線程處理文件系統操作
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: course.folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                
                guard let videoURL = fileURLs.first(where: { $0.lastPathComponent == videoToPlay.fileName }) else {
                    print("ERROR: 在課程資料夾中找不到對應的影片檔案: \(videoToPlay.fileName)")
                    DispatchQueue.main.async {
                        self.currentVideoURL = nil
                        self.currentVideo = nil
                    }
                    return
                }
                
                // 嘗試為個別影片獲取額外的安全作用域存取權限
                // 這是必要的，因為 AVPlayer 可能在不同的進程中播放，需要自己的權限
                guard videoURL.startAccessingSecurityScopedResource() else {
                    print("CRITICAL: 無法為影片檔案啟動安全作用域存取: \(videoURL.path)")
                    
                    // 嘗試用其他方式訪問
                    if let secURL = self.securityScopedURL, secURL.path.isEmpty == false {
                        print("嘗試使用主資料夾的權限存取影片")
                        // 確保 secURL 有效並在存取狀態
                        if secURL.startAccessingSecurityScopedResource() {
                            // 使用相對路徑構建新的 URL
                            let relativeVideoPath = videoURL.path.replacingOccurrences(of: secURL.path, with: "")
                            let newVideoURL = secURL.appendingPathComponent(relativeVideoPath)
                            
                            print("使用替代路徑: \(newVideoURL.path)")
                            DispatchQueue.main.async {
                                self.currentlyAccessedVideoURL = videoURL
                                self.currentVideoURL = newVideoURL
                                self.markVideoAsWatched(videoToPlay)
                            }
                            return
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.currentVideoURL = nil
                        self.currentVideo = nil
                    }
                    return
                }
                
                // 在主線程更新 UI
                DispatchQueue.main.async {
                    // 儲存此 URL，以便之後可以釋放其存取權，然後發布它
                    self.currentlyAccessedVideoURL = videoURL
                    self.currentVideoURL = videoURL
                    print("已啟動影片資源存取並發布 URL: \(videoURL.path)")
                    
                    self.markVideoAsWatched(videoToPlay)
                }
            } catch {
                print("ERROR: 無法列舉課程資料夾內容以尋找影片: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.currentVideoURL = nil
                    self.currentVideo = nil
                }
            }
        }
    }

    private func markVideoAsWatched(_ video: VideoItem) {
        // 切換到主線程，確保狀態更新在視圖更新循環之外
        DispatchQueue.main.async {
            guard let courseIndex = self.selectedCourseIndex,
                  let videoIndex = self.courses[courseIndex].videos.firstIndex(where: { $0.id == video.id }),
                  !self.courses[courseIndex].videos[videoIndex].watched else {
                return
            }
            
            self.courses[courseIndex].videos[videoIndex].watched = true
            
            // 在狀態更新後異步保存，避免在視圖更新期間執行 IO
            DispatchQueue.global(qos: .background).async {
                self.saveVideos(for: self.courses[courseIndex].id)
            }
        }
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
            
            // 清理舊的權限
            stopAccessingResources()

            // 使用安全作用域書籤來持久化權限，請求讀寫權限
            do {
                // 不使用 .securityScopeAllowOnlyReadAccess 選項，以獲取完整的讀寫權限
                let bookmarkData = try folder.bookmarkData(
                    options: .withSecurityScope, 
                    includingResourceValuesForKeys: nil, 
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
                print("已儲存資料夾書籤資料 (讀寫權限)。")
                
                // 直接使用新資料夾重新載入所有內容
                if folder.startAccessingSecurityScopedResource() {
                    print("成功為新選擇的資料夾啟動安全作用域存取: \(folder.path)")
                    self.securityScopedURL = folder
                    self.sourceFolderURL = folder
                    // 確保UI更新在主線程
                    DispatchQueue.main.async {
                        self.selectedCourseID = nil
                        self.currentVideo = nil
                    }
                    self.loadCourses(from: folder)
                } else {
                    print("CRITICAL: 無法為新選擇的資料夾啟動安全作用域存取。")
                }
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
            
            // 嘗試開始存取安全作用域資源
            if url.startAccessingSecurityScopedResource() {
                print("成功透過書籤取得安全作用域存取權限: \(url.path)")
                self.securityScopedURL = url
                self.sourceFolderURL = url
                
                // 重新儲存最新的書籤資料，避免因為系統變更而失效
                do {
                    // 使用讀寫權限
                    let freshBookmarkData = try url.bookmarkData(
                        options: .withSecurityScope, 
                        includingResourceValuesForKeys: nil, 
                        relativeTo: nil
                    )
                    UserDefaults.standard.set(freshBookmarkData, forKey: bookmarkKey)
                    print("已更新書籤資料 (讀寫權限)")
                } catch {
                    print("警告：無法更新書籤資料：\(error.localizedDescription)")
                }
                
                // 載入課程，但不要觸發UI更新
                self.loadCourses(from: url)
            } else {
                print("無法透過書籤取得安全作用域存取權限。")
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
        // 將檔案讀取操作移至後台線程
        DispatchQueue.global(qos: .background).async {
            // 此函數假定 sourceURL 的存取權限已在外部被啟動並持有
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                let courseFolders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                
                let newCourses = courseFolders.map { Course(folderURL: $0, videos: []) }

                // 在主線程更新 UI 相關屬性
                DispatchQueue.main.async {
                    self.courses = newCourses
                    print("已載入 \(self.courses.count) 個課程。")
                    // 如果沒有選擇任何課程，則自動選擇第一個
                    if self.selectedCourseID == nil {
                        self.selectedCourseID = self.courses.first?.id
                    }
                }
            } catch {
                print("讀取課程資料夾失敗: \(error.localizedDescription)")
            }
        }
    }

    func loadVideos(for course: Course) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }) else { return }

        // 將檔案讀取和處理操作移至後台線程
        DispatchQueue.global(qos: .background).async {
            // 先從本地元數據存儲中讀取
            var loadedVideos = LocalMetadataStorage.loadVideos(for: course.id)
            
            // 如果本地無數據，嘗試從外部讀取（向後兼容）
            if loadedVideos.isEmpty {
                let jsonURL = course.folderURL.appendingPathComponent("videos.json")
                if let data = try? Data(contentsOf: jsonURL),
                   let decodedVideos = try? JSONDecoder().decode([VideoItem].self, from: data) {
                    loadedVideos = decodedVideos
                    // 順便保存到本地元數據存儲中
                    LocalMetadataStorage.saveVideos(decodedVideos, for: course.id)
                }
            }
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: course.folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                let videoFiles = contents.filter { $0.pathExtension.lowercased() == "mp4" }
                
                var updatedVideos: [VideoItem] = []
                let loadedFileNames = Set(loadedVideos.map { $0.fileName })

                // 加入已有的影片
                updatedVideos.append(contentsOf: loadedVideos)

                // 加入資料夾中新增的影片
                for fileURL in videoFiles {
                    if !loadedFileNames.contains(fileURL.lastPathComponent) {
                        updatedVideos.append(VideoItem(fileName: fileURL.lastPathComponent))
                    }
                }
                
                // 移除在JSON中但已從資料夾刪除的影片
                let fileNamesOnDisk = Set(videoFiles.map { $0.lastPathComponent })
                updatedVideos.removeAll { !fileNamesOnDisk.contains($0.fileName) }

                // 依日期排序
                updatedVideos.sort {
                    guard let date1 = $0.date, let date2 = $1.date else {
                        return $0.fileName < $1.fileName
                    }
                    return date1 < date2
                }
                
                // 在主線程更新 UI
                DispatchQueue.main.async {
                    self.courses[courseIndex].videos = updatedVideos
                    print("為課程 \(course.folderURL.lastPathComponent) 載入/更新了 \(updatedVideos.count) 個影片。")
                    // 保存更新後的視頻數據
                    self.saveVideos(for: course.id)
                }
            } catch {
                print("讀取影片檔案失敗: \(error.localizedDescription)")
            }
        }
    }

    func saveVideos(for courseID: UUID) {
        guard let course = courses.first(where: { $0.id == courseID }) else { return }
        
        // 使用本地元數據存儲，同時支持可選的外部驅動器寫入
        let videosToSave = course.videos
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 將元數據保存到本地應用支持目錄
            LocalMetadataStorage.saveVideos(videosToSave, for: courseID)
            
            // 嘗試將元數據複製到外部驅動器（根據設置決定是否嘗試，預設為開啟）
            // LocalMetadataStorage.shouldAttemptWriteToExternalDrives 控制是否執行此操作
            LocalMetadataStorage.tryCopyMetadataToExternalLocation(for: courseID, folderURL: course.folderURL)
        }
    }
}
