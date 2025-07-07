import SwiftUI
import AVKit
import Combine

@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var courses: [Course] = [] {
        didSet {
            print("🚨 [PUBLISH DEBUG] courses changed: \(oldValue.count) -> \(courses.count)")
            print("🚨 [PUBLISH DEBUG] courses changed in @MainActor context")
        }
    }
    @Published var selectedCourseID: UUID? {
        didSet {
            if oldValue != selectedCourseID {
                print("🔄 [DEBUG] selectedCourseID changed from \(oldValue?.uuidString.prefix(8) ?? "nil") to \(selectedCourseID?.uuidString.prefix(8) ?? "nil")")
                // Schedule the change processing to avoid publishing during a view update.
                // Use asyncAfter to ensure we're completely outside the current update cycle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
                    guard let self = self else { return }
                    Task { @MainActor in
                        print("🔄 [DEBUG] Processing selectedCourseID change in delayed Task")
                        
                        // When the course changes, stop the current video playback.
                        await self.selectVideo(nil)
                        
                        // Load videos for the newly selected course if it doesn't have videos yet
                        if let course = self.selectedCourse, course.videos.isEmpty {
                            print("🔄 [DEBUG] Loading videos for course: \(course.folderURL.lastPathComponent)")
                            await self.loadVideos(for: course)
                        }
                    }
                }
            }
        }
    }
    @Published var currentVideo: VideoItem? {
        didSet {
            print("🚨 [PUBLISH DEBUG] currentVideo changed: \(oldValue?.fileName ?? "nil") -> \(currentVideo?.fileName ?? "nil")")
            print("🚨 [PUBLISH DEBUG] currentVideo changed in @MainActor context")
        }
    }
    @Published var player: AVPlayer? {
        didSet {
            print("🚨 [PUBLISH DEBUG] player changed: \(oldValue != nil ? "not nil" : "nil") -> \(player != nil ? "not nil" : "nil")")
            print("🚨 [PUBLISH DEBUG] player changed in @MainActor context")
        }
    }
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
        Task {
            await loadBookmark()
        }
    }

    deinit {
        // App 結束時，清理所有安全作用域存取權
        if let url = currentlyAccessedVideoURL {
            url.stopAccessingSecurityScopedResource()
            currentlyAccessedVideoURL = nil
            print("AppState deinit: 已停止影片檔案安全作用域存取")
        }
        // Since we can't call actor-isolated methods from deinit, directly stop accessing the resource
        if let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
            print("AppState deinit: 已停止主資料夾安全作用域存取")
        }
    }

    // MARK: - Safe UI Update Methods
    
    /// Safely set selectedCourseID without triggering publishing during view updates
    func selectCourse(_ courseID: UUID?) {
        print("🔄 [DEBUG] selectCourse called with: \(courseID?.uuidString.prefix(8) ?? "nil")")
        
        // Always defer the change to the next run loop to avoid publishing during view updates
        Task { @MainActor in
            print("🔄 [DEBUG] Processing selectCourse in Task")
            self.selectedCourseID = courseID
        }
    }

    // MARK: - Video & Player Logic
    @MainActor
    func selectVideo(_ video: VideoItem?) async {
        print("🎥 [DEBUG] selectVideo called with: \(video?.fileName ?? "nil")")
        print("🎥 [DEBUG] selectVideo - Running on @MainActor")
        
        // If we're trying to select the same video, don't do anything
        if currentVideo?.id == video?.id {
            print("🎥 [DEBUG] selectVideo - Same video already selected, skipping")
            return
        }
        
        // 1. Stop accessing the previous video's resources.
            if let previousURL = currentlyAccessedVideoURL {
                previousURL.stopAccessingSecurityScopedResource()
                currentlyAccessedVideoURL = nil
                print("Stopped accessing previous video resource: \(previousURL.path)")
            }

            // 2. If the video is deselected, clear the player and state.
            if video == nil {
                print("🎥 [DEBUG] Clearing video and player state")
                self.currentVideo = nil
                self.player = nil
                return
            }

            // 3. Set the current video and show a loading state.
            print("🎥 [DEBUG] Setting currentVideo to: \(video?.fileName ?? "unknown")")
            self.currentVideo = video
            self.player = nil

            guard let course = selectedCourse, let videoToPlay = video else { return }
            guard let sourceFolderURL = self.securityScopedURL else {
                print("CRITICAL: Cannot play video because the main folder's security scope is missing.")
                return
            }

            // 4. Start security access and create the player.
            if sourceFolderURL.startAccessingSecurityScopedResource() {
                let fileURL = course.folderURL.appendingPathComponent(videoToPlay.fileName)
                
                // 5. Create the player and update the state.
                print("🎥 [DEBUG] Creating AVPlayer for: \(fileURL.path)")
                let newPlayer = AVPlayer(url: fileURL)
                self.player = newPlayer
                self.player?.play()
                await self.markVideoAsWatched(videoToPlay)
                
                // We keep the access to the parent folder open while the player might need it.
                // It will be closed when the next video is selected or the app closes.
                self.currentlyAccessedVideoURL = sourceFolderURL
            } else {
                print("Failed to start security-scoped access for the source folder.")
            }
    }

    @MainActor
    private func markVideoAsWatched(_ video: VideoItem) async {
        print("✅ [DEBUG] markVideoAsWatched called for: \(video.fileName)")
        // Use asyncAfter to ensure we're completely outside the current update cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                print("✅ [DEBUG] Processing markVideoAsWatched in delayed Task for: \(video.fileName)")
                guard let courseIndex = self.selectedCourseIndex,
                      let videoIndex = self.courses[courseIndex].videos.firstIndex(where: { $0.id == video.id }),
                      !self.courses[courseIndex].videos[videoIndex].watched else {
                    print("✅ [DEBUG] Video already watched or not found: \(video.fileName)")
                    return
                }
                
                print("✅ [DEBUG] Marking video as watched: \(video.fileName)")
                self.courses[courseIndex].videos[videoIndex].watched = true
                
                // Save the changes in the background
                await self.saveVideos(for: self.courses[courseIndex].id)
            }
        }
    }

    func toggleFullScreen() {
        withAnimation {
            isVideoPlayerFullScreen.toggle()
        }
    }

    // MARK: - Data Handling & Permissions

    private func stopAccessingAllResources() {
        if let url = currentlyAccessedVideoURL {
            url.stopAccessingSecurityScopedResource()
            currentlyAccessedVideoURL = nil
            print("Stopped accessing video resource: \(url.path)")
        }
        if let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
            print("Stopped accessing main folder resource: \(url.path)")
        }
    }
    
    func handleFolderSelection(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }

            // First, stop all previous resource access on the main thread.
            stopAccessingAllResources()

            // Perform blocking file I/O and bookmarking on a background thread.
            Task.detached(priority: .userInitiated) {
                // Start security access to get permissions for the new folder.
                guard folder.startAccessingSecurityScopedResource() else {
                    print("ERROR: Could not start security-scoped access for the newly selected folder.")
                    return
                }

                do {
                    // Create and save the bookmark data.
                    let bookmarkData = try folder.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    // UserDefaults is thread-safe.
                    UserDefaults.standard.set(bookmarkData, forKey: self.bookmarkKey)
                    print("Successfully saved bookmark data for the new folder.")

                    // Stop access now that we have the bookmark.
                    folder.stopAccessingSecurityScopedResource()

                    // Switch back to the main actor to update state and reload content.
                    // The await on a @MainActor function handles the switch automatically.
                    await self.loadBookmark()

                } catch {
                    print("Failed to save folder bookmark: \(error.localizedDescription)")
                    // Still stop access if bookmarking fails.
                    folder.stopAccessingSecurityScopedResource()
                }
            }

        case .failure(let error):
            print("Folder selection failed: \(error.localizedDescription)")
        }
    }

    func loadBookmark() async {
        print("🔖 [DEBUG] loadBookmark called")
        // Stop any previously held security permissions before trying to load a new one.
        stopAccessingAllResources()

        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            print("找不到書籤資料。")
            return
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("🔖 [DEBUG] Bookmark is stale, clearing data")
                print("書籤已過期，需要重新選擇資料夾。")
                self.sourceFolderURL = nil
                self.courses = []
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return
            }
            
            // 嘗試開始存取安全作用域資源
            if url.startAccessingSecurityScopedResource() {
                print("🔖 [DEBUG] Security-scoped access granted for: \(url.path)")
                print("成功透過書籤取得安全作用域存取權限: \(url.path)")
                
                // 檢查權限狀態
                if let resourceValues = try? url.resourceValues(forKeys: [.isWritableKey]) {
                    let isWritable = resourceValues.isWritable ?? false
                    print("資料夾寫入權限狀態: \(isWritable ? "可寫" : "唯讀")")
                }
                
                print("🔖 [DEBUG] Setting securityScopedURL and sourceFolderURL")
                self.securityScopedURL = url
                self.sourceFolderURL = url
                
                // 重新儲存最新的書籤資料，避免因為系統變更而失效 - 在後台執行
                Task.detached {
                    do {
                        let freshBookmarkData = try url.bookmarkData(
                            options: .withSecurityScope, 
                            includingResourceValuesForKeys: nil, 
                            relativeTo: nil
                        )
                        UserDefaults.standard.set(freshBookmarkData, forKey: self.bookmarkKey)
                        print("已更新書籤資料 (讀寫權限)")
                    } catch {
                        print("警告：無法更新書籤資料：\(error.localizedDescription)")
                    }
                }
                
                print("🔖 [DEBUG] About to call loadCourses")
                // 載入課程，但不要觸發UI更新
                await self.loadCourses(from: url)
            } else {
                print("無法透過書籤取得安全作用域存取權限。")
            }
        } catch {
            print("解析書籤失敗: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    @MainActor
    func loadCourses(from sourceURL: URL) async {
        print("📚 [DEBUG] loadCourses called for: \(sourceURL.path)")
        do {
            // First load the courses on a background thread
            let newCourses = try await Task.detached {
                let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                let courseFolders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                return courseFolders.map { Course(folderURL: $0, videos: []) }
            }.value
            
            print("📚 [DEBUG] Found \(newCourses.count) courses, scheduling UI update")
            // Schedule UI updates for the next run loop to avoid "Publishing changes from within view updates"
            Task { @MainActor in
                print("📚 [DEBUG] Processing loadCourses UI update in Task")
                self.courses = newCourses
                print("載入了 \(self.courses.count) 個課程。")
                
                // If no course is selected, select the first one and load its videos
                if self.selectedCourseID == nil, let firstCourse = self.courses.first {
                    print("📚 [DEBUG] Selecting first course: \(firstCourse.folderURL.lastPathComponent)")
                    // Use the safe selection method to avoid nested publishing issues
                    self.selectCourse(firstCourse.id)
                    // Load videos for the selected course
                    await self.loadVideos(for: firstCourse)
                }
            }
        } catch {
            print("讀取課程資料夾失敗: \(error.localizedDescription)")
            print("請確認應用程式有存取所選資料夾的權限，或嘗試重新選擇資料夾")
        }
    }

    func loadVideos(for course: Course) async {
        print("🎬 [DEBUG] loadVideos called for course: \(course.folderURL.lastPathComponent)")
        guard let courseIndex = courses.firstIndex(where: { $0.id == course.id }) else { 
            print("🎬 [DEBUG] Course not found in courses array: \(course.folderURL.lastPathComponent)")
            return 
        }

        // 使用 Task.detached 在背景執行檔案操作
        do {
            let updatedVideos = try await Task.detached {
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
                
                // 讀取資料夾內容
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
                
                return updatedVideos
            }.value

            print("🎬 [DEBUG] Found \(updatedVideos.count) videos for \(course.folderURL.lastPathComponent), scheduling UI update")
            // Schedule UI updates for the next run loop to avoid "Publishing changes from within view updates"
            Task { @MainActor in
                print("🎬 [DEBUG] Processing loadVideos UI update in Task for: \(course.folderURL.lastPathComponent)")
                self.courses[courseIndex].videos = updatedVideos
                print("為課程 \(course.folderURL.lastPathComponent) 載入/更新了 \(updatedVideos.count) 個影片。")
                
                // Save updated video data
                await self.saveVideos(for: course.id)
            }
        } catch {
            print("讀取影片檔案失敗: \(error.localizedDescription)")
            print("請確認應用程式有存取所選資料夾的權限")
        }
    }

    @MainActor
    func saveVideos(for courseID: UUID) async {
        guard let course = courses.first(where: { $0.id == courseID }) else { return }
        
        // Capture all needed data before going to background
        let videosToSave = course.videos
        let folderURL = course.folderURL
        
        // Perform the file I/O on a background thread
        await Task.detached {
            // First save to local storage
            LocalMetadataStorage.saveVideos(videosToSave, for: courseID)
            
            // Then try to copy to external location if possible
            LocalMetadataStorage.tryCopyMetadataToExternalLocation(for: courseID, folderURL: folderURL)
        }.value
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
