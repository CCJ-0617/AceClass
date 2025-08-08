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
                // Schedule the change processing to avoid publishing during view updates.
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
    
    // VERBOSE DIAGNOSTICS
    nonisolated private func logURLDiagnostics(_ url: URL, context: String) {
        print("🔎 [DIAG] Context=\(context)")
        print("🔎 [DIAG] URL path=\(url.path)")
        do {
            let keys: Set<URLResourceKey> = [
                .isReadableKey,
                .isWritableKey,
                .isDirectoryKey,
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsLocalKey,
                .volumeIsReadOnlyKey
            ]
            let values = try url.resourceValues(forKeys: keys)
            print("🔎 [DIAG] isDirectory=\(values.isDirectory ?? false) isReadable=\(values.isReadable ?? false) isWritable=\(values.isWritable ?? false)")
            print("🔎 [DIAG] volume name=\(values.volumeName ?? "nil") removable=\(values.volumeIsRemovable ?? false) local=\(values.volumeIsLocal ?? false) readOnly=\(values.volumeIsReadOnly ?? false)")
        } catch {
            print("🔎 [DIAG] Failed to read URL resource values: \(error.localizedDescription)")
        }
    }
    
    func handleFolderSelection(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            print("📁 [DEBUG] fileImporter returned \(urls.count) URL(s)")
            if let first = urls.first {
                logURLDiagnostics(first, context: "fileImporter selection (pre-security-scope)")
            }
            guard let folder = urls.first else { return }

            // First, stop all previous resource access on the main thread.
            stopAccessingAllResources()

            // Perform blocking file I/O and bookmarking on a background thread.
            Task.detached(priority: .userInitiated) {
                print("📁 [DEBUG] Attempting startAccessingSecurityScopedResource on selected folder…")
                // Start security access to get permissions for the new folder.
                guard folder.startAccessingSecurityScopedResource() else {
                    print("ERROR: Could not start security-scoped access for the newly selected folder.")
                    self.logURLDiagnostics(folder, context: "startAccessingSecurityScopedResource FAILED")
                    print("HINT: Ensure 'com.apple.security.files.user-selected.read-write' entitlement is enabled and that the folder was chosen via the system picker.")
                    return
                }
                self.logURLDiagnostics(folder, context: "startAccessingSecurityScopedResource SUCCEEDED")

                do {
                    // Create and save the bookmark data.
                    let bookmarkData = try folder.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    // UserDefaults is thread-safe.
                    UserDefaults.standard.set(bookmarkData, forKey: self.bookmarkKey)
                    print("Successfully saved bookmark data for the new folder. size=\(bookmarkData.count) bytes")

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
        print("🔖 [DEBUG] bookmarkData size=\(bookmarkData.count) bytes")
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            print("🔖 [DEBUG] Resolved bookmark URL: \(url.path) isStale=\(isStale)")
            logURLDiagnostics(url, context: "after resolving bookmark (pre-startAccess)")
            
            if isStale {
                print("🔖 [DEBUG] Bookmark is stale, attempting to refresh bookmark data instead of clearing")
                do {
                    let refreshed = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                    print("🔖 [DEBUG] Refreshed stale bookmark successfully. size=\(refreshed.count) bytes")
                } catch {
                    print("⚠️ [DEBUG] Failed to refresh stale bookmark: \(error.localizedDescription). Will proceed with resolved URL anyway.")
                }
            }
            
            // 嘗試開始存取安全作用域資源
            if url.startAccessingSecurityScopedResource() {
                print("🔖 [DEBUG] Security-scoped access granted for: \(url.path)")
                print("成功透過書籤取得安全作用域存取權限: \(url.path)")
                
                // 檢查權限狀態
                if let resourceValues = try? url.resourceValues(forKeys: [.isWritableKey, .isReadableKey]) {
                    let isWritable = resourceValues.isWritable ?? false
                    let isReadable = resourceValues.isReadable ?? false
                    print("資料夾權限狀態: 讀=\(isReadable ? "可讀" : "不可讀") 寫=\(isWritable ? "可寫" : "唯讀")")
                }
                
                // Quick probe: attempt to list directory to confirm effective access
                do {
                    let probe = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                    print("🔖 [DEBUG] Probe listing count=\(probe.count) (post-startAccess)")
                } catch {
                    print("⚠️ [DEBUG] Probe listing failed even after startAccess: \(error.localizedDescription)")
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
                        print("已更新書籤資料 (讀寫權限)，size=\(freshBookmarkData.count) bytes")
                    } catch {
                        print("警告：無法更新書籤資料：\(error.localizedDescription)")
                    }
                }
                
                print("🔖 [DEBUG] About to call loadCourses")
                // 載入課程，但不要觸發UI更新
                await self.loadCourses(from: url)
                
                // 額外列印目前的權限與可讀性檢查
                self.debugPermissionStatus()
            } else {
                print("無法透過書籤取得安全作用域存取權限：\(url.path)")
                logURLDiagnostics(url, context: "startAccessingSecurityScopedResource FAILED in loadBookmark")
                // Last resort diagnostic: try a non-scoped directory listing (may fail under sandbox)
                do {
                    let probe = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                    print("🔖 [DEBUG] Fallback non-scoped listing count=\(probe.count)")
                } catch {
                    print("🔖 [DEBUG] Fallback non-scoped listing failed: \(error.localizedDescription)")
                }
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
            let loadResult = try await Task.detached { () -> (courseFolders: [URL], rootVideoFiles: [URL]) in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: sourceURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: .skipsHiddenFiles
                )
                let folders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                // Also check if there are videos directly under the selected folder
                let files = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false }
                let rootVideos = files.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
                return (folders, rootVideos)
            }.value
            
            let courseFolders = loadResult.courseFolders
            let rootVideoFiles = loadResult.rootVideoFiles
            
            print("📚 [DEBUG] Found \(courseFolders.count) course folders; root has \(rootVideoFiles.count) video files (mp4/mov/m4v)")
            
            // Schedule UI updates for the next run loop to avoid "Publishing changes from within view updates"
            Task { @MainActor in
                print("📚 [DEBUG] Processing loadCourses UI update in Task")
                
                var coursesWithMetadata: [Course] = []
                
                if !courseFolders.isEmpty {
                    // Normal case: each subfolder is a course
                    for folderURL in courseFolders {
                        if let existingCourse = self.courses.first(where: { $0.folderURL.path == folderURL.path }) {
                            coursesWithMetadata.append(existingCourse)
                        } else {
                            let newCourse = Course(folderURL: folderURL, videos: [])
                            let (targetDate, targetDescription) = await self.loadCourseMetadata(for: newCourse.id)
                            let courseWithMetadata = Course(
                                id: newCourse.id,
                                folderURL: folderURL,
                                videos: [],
                                targetDate: targetDate,
                                targetDescription: targetDescription
                            )
                            coursesWithMetadata.append(courseWithMetadata)
                        }
                    }
                } else if !rootVideoFiles.isEmpty {
                    // Fallback: selected folder itself contains videos; treat it as a single course
                    let folderURL = sourceURL
                    if let existingCourse = self.courses.first(where: { $0.folderURL.path == folderURL.path }) {
                        coursesWithMetadata.append(existingCourse)
                    } else {
                        let newCourse = Course(folderURL: folderURL, videos: [])
                        let (targetDate, targetDescription) = await self.loadCourseMetadata(for: newCourse.id)
                        let courseWithMetadata = Course(
                            id: newCourse.id,
                            folderURL: folderURL,
                            videos: [],
                            targetDate: targetDate,
                            targetDescription: targetDescription
                        )
                        coursesWithMetadata.append(courseWithMetadata)
                    }
                } else {
                    print("📚 [DEBUG] No subfolders and no supported video files found under the selected folder")
                    // Provide a short directory listing to aid debugging
                    let listing: [String]? = try? await Task.detached(priority: .utility) { () throws -> [String] in
                        let contents = try FileManager.default.contentsOfDirectory(
                            at: sourceURL,
                            includingPropertiesForKeys: [.isDirectoryKey],
                            options: .skipsHiddenFiles
                        )
                        return contents.prefix(20).map { url in
                            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                            return "- \(url.lastPathComponent) \(isDir ? "[DIR]" : "[FILE] ext=\(url.pathExtension.lowercased())")"
                        }
                    }.value
                    if let listing = listing {
                        print("📚 [DEBUG] Directory listing (up to 20):\n" + listing.joined(separator: "\n"))
                    }
                }
                
                self.courses = coursesWithMetadata
                print("載入了 \(self.courses.count) 個課程。")
                
                // If no course is selected, select the first one and load its videos
                if self.selectedCourseID == nil, let firstCourse = self.courses.first {
                    print("📚 [DEBUG] Selecting first course: \(firstCourse.folderURL.lastPathComponent)")
                    self.selectCourse(firstCourse.id)
                    await self.loadVideos(for: firstCourse)
                }
            }
        } catch {
            print("讀取課程資料夾失敗: \(error.localizedDescription) at: \(sourceURL.path)")
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
                let videoFiles = contents.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
                
                var updatedVideos: [VideoItem] = []
                
                // 若沒有任何影片，附上簡要清單協助偵錯
                if videoFiles.isEmpty {
                    let debugList = contents.prefix(20).map { url in "- \(url.lastPathComponent) [ext=\(url.pathExtension.lowercased())]" }
                    print("🎬 [DEBUG] No supported video files found. Directory sample (up to 20):\n" + debugList.joined(separator: "\n"))
                }
                
                for fileURL in videoFiles {
                    let fileName = fileURL.lastPathComponent
                    if let existing = loadedVideos.first(where: { $0.fileName == fileName }) {
                        updatedVideos.append(existing)
                    } else {
                        updatedVideos.append(VideoItem(fileName: fileName))
                    }
                }
                
                // 根據日期排序，無日期者放最後
                updatedVideos.sort { (a, b) -> Bool in
                    switch (a.date, b.date) {
                    case let (date1?, date2?):
                        return date1 < date2
                    case (nil, nil):
                        return a.displayName.localizedCompare(b.displayName) == .orderedAscending
                    case (nil, _):
                        return false
                    case (_, nil):
                        return true
                    }
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
    
    // MARK: - Countdown Management
    
    /// 設定課程的目標日期和描述
    @MainActor
    func setTargetDate(for courseID: UUID, targetDate: Date?, description: String) async {
        print("📅 [DEBUG] Setting target date for course: \(courseID.uuidString.prefix(8))")
        
        guard let courseIndex = courses.firstIndex(where: { $0.id == courseID }) else {
            print("📅 [DEBUG] Course not found for setting target date")
            return
        }
        
        courses[courseIndex].targetDate = targetDate
        courses[courseIndex].targetDescription = description
        
        print("📅 [DEBUG] Target date set: \(targetDate?.formatted(date: .abbreviated, time: .omitted) ?? "nil")")
        print("📅 [DEBUG] Description: \(description)")
        
        // 保存課程數據
        await saveCourseMetadata(for: courseID)
    }
    
    /// 獲取指定課程的倒數計日資訊
    func getCountdownInfo(for courseID: UUID) -> (daysRemaining: Int?, countdownText: String, isOverdue: Bool) {
        guard let course = courses.first(where: { $0.id == courseID }) else {
            return (nil, "課程未找到", false)
        }
        
        return (course.daysRemaining, course.countdownText, course.isOverdue)
    }
    
    /// 獲取所有即將到期的課程（7天內）
    var upcomingDeadlines: [Course] {
        return courses.filter { course in
            guard let daysRemaining = course.daysRemaining else { return false }
            return daysRemaining >= 0 && daysRemaining <= 7
        }.sorted { course1, course2 in
            let days1 = course1.daysRemaining ?? Int.max
            let days2 = course2.daysRemaining ?? Int.max
            return days1 < days2
        }
    }
    
    /// 獲取所有過期的課程
    var overdueCoures: [Course] {
        return courses.filter { $0.isOverdue }.sorted { course1, course2 in
            let days1 = abs(course1.daysRemaining ?? 0)
            let days2 = abs(course2.daysRemaining ?? 0)
            return days1 > days2 // 過期最久的排在前面
        }
    }
    
    /// 保存課程元數據（包括倒數計日資訊）
    @MainActor
    private func saveCourseMetadata(for courseID: UUID) async {
        guard let course = courses.first(where: { $0.id == courseID }) else { return }
        
        let courseData = course
        
        // 在背景線程保存數據
        await Task.detached {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(courseData)
                
                // 保存到 UserDefaults 中（使用課程ID作為鍵值）
                let key = "course_metadata_\(courseID.uuidString)"
                UserDefaults.standard.set(data, forKey: key)
                
                print("📅 [DEBUG] Course metadata saved for: \(courseID.uuidString.prefix(8))")
            } catch {
                print("📅 [ERROR] Failed to save course metadata: \(error.localizedDescription)")
            }
        }.value
    }
    
    /// 載入課程元數據（包括倒數計日資訊）
    @MainActor
    private func loadCourseMetadata(for courseID: UUID) async -> (targetDate: Date?, targetDescription: String) {
        return await Task.detached {
            let key = "course_metadata_\(courseID.uuidString)"
            guard let data = UserDefaults.standard.data(forKey: key) else {
                return (nil, "")
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let courseData = try decoder.decode(Course.self, from: data)
                return (courseData.targetDate, courseData.targetDescription)
            } catch {
                print("📅 [ERROR] Failed to load course metadata: \(error.localizedDescription)")
                return (nil, "")
            }
        }.value
    }
}
