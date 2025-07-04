//
//  ContentView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI
import AVKit
import AppKit // 引入 AppKit 以使用 Security-Scoped Bookmarks 相關功能
import Combine

// 1. 建立一個 ObservableObject 來管理課程資料
class CourseManager: ObservableObject {
    @Published var courses: [Course] = []
}

// MARK: - ContentView
struct ContentView: View {
    @State private var sourceFolderURL: URL?
    @StateObject private var courseManager = CourseManager()
    @State private var showFolderPicker = false
    @State private var selectedCourseID: UUID? = nil
    @State private var playingVideoIndex: Int? = nil
    @State private var player: AVPlayer?
    @State private var isVideoPlayerFullScreen = false
    
    private let bookmarkKey = "selectedFolderBookmark"
    @State private var showFullDiskAccessAlert = false

    // MARK: Body
    var body: some View {
        ZStack {
            NavigationSplitView {
                courseSidebar
            } content: {
                videoList
            } detail: {
                videoPlayerArea
            }
            .navigationTitle("補課影片管理系統")
            .toolbar(isVideoPlayerFullScreen ? .hidden : .visible, for: .windowToolbar)
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                handleFolderSelection(result)
            }
            .onAppear(perform: setupOnAppear)
            .onDisappear(perform: stopAccessingResources)
            // 修正：更新 onChange 以符合 macOS 14+ 的語法
            .onChange(of: playingVideoIndex) { _, newIndex in
                setupPlayerForIndex(newIndex)
            }
            .onChange(of: selectedCourseID) { _, newCourseID in
                handleCourseSelectionChange(newCourseID)
            }
            .alert("需要完整磁碟取用權限", isPresented: $showFullDiskAccessAlert, actions: fullDiskAccessAlertButtons, message: fullDiskAccessAlertMessage)
            
            if isVideoPlayerFullScreen, let player = player {
                FullScreenVideoPlayerView(player: player, onToggleFullScreen: toggleFullScreen)
            }
        }
    }
    
    // MARK: - UI Components
    
    private var courseSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderSelectionArea
                .padding(.horizontal)
            Divider()
            courseListArea
                .padding(.horizontal)
            Spacer()
        }
    }
    
    private var folderSelectionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("來源資料夾")
                .font(.headline)
                .padding(.top, 16)
            Button(action: { showFolderPicker = true }) {
                HStack {
                    Image(systemName: "folder")
                    Text("選擇資料夾")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 4)
            if let url = sourceFolderURL {
                Text(url.path)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.bottom, 4)
            }
        }
    }
    
    private var courseListArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("課程列表")
                .font(.title3)
                .bold()
                .padding(.vertical, 8)
            if courseManager.courses.isEmpty {
                Spacer()
                Text("請先選擇來源資料夾")
                    .foregroundColor(.secondary)
                    .padding()
                Spacer()
            } else {
                List(selection: $selectedCourseID) {
                    ForEach(courseManager.courses) { course in
                        CourseRowView(course: course)
                            .tag(course.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
    
    private var videoList: some View {
        Group {
            if let idx = selectedCourseIndex {
                let course = courseManager.courses[idx]
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("課程：")
                            .font(.title3)
                            .bold()
                        Text(course.folderURL.lastPathComponent)
                            .font(.title3)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    Divider()
                    
                    if course.videos.isEmpty {
                        Spacer()
                        Text("此課程尚無 mp4 影片")
                            .foregroundColor(.secondary)
                            .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach($courseManager.courses[idx].videos) { $video in
                                VideoRowView(
                                    video: $video,
                                    isPlaying: playingVideoIndex == course.videos.firstIndex(where: { $0.id == video.id }),
                                    playAction: {
                                        playVideo(video, in: course)
                                    },
                                    saveAction: { saveVideos(for: course.id) }
                                )
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            } else {
                Spacer()
                Text("請點選左側課程以瀏覽影片")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
    
    private var videoPlayerArea: some View {
        Group {
            // 修正：增加索引有效性檢查，防止在影片列表更新時崩潰
            if let player = player, 
               let course = selectedCourse, 
               let index = playingVideoIndex, 
               course.videos.indices.contains(index) {
                
                let video = course.videos[index]
                VStack(spacing: 0) {
                    // 影片標題區
                    Text(video.note)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)

                    // 播放器區
                    VideoPlayerView(player: player, onToggleFullScreen: toggleFullScreen)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 5, y: 3)
                .padding(20)

            } else if let course = selectedCourse {
                let stats = calculateCourseStats(for: course)
                let unwatched = course.videos.filter { !$0.watched }
                CourseStatisticsView(
                    stats: stats,
                    courseName: course.folderURL.lastPathComponent,
                    unwatchedVideos: unwatched,
                    playUnwatchedVideoAction: { video in
                        playVideo(video, in: course)
                    }
                )
            } else {
                VStack {
                    Image(systemName: "film.stack")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("歡迎使用補課影片管理系統")
                        .font(.title)
                        .padding(.top)
                    Text("請從左側選擇課程資料夾與課程")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func fullDiskAccessAlertButtons() -> some View {
        Button("前往設定") {
            openPrivacySettings()
        }
        Button("稍後再說", role: .cancel) { }
    }
    
    private func fullDiskAccessAlertMessage() -> some View {
        Text("為了讓您能選擇任意資料夾作為課程來源，本應用程式需要「完整磁碟取用權限」。\n\n請至「系統設定 > 隱私權與安全性 > 完整磁碟取用權限」中，將 AceClass 加入並啟用。")
    }

    // MARK: - Computed Properties
    
    private var selectedCourseIndex: Int? {
        courseManager.courses.firstIndex(where: { $0.id == selectedCourseID })
    }
    
    private var selectedCourse: Course? {
        guard let id = selectedCourseID else { return nil }
        return courseManager.courses.first(where: { $0.id == id })
    }
    
    // MARK: - Methods & Logic
    
    private func setupOnAppear() {
        loadBookmark()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.sourceFolderURL == nil && !self.hasFullDiskAccess() {
                self.showFullDiskAccessAlert = true
            }
        }
    }
    
    private func stopAccessingResources() {
        if let url = sourceFolderURL {
            url.stopAccessingSecurityScopedResource()
            print("onDisappear: 已停止主資料夾安全作用域存取權限")
        }
    }
    
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            let granted = folder.startAccessingSecurityScopedResource()
            print("fileImporter: startAccessingSecurityScopedResource: \(granted)")
            
            defer {
                if granted {
                    folder.stopAccessingSecurityScopedResource()
                    print("fileImporter: 已釋放安全作用域資源")
                }
            }
            
            if granted {
                do {
                    let bookmarkData = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
                    print("已儲存資料夾書籤資料。")
                    
                    DispatchQueue.main.async {
                        self.loadBookmark()
                        self.selectedCourseID = nil
                        self.playingVideoIndex = nil
                        self.player = nil
                    }
                } catch {
                    print("儲存資料夾書籤失敗: \(error.localizedDescription)")
                }
            } else {
                print("無法取得資料夾安全作用域存取權限")
            }
        case .failure(let error):
            print("選擇資料夾失敗: \(error.localizedDescription)")
        }
    }
    
    private func handleCourseSelectionChange(_ newCourseID: UUID?) {
        playingVideoIndex = nil
        player = nil
        if let newCourse = courseManager.courses.first(where: { $0.id == newCourseID }) {
            print("課程選擇已變更: \(newCourse.folderURL.lastPathComponent)")
            DispatchQueue.main.async {
                self.loadVideos(for: newCourse)
            }
        }
    }
    
    private func setupPlayerForIndex(_ newIndex: Int?) {
        setupPlayer(for: newIndex)
    }
    
    private func playVideo(_ video: VideoItem, in course: Course) {
        let videoIdx = course.videos.firstIndex(where: { $0.id == video.id })
        playingVideoIndex = (playingVideoIndex == videoIdx) ? nil : videoIdx
    }

    private func toggleFullScreen() {
        withAnimation {
            isVideoPlayerFullScreen.toggle()
        }
    }
    
    private func calculateCourseStats(for course: Course) -> CourseStats {
        let total = course.videos.count
        let watched = course.videos.filter { $0.watched }.count
        return CourseStats(totalVideos: total, watchedVideos: watched)
    }

    // MARK: - Data Handling & Permissions
    
    private func hasFullDiskAccess() -> Bool {
        // 修正：將 String 轉換為 NSString 以使用 expandingTildeInPath
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
    
    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess") {
            NSWorkspace.shared.open(url)
        }
    }

    func loadBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            print("找不到書籤資料。")
            return
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("書籤已過期，正在嘗試刷新...")
                // 如果書籤過期，需要重新讓使用者選擇資料夾以生成新的書籤
                showFolderPicker = true
                return
            }
            
            if url.startAccessingSecurityScopedResource() {
                print("成功透過書籤取得安全作用域存取權限: \(url.path)")
                self.sourceFolderURL = url
                self.loadCourses(from: url)
                // 注意：在這裡不再呼叫 stopAccessingSecurityScopedResource()，
                // 權限將在 onDisappear 中釋放。
            } else {
                print("無法透過書籤取得安全作用域存取權限。")
                // 可能需要提示使用者重新選擇資料夾
                self.showFullDiskAccessAlert = true
            }
        } catch {
            print("解析書籤失敗: \(error.localizedDescription)")
            // 書籤解析失敗，可能需要使用者重新選擇
            self.showFolderPicker = true
        }
    }

    func loadCourses(from sourceURL: URL) {
        // 修正：不再需要重複請求權限，因為父資料夾的權限已經在 loadBookmark 中取得並保持
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            let courseFolders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            
            DispatchQueue.main.async {
                // 修正：初始化 Course 時提供空的 videos 陣列
                self.courseManager.courses = courseFolders.map { Course(folderURL: $0, videos: []) }
                print("已載入 \(self.courseManager.courses.count) 個課程。")
            }
        } catch {
            print("讀取課程資料夾失敗: \(error.localizedDescription)")
            // 如果在這裡失敗，很可能是主資料夾的權限問題
            DispatchQueue.main.async {
                self.showFullDiskAccessAlert = true
            }
        }
    }

    func loadVideos(for course: Course) {
        // 修正：不再需要重複請求權限
        guard let courseIndex = courseManager.courses.firstIndex(where: { $0.id == course.id }) else { return }
        
        // 從 JSON 檔案讀取影片資料
        let jsonURL = course.folderURL.appendingPathComponent("videos.json")
        var loadedVideos: [VideoItem] = []
        if let data = try? Data(contentsOf: jsonURL) {
            if let decodedVideos = try? JSONDecoder().decode([VideoItem].self, from: data) {
                loadedVideos = decodedVideos
            }
        }
        
        // 掃描資料夾中的 MP4 檔案
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: course.folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let videoFiles = contents.filter { $0.pathExtension.lowercased() == "mp4" }
            
            var updatedVideos: [VideoItem] = []
            for fileURL in videoFiles {
                // 修正：使用 fileName 進行比對
                if let existingVideo = loadedVideos.first(where: { $0.fileName == fileURL.lastPathComponent }) {
                    updatedVideos.append(existingVideo)
                } else {
                    // 修正：使用正確的初始化方法
                    updatedVideos.append(VideoItem(fileName: fileURL.lastPathComponent))
                }
            }
            
            // 根據日期排序
            updatedVideos.sort {
                guard let date1 = $0.date, let date2 = $1.date else {
                    return $0.fileName < $1.fileName
                }
                return date1 < date2
            }
            
            DispatchQueue.main.async {
                self.courseManager.courses[courseIndex].videos = updatedVideos
                print("為課程 \(course.folderURL.lastPathComponent) 載入/更新了 \(updatedVideos.count) 個影片。")
                self.saveVideos(for: course.id)
            }
        } catch {
            print("讀取影片檔案失敗: \(error.localizedDescription)")
            // 在這裡捕獲錯誤並顯示提示
            DispatchQueue.main.async {
                self.showFullDiskAccessAlert = true
            }
        }
    }

    func saveVideos(for courseID: UUID) {
        guard let courseIndex = courseManager.courses.firstIndex(where: { $0.id == courseID }) else { return }
        let course = courseManager.courses[courseIndex]
        
        // 修正：不再需要重複請求權限
        let jsonURL = course.folderURL.appendingPathComponent("videos.json")
        do {
            let data = try JSONEncoder().encode(course.videos)
            try data.write(to: jsonURL)
            print("已將影片資料儲存至 \(jsonURL.path)")
        } catch {
            print("儲存影片資料失敗: \(error.localizedDescription)")
        }
    }

    func setupPlayer(for index: Int?) {
        guard let course = selectedCourse, let videoIndex = index, course.videos.indices.contains(videoIndex) else {
            player = nil
            return
        }
        
        let video = course.videos[videoIndex]
        // 修正：從 course 的 folderURL 組合出完整的影片 URL
        let videoURL = course.folderURL.appendingPathComponent(video.fileName)
        
        // 修正：不再需要重複請求權限，AVPlayer 會利用已有的父資料夾權限
        player = AVPlayer(url: videoURL)
        player?.play()
        
        // 標記為已觀看
        if let courseIndex = selectedCourseIndex,
           let videoItemIndex = courseManager.courses[courseIndex].videos.firstIndex(where: { $0.id == video.id }),
           !courseManager.courses[courseIndex].videos[videoItemIndex].watched {
            
            courseManager.courses[courseIndex].videos[videoItemIndex].watched = true
            saveVideos(for: course.id)
        }
    }
}
