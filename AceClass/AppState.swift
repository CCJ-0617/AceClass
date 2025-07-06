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
                // Use async dispatch to avoid publishing changes within view updates
                Task { @MainActor in
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
        
        // 3. 更新當前影片狀態
        Task { @MainActor in
            self.currentVideo = video
        }
        
        guard let course = selectedCourse, let videoToPlay = video else {
            Task { @MainActor in
                self.currentVideoURL = nil
            }
            return
        }

        // 確保我們有根文件夾的安全作用域存取權限
        guard securityScopedURL != nil else {
            print("CRITICAL: 無法播放影片，因為沒有主資料夾的安全作用域存取權限")
            Task { @MainActor in
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
                    Task { @MainActor in
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
                            Task { @MainActor in
                                self.currentlyAccessedVideoURL = videoURL
                                self.currentVideoURL = newVideoURL
                                self.markVideoAsWatched(videoToPlay)
                            }
                            return
                        }
                    }
                    
                    Task { @MainActor in
                        self.currentVideoURL = nil
                        self.currentVideo = nil
                    }
                    return
                }
                
                // 在主線程更新 UI
                Task { @MainActor in
                    // 儲存此 URL，以便之後可以釋放其存取權，然後發布它
                    self.currentlyAccessedVideoURL = videoURL
                    self.currentVideoURL = videoURL
                    print("已啟動影片資源存取並發布 URL: \(videoURL.path)")
                    
                    self.markVideoAsWatched(videoToPlay)
                }
            } catch {
                print("ERROR: 無法列舉課程資料夾內容以尋找影片: \(error.localizedDescription)")
                Task { @MainActor in
                    self.currentVideoURL = nil
                    self.currentVideo = nil
                }
            }
        }
    }

    private func markVideoAsWatched(_ video: VideoItem) {
        // 使用 Task 確保狀態更新在視圖更新循環之外
        Task { @MainActor in
            guard let courseIndex = self.selectedCourseIndex,
                  let videoIndex = self.courses[courseIndex].videos.firstIndex(where: { $0.id == video.id }),
                  !self.courses[courseIndex].videos[videoIndex].watched else {
                return
            }
            
            self.courses[courseIndex].videos[videoIndex].watched = true
            
            // 在狀態更新後異步保存，避免在視圖更新期間執行 IO
            Task.detached(priority: .background) {
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

            // 首先啟動安全作用域存取以獲得權限
            guard folder.startAccessingSecurityScopedResource() else {
                print("ERROR: 無法啟動新選擇資料夾的安全作用域存取")
                return
            }
            
            // 使用安全作用域書籤來持久化權限，請求讀寫權限
            do {
                // 首先測試是否可以讀取資料夾內容
                let testContents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isWritableKey], options: .skipsHiddenFiles)
                print("成功讀取資料夾內容，包含 \(testContents.count) 個項目")
                
                // 檢查資料夾是否可寫
                var isWritable = false
                if let resourceValues = try? folder.resourceValues(forKeys: [.isWritableKey]) {
                    isWritable = resourceValues.isWritable ?? false
                }
                print("資料夾寫入權限狀態: \(isWritable ? "可寫" : "唯讀")")
                
                // 不使用 .securityScopeAllowOnlyReadAccess 選項，以獲取完整的讀寫權限
                let bookmarkData = try folder.bookmarkData(
                    options: .withSecurityScope, 
                    includingResourceValuesForKeys: nil, 
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
                print("已儲存資料夾書籤資料 (讀寫權限)。")
                
                // 設定狀態並重新載入內容
                print("成功為新選擇的資料夾啟動安全作用域存取: \(folder.path)")
                self.securityScopedURL = folder
                self.sourceFolderURL = folder
                // 確保UI更新在主線程
                Task { @MainActor in
                    self.selectedCourseID = nil
                    self.currentVideo = nil
                }
                self.loadCourses(from: folder)
                
            } catch {
                print("儲存資料夾書籤失敗: \(error.localizedDescription)")
                // 如果書籤儲存失敗，至少嘗試載入內容
                print("儘管書籤儲存失敗，仍嘗試載入課程內容")
                self.securityScopedURL = folder
                self.sourceFolderURL = folder
                Task { @MainActor in
                    self.selectedCourseID = nil
                    self.currentVideo = nil
                }
                self.loadCourses(from: folder)
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
                
                // 檢查權限狀態
                if let resourceValues = try? url.resourceValues(forKeys: [.isWritableKey]) {
                    let isWritable = resourceValues.isWritable ?? false
                    print("資料夾寫入權限狀態: \(isWritable ? "可寫" : "唯讀")")
                }
                
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
            // 假設調用者已經有了適當的權限
            // 不需要重複請求 startAccessingSecurityScopedResource
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                let courseFolders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                
                let newCourses = courseFolders.map { Course(folderURL: $0, videos: []) }

                // 在主線程更新 UI 相關屬性
                Task { @MainActor in
                    self.courses = newCourses
                    print("已載入 \(self.courses.count) 個課程。")
                    // 如果沒有選擇任何課程，則自動選擇第一個
                    if self.selectedCourseID == nil {
                        self.selectedCourseID = self.courses.first?.id
                    }
                }
            } catch {
                print("讀取課程資料夾失敗: \(error.localizedDescription)")
                print("請確認應用程式有存取所選資料夾的權限，或嘗試重新選擇資料夾")
            }
        }
    }

    func loadVideos(for course: Course) {
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }) else { return }

        // 將檔案讀取和處理操作移至後台線程
        DispatchQueue.global(qos: .background).async {
            // 假設父級已經有了適當的權限，不需要重複請求
            
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
                Task { @MainActor in
                    self.courses[courseIndex].videos = updatedVideos
                    print("為課程 \(course.folderURL.lastPathComponent) 載入/更新了 \(updatedVideos.count) 個影片。")
                    // 保存更新後的視頻數據
                    Task.detached(priority: .background) {
                        self.saveVideos(for: course.id)
                    }
                }
            } catch {
                print("讀取影片檔案失敗: \(error.localizedDescription)")
                // 如果讀取失敗，可能是權限問題，提示用戶
                Task { @MainActor in
                    // 可以在這裡觸發一個錯誤狀態或提示
                    print("請確認應用程式有存取所選資料夾的權限")
                }
            }
        }
    }

    func saveVideos(for courseID: UUID) {
        guard let course = courses.first(where: { $0.id == courseID }) else { return }
        
        // 使用本地元數據存儲，同時支持可選的外部驅動器寫入
        let videosToSave = course.videos
        
        // 將元數據保存到本地應用支持目錄
        LocalMetadataStorage.saveVideos(videosToSave, for: courseID)
        
        // 嘗試將元數據複製到外部驅動器（需要在有安全作用域權限的情況下）
        if let secURL = securityScopedURL, secURL.startAccessingSecurityScopedResource() {
            defer { secURL.stopAccessingSecurityScopedResource() }
            LocalMetadataStorage.tryCopyMetadataToExternalLocation(for: courseID, folderURL: course.folderURL)
        }
    }
    
    // MARK: - Debug Methods
    
    /// Debug method to check current permission status
    func debugPermissionStatus() {
        print("=== 權限狀態調試 ===")
        
        if let secURL = securityScopedURL {
            print("安全作用域 URL: \(secURL.path)")
            
            // 檢查權限
            if let resourceValues = try? secURL.resourceValues(forKeys: [.isReadableKey, .isWritableKey]) {
                print("可讀: \(resourceValues.isReadable ?? false)")
                print("可寫: \(resourceValues.isWritable ?? false)")
            }
            
            // 嘗試讀取目錄
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: secURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                print("可以讀取目錄，包含 \(contents.count) 個項目")
            } catch {
                print("無法讀取目錄: \(error.localizedDescription)")
            }
        } else {
            print("沒有安全作用域 URL")
        }
        
        print("==================")
    }
}
