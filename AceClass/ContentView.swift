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

// 1. 簡化 CourseRowView，移除點擊事件處理，完全由 List 的 selection 控制
struct CourseRowView: View {
    let course: Course

    var body: some View {
        HStack {
            Image(systemName: "book")
                .foregroundColor(.accentColor)
            Text(course.folderURL.lastPathComponent)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
    }
}

// 1. 簡化 VideoRowView，移除播放器，只負責顯示資訊和高亮
struct VideoRowView: View {
    @Binding var video: VideoItem
    let isPlaying: Bool
    let playAction: () -> Void
    let saveAction: () -> Void

    // 1. 新增日期格式化工具
    private var formattedDate: String {
        guard let date = video.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { // 增加垂直間距
            // 1. 將註解欄位移到最上方，並使用較大的字體
            HStack(alignment: .firstTextBaseline) {
                TextField("輸入註解...", text: $video.note)
                    .font(.headline) // 使用 headline 字體
                    .textFieldStyle(.plain)
                    .onChange(of: video.note) { _, _ in saveAction() }

                Spacer()

                // 播放按鈕保持在右上角
                Button(action: playAction) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            // 2. 將顯示名稱移到下方，並使用較小的字體
            HStack(alignment: .firstTextBaseline) {
                TextField("顯示名稱", text: $video.displayName)
                    .font(.body) // 使用 body 字體
                    .textFieldStyle(.plain)
                    .onChange(of: video.displayName) { _, _ in saveAction() }

                // 日期跟隨顯示名稱
                if !formattedDate.isEmpty {
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }

                Spacer()

                // 已看/未看按鈕保持在右下角
                Button(action: {
                    video.watched.toggle()
                    saveAction()
                }) {
                    Image(systemName: video.watched ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(video.watched ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(isPlaying ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .padding(.vertical, 2)
    }
}

// 1. 新增一個結構來存放課程的統計數據
struct CourseStats {
    let totalVideos: Int
    let watchedVideos: Int
    var unwatchedVideos: Int { totalVideos - watchedVideos }
    var progress: Double {
        totalVideos > 0 ? Double(watchedVideos) / Double(totalVideos) : 0
    }
}

// 2. 將統計數據部分抽離成獨立的 View
struct StatisticsRowsView: View {
    let stats: CourseStats

    var body: some View {
        HStack {
            Label("總影片數", systemImage: "film.stack")
            Spacer()
            Text("\(stats.totalVideos)")
        }
        .font(.title2)

        HStack {
            Label("已觀看", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
            Spacer()
            Text("\(stats.watchedVideos)")
        }
        .font(.title2)

        HStack {
            Label("未觀看", systemImage: "circle")
                .foregroundColor(.orange)
            Spacer()
            Text("\(stats.unwatchedVideos)")
        }
        .font(.title2)
    }
}

// 2. 將進度條部分抽離成獨立的 View
struct ProgressSectionView: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading) {
            Text("觀看進度")
                .font(.headline)
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.vertical, 5)
            Text(String(format: "%.1f%%", progress * 100))
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// 1. 修正：重新引入 UnwatchedVideoRowView 以簡化結構並解決潛在的編譯問題。
struct UnwatchedVideoRowView: View {
    let video: VideoItem

    var body: some View {
        HStack {
            Image(systemName: "video")
                .foregroundColor(.secondary)
            Text(video.note)
                .truncationMode(.tail)
                .help(video.fileName) // 使用 .help 替代 .tooltip
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// 3. 將未觀看影片列表抽離成獨立的 View
struct UnwatchedVideosListView: View {
    let unwatchedVideos: [VideoItem]

    var body: some View {
        if !unwatchedVideos.isEmpty {
            Divider()
                .padding(.vertical, 10)

            Text("待觀看影片")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // 2. 使用新建立的 UnwatchedVideoRowView
                    ForEach(unwatchedVideos) { video in
                        UnwatchedVideoRowView(video: video)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
}

// 2. 新增一個專門顯示統計數據的 View
struct CourseStatisticsView: View {
    let stats: CourseStats
    let courseName: String
    // 1. 新增屬性以接收未觀看影片的列表
    let unwatchedVideos: [VideoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(courseName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 10)

            // 4. 使用抽離出來的 View
            StatisticsRowsView(stats: stats)

            Divider()
                .padding(.vertical, 10)

            // 4. 使用抽離出來的 View
            ProgressSectionView(progress: stats.progress)

            // 4. 使用抽離出來的 View
            UnwatchedVideosListView(unwatchedVideos: unwatchedVideos)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
        .foregroundColor(.white)
        .cornerRadius(12)
        .padding()
    }
}

struct ContentView: View {
    @State private var sourceFolderURL: URL?
    // 2. 使用 @StateObject 替代 @State
    @StateObject private var courseManager = CourseManager()
    @State private var showFolderPicker = false
    // 將 selectedCourse 改為 selectedCourseID
    @State private var selectedCourseID: UUID? = nil
    @State private var playingVideoIndex: Int? = nil
    // 1. 將 AVPlayer 移至 ContentView 管理
    @State private var player: AVPlayer?
    // 1. 新增狀態變數以控制影片播放器的全螢幕
    @State private var isVideoPlayerFullScreen = false
    
    // 用於儲存 Security-Scoped Bookmark 資料的 UserDefaults Key
    private let bookmarkKey = "selectedFolderBookmark"
    private var cancellables = Set<AnyCancellable>()
    
    // 1. 新增狀態變數以顯示權限提示
    @State private var showFullDiskAccessAlert = false
    
    // 4. 新增權限相關的輔助函式
    private func hasFullDiskAccess() -> Bool {
        // 透過嘗試存取一個通常需要權限的目錄來檢查
        // 這是一個啟發式方法，並非絕對準確，但常用於此目的
        // 改用 Application Support 目錄，因為 Safari 目錄在某些系統版本不存在
        let testPath = "~/Library/Application Support".expandingTildeInPath
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: testPath)
            print("完整磁碟取用權限：已取得")
            return true
        } catch {
            print("完整磁碟取用權限檢查失敗: \(error.localizedDescription)")
            return false
        }
    }

    var body: some View {
        // 2. 使用 ZStack 來疊加全螟幕播放器
        ZStack {
            // 使用 NavigationSplitView 替代 NavigationView 以建立更穩定的三欄式佈局
            NavigationSplitView {
                // 側邊欄
                courseSidebar
            } content: {
                // 中間影片列表
                videoList
            } detail: {
                // 右側影片播放器
                videoPlayerArea
            }
            .navigationTitle("補課影片管理系統")
            // 1. 根據 isVideoPlayerFullScreen 狀態動態隱藏工具列（包含標題列）
            .toolbar(isVideoPlayerFullScreen ? .hidden : .visible, for: .windowToolbar)
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let folder = urls.first {
                        // 先取得安全作用域存取權限
                        let granted = folder.startAccessingSecurityScopedResource()
                        print("fileImporter: startAccessingSecurityScopedResource: \(granted)")
                        
                        // 確保無論如何都會在函數結束時停止訪問
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
                                
                                sourceFolderURL = folder
                                print("來源資料夾已選擇: \(folder.path)")
                                
                                // 由於我們已經釋放了原始 URL 的安全作用域，我們需要通過 loadBookmark 重新獲取
                                // 而不是直接使用 folder
                                DispatchQueue.main.async {
                                    self.loadBookmark()
                                }
                                
                                selectedCourseID = nil
                                playingVideoIndex = nil
                            } catch {
                                print("儲存資料夾書籤失敗: \(error.localizedDescription)")
                            }
                        } else {
                            print("無法取得資料夾安全作用域存取權限")
                        }
                    }
                case .failure(let error):
                    print("選擇資料夾失敗: \(error.localizedDescription)")
                    break
                }
            }
            .onAppear {
                // 修正：應用程式啟動時直接嘗試載入書籤。
                // 如果書籤指向受保護的目錄（如下載、文件），系統會自動跳出權限請求視窗，
                // 這正是使用者期望的行為。
                loadBookmark()

                // 我們仍然可以保留完整磁碟權限的檢查，作為一個輔助的提示。
                // 延遲執行以避免與系統權限視窗衝突。
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // 只有在書籤載入失敗，且我們猜測原因是權限不足時，才顯示我們自訂的提示。
                    if self.sourceFolderURL == nil && !self.hasFullDiskAccess() {
                        self.showFullDiskAccessAlert = true
                    }
                }
            }
            .onDisappear {
                // 應用程式關閉時停止安全作用域存取
                if let url = sourceFolderURL {
                    // 注意：這裡只在應用程式退出時才停止存取
                    // 為了避免閃退，添加額外的檢查
                    do {
                        // 確認這個 URL 是否仍然有效
                        let _ = try url.checkResourceIsReachable()
                        url.stopAccessingSecurityScopedResource()
                        print("onDisappear: 已停止主資料夾安全作用域存取權限")
                    } catch {
                        print("onDisappear: URL已不可訪問，跳過停止安全作用域存取: \(error.localizedDescription)")
                    }
                }
            }
            // 2. 監聽播放影片的變化
            .onChange(of: playingVideoIndex) { _, newIndex in
                setupPlayer(for: newIndex)
            }
            // 2. 監聽課程選擇的變化
            .onChange(of: selectedCourseID) { _, newCourseID in
                // 修正：先重置播放狀態，再載入影片，避免索引越界
                playingVideoIndex = nil
                if let newCourse = courseManager.courses.first(where: { $0.id == newCourseID }) {
                    print("課程選擇已變更: \(newCourse.folderURL.lastPathComponent)")
                    // 將 loadVideos 放入主線程，確保 UI 更新正常
                    DispatchQueue.main.async {
                        self.loadVideos(for: newCourse)
                    }
                }
            }
            // 3. 新增提示視窗
            .alert("需要完整磁碟取用權限", isPresented: $showFullDiskAccessAlert) {
                Button("前往設定") {
                    openPrivacySettings()
                }
                Button("稍後再說", role: .cancel) { }
            } message: {
                Text("為了讓您能選擇任意資料夾作為課程來源，本應用程式需要「完整磁碟取用權限」。\n\n請至「系統設定 > 隱私權與安全性 > 完整磁碟取用權限」中，將 AceClass 加入並啟用。")
            }
            // .opacity(isVideoPlayerFullScreen ? 0 : 1) // 2. 移除舊的 opacity 方法，改用 toolbar 控制
            
            // 3. 如果 isVideoPlayerFullScreen 為 true，則顯示全螢幕播放器
            if isVideoPlayerFullScreen, let player = player {
                fullScreenVideoPlayerView(player: player)
            }
        }
    }
    
    // 將側邊欄課程列表抽離成獨立的 computed property
    private var courseSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 上方選擇資料夾區域塊
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
            .padding(.horizontal)
            Divider()
            // 下方課程列表
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
                    // 側邊欄 List 綁定 selectedCourseID
                    List(selection: $selectedCourseID) {
                        ForEach(courseManager.courses) { course in
                            // 3. 移除 selectAction，讓 List selection 自動處理
                            CourseRowView(course: course)
                                .tag(course.id) // 確保 selection 能正確運作
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .padding(.horizontal)
            Spacer()
        }
    }
    
    // 3. 建立中間影片列表的 View
    private var videoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let idx = selectedCourseIndex {
                let course = courseManager.courses[idx]
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
                        // 修正：直接使用 $courseManager.courses[idx].videos 進行綁定，這是更現代、更直接的 SwiftUI 寫法
                        ForEach($courseManager.courses[idx].videos) { $video in
                            VideoRowView(
                                video: $video,
                                isPlaying: playingVideoIndex == course.videos.firstIndex(where: { $0.id == video.id }),
                                playAction: {
                                    let videoIdx = course.videos.firstIndex(where: { $0.id == video.id })
                                    playingVideoIndex = (playingVideoIndex == videoIdx) ? nil : videoIdx
                                },
                                saveAction: { saveVideos(for: course.id) }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                Spacer()
                Text("請點選左側課程以瀏覽影片")
                    .foregroundColor(.secondary)
                    .padding()
                Spacer()
            }
        }
    }
    
    // 4. 建立右側影片播放器的 View
    private var videoPlayerArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 修正：新增邊界檢查，確保 videoIndex 在 videos 陣列的有效範圍內
            if let courseIndex = selectedCourseIndex,
               let videoIndex = playingVideoIndex,
               courseIndex < courseManager.courses.count, // 確保課程索引有效
               videoIndex < courseManager.courses[courseIndex].videos.count, // 確保影片索引有效
               let player = player {

                let video = courseManager.courses[courseIndex].videos[videoIndex]

                // 5. 在標題旁新增全螢幕按鈕
                HStack {
                    Text(video.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        isVideoPlayerFullScreen = true
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top)

                VideoPlayer(player: player)
                    .padding(.horizontal)
                    .padding(.bottom)

            } else if let stats = courseStatistics, let courseIndex = selectedCourseIndex {
                // 3. 如果沒有影片播放，但有選定課程，則顯示統計數據
                let courseName = courseManager.courses[courseIndex].folderURL.lastPathComponent
                CourseStatisticsView(stats: stats, courseName: courseName, unwatchedVideos: unwatchedVideosForSelectedCourse)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("點擊影片播放按鈕以開始播放")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
    
    // 4. 新增全螢幕播放器 View
    @ViewBuilder
    private func fullScreenVideoPlayerView(player: AVPlayer) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.edgesIgnoringSafeArea(.all)

            VideoPlayer(player: player)
                .edgesIgnoringSafeArea(.all)

            Button(action: {
                isVideoPlayerFullScreen = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            }
            .buttonStyle(.plain)
        }
        .zIndex(1) // 確保它在最上層
    }
    
    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func loadBookmark() {
        // 應用程式啟動時嘗試載入之前選擇的資料夾
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                // 檢查書籤是否過期並更新
                if isStale {
                    print("書籤資料已過期，嘗試重新儲存。")
                    do {
                        let newBookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                        UserDefaults.standard.set(newBookmarkData, forKey: bookmarkKey)
                        print("成功更新過期的書籤資料。")
                    } catch {
                        print("更新過期書籤資料失敗: \(error.localizedDescription)")
                        // 即使更新書籤失敗，我們仍然嘗試使用原始的 URL，因為它可能仍然有效
                    }
                }
                
                // 啟動安全作用域存取
                let granted = url.startAccessingSecurityScopedResource()
                if granted {
                    print("loadBookmark: 成功取得主資料夾安全作用域存取權限")
                    sourceFolderURL = url
                    print("loadBookmark: 從書籤載入來源資料夾: \(url.path)")
                    
                    // 使用 DispatchQueue.main.async 確保在主線程載入課程
                    DispatchQueue.main.async {
                        self.loadCourses(from: url)
                    }
                    
                    // 注意：這裡不釋放安全作用域資源，因為我們需要持續訪問
                    // stopAccessingSecurityScopedResource 將在 onDisappear 或各個子函數的 defer 中調用
                } else {
                    print("loadBookmark: 未能取得主資料夾安全作用域存取權限！")
                    // 嘗試使用完整磁碟存取權限的替代方案
                    if self.hasFullDiskAccess() {
                        print("loadBookmark: 嘗試使用完整磁碟權限繼續操作")
                        sourceFolderURL = url
                        DispatchQueue.main.async {
                            self.loadCourses(from: url)
                        }
                    } else {
                        // 如果沒有足夠的權限，顯示提示
                        self.showFullDiskAccessAlert = true
                    }
                }
            } catch {
                print("loadBookmark: 載入資料夾書籤失敗: \(error.localizedDescription)")
                self.showFullDiskAccessAlert = true
            }
        }
    }

    // 4. 新增計算屬性來取得目前課程的統計數據
    var courseStatistics: CourseStats? {
        guard let courseIndex = selectedCourseIndex, courseIndex < courseManager.courses.count else { return nil }
        let course = courseManager.courses[courseIndex]
        let watchedCount = course.videos.filter { $0.watched }.count
        return CourseStats(totalVideos: course.videos.count, watchedVideos: watchedCount)
    }

    // 5. 新增計算屬性以取得未觀看的影片列表
    var unwatchedVideosForSelectedCourse: [VideoItem] {
        guard let courseIndex = selectedCourseIndex, courseIndex < courseManager.courses.count else { return [] }
        return courseManager.courses[courseIndex].videos.filter { !$0.watched }
    }

    // 取得目前選取課程的 index
    var selectedCourseIndex: Int? {
        guard let id = selectedCourseID else { return nil }
        // 3. 從 courseManager 取得 courses
        return courseManager.courses.firstIndex(where: { $0.id == id })
    }
    
    // 5. 設定播放器並監聽播放完成事件
    private func setupPlayer(for newIndex: Int?) {
        // 清除舊的播放結束通知監聽
        if let playerItem = player?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        }

        guard let courseIndex = selectedCourseIndex,
              let videoIndex = newIndex,
              let url = videoURL(for: courseManager.courses[courseIndex], idx: videoIndex) else {
            player?.pause()
            player = nil
            return
        }
        
        let playerItem = AVPlayerItem(url: url)
        // 監聽播放結束事件
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [self] _ in
            print("影片播放完畢。")
            // 播放完畢後，自動標示為已觀看
            if let courseIdx = self.selectedCourseIndex, let videoIdx = self.playingVideoIndex {
                self.courseManager.courses[courseIdx].videos[videoIdx].watched = true
                // 修正：傳遞 course ID 而不是 course 物件
                self.saveVideos(for: self.courseManager.courses[courseIdx].id)
                print("已將 \(self.courseManager.courses[courseIdx].videos[videoIdx].displayName) 標示為已觀看並儲存。")
            }
            // 清除播放狀態
            self.playingVideoIndex = nil
        }

        if let player = player {
            player.replaceCurrentItem(with: playerItem)
        } else {
            player = AVPlayer(playerItem: playerItem)
        }
        player?.play()
    }

    func loadCourses(from folder: URL) {
        print("--- 載入課程開始 for: \(folder.lastPathComponent) ---")
        
        // 在載入課程時獲取安全作用域存取權限
        // 注意：如果 folder 已經是在安全作用域內，這不會有重複啟動的問題
        let granted = folder.startAccessingSecurityScopedResource()
        
        // 確保無論成功或失敗，都會釋放安全作用域資源
        defer {
            if granted {
                folder.stopAccessingSecurityScopedResource()
                print("loadCourses: 釋放資料夾安全作用域存取權限: \(folder.lastPathComponent)")
            }
        }

        let fileManager = FileManager.default
        do {
            // 確認目錄是否存在且可訪問
            var isDir: ObjCBool = false
            if !fileManager.fileExists(atPath: folder.path, isDirectory: &isDir) || !isDir.boolValue {
                print("錯誤：指定的路徑不存在或不是目錄: \(folder.path)")
                return
            }
            
            let courseFolders = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

            // 更新 courseManager.courses
            self.courseManager.courses = courseFolders.map { Course(folderURL: $0, videos: []) }
            print("找到 \(self.courseManager.courses.count) 個課程資料夾。")
            
            if self.courseManager.courses.isEmpty {
                print("警告：未找到任何課程資料夾。請確認選擇的目錄結構是否正確。")
            } else {
                // 列印找到的課程名稱，幫助診斷
                for (index, course) in self.courseManager.courses.enumerated() {
                    print("課程 \(index + 1): \(course.folderURL.lastPathComponent)")
                }
            }
        } catch {
            print("無法讀取資料夾內容: \(error.localizedDescription)")
            
            // 嘗試取得更詳細的錯誤信息
            if let nsError = error as NSError? {
                print("錯誤域: \(nsError.domain), 代碼: \(nsError.code), 描述: \(nsError.localizedDescription)")
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    print("底層錯誤: \(underlyingError.localizedDescription)")
                }
            }
        }
        
        print("--- 載入課程結束 ---")
    }
    func loadVideos(for course: Course) {
        print("\n--- 載入影片開始 for: \(course.folderURL.lastPathComponent) ---")
        // 修正：在訪問資料夾內容時獲取安全作用域存取權限
        let granted = course.folderURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                course.folderURL.stopAccessingSecurityScopedResource()
                print("loadVideos: 釋放資料夾安全作用域存取權限: \(course.folderURL.lastPathComponent)")
            }
        }
        
        let fileManager = FileManager.default
        let jsonURL = course.jsonFileURL
        
        // 1. 掃描資料夾內所有 mp4 檔案
        var scannedMp4Files: [URL] = []
        do {
            let files = try fileManager.contentsOfDirectory(at: course.folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            scannedMp4Files = files.filter { $0.pathExtension.lowercased() == "mp4" }
            print("掃描到的 MP4 檔案數量: \(scannedMp4Files.count)")
            for file in scannedMp4Files {
                print("- \(file.lastPathComponent)")
            }
        } catch {
            print("掃描 MP4 檔案失敗: \(error.localizedDescription)")
            do {
                let debugFiles = try fileManager.contentsOfDirectory(atPath: course.folderURL.path)
                print("該資料夾實際內容: \(debugFiles)")
            } catch {
                print("無法取得該資料夾內容: \(error.localizedDescription)")
            }
        }
        
        // 2. 嘗試讀取已儲存的 JSON 資料
        var savedVideos: [VideoItem] = []
        if let data = try? Data(contentsOf: jsonURL) {
            print("嘗試從 JSON 讀取資料: \(jsonURL.lastPathComponent)")
            if let decodedVideos = try? JSONDecoder().decode([VideoItem].self, from: data) {
                savedVideos = decodedVideos
                print("從 JSON 讀取到 \(savedVideos.count) 條影片資料。")
            } else {
                print("JSON 解碼失敗或資料格式錯誤。");
            }
        } else {
            print("未找到 JSON 檔案: \(jsonURL.lastPathComponent)");
        }
        
        // 3. 合併掃描到的影片與已儲存的資料
        var updatedVideos: [VideoItem] = []
        for mp4URL in scannedMp4Files {
            if let existingVideoIndex = savedVideos.firstIndex(where: { $0.fileName == mp4URL.lastPathComponent }) {
                // 如果已存在，使用舊資料
                updatedVideos.append(savedVideos[existingVideoIndex])
            } else {
                // 如果是新的，建立新資料
                print("新增影片: \(mp4URL.lastPathComponent) - 建立新資料")
                updatedVideos.append(VideoItem(fileName: mp4URL.lastPathComponent))
            }
        }
        
        // 排序影片：有日期的排在前面，並按日期從新到舊排序；沒有日期的排在後面
        updatedVideos.sort { (video1, video2) -> Bool in
            guard let date1 = video1.date else { return false } // video1 沒有日期，排在後面
            guard let date2 = video2.date else { return true }  // video2 沒有日期，排在前面
            return date1 > date2 // 日期從新到舊排序
        }
        
        // 更新 courses 陣列與 selectedCourse
        // 5. 直接修改 courseManager 中的資料來觸發更新
        if let idx = courseManager.courses.firstIndex(where: { $0.id == course.id }) {
            courseManager.courses[idx].videos = updatedVideos
            print("已更新課程陣列中索引 \(idx) 的影片列表，共 \(updatedVideos.count) 條影片。")
        } else {
            print("錯誤：在課程陣列中找不到 ID 為 \(course.id) 的課程。")
        }
        
        // 4. 立即儲存更新後的影片資料到 JSON
        saveVideos(for: course.id)
        print("已儲存影片資料到 JSON。\n--- 載入影片結束 ---")
    }
    func saveVideos(for courseID: UUID) {
        // 修正：改為接收 courseID，並從 courseManager 中取得最新的 course 物件
        guard let course = courseManager.courses.first(where: { $0.id == courseID }) else {
            print("儲存失敗：找不到 ID 為 \(courseID) 的課程。")
            return
        }
        let videos = course.videos
        let jsonURL = course.jsonFileURL
        
        // 修正：在寫入 JSON 時獲取安全作用域存取權限
        let granted = course.folderURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                course.folderURL.stopAccessingSecurityScopedResource()
                print("saveVideos: 釋放資料夾安全作用域存取權限: \(course.folderURL.lastPathComponent)")
            }
        }

        if let data = try? JSONEncoder().encode(videos) {
            do {
                try data.write(to: jsonURL)
                print("成功寫入 JSON 檔案: \(jsonURL.lastPathComponent)")
            } catch {
                print("寫入 JSON 檔案失敗: \(error.localizedDescription)")
            }
        } else {
            print("JSON 編碼失敗。")
        }
    }

    // 說明：以下輔助函式已不再需要，因為我們在 ForEach 中使用了更直接的綁定方式 (`$video`)。
    // 為了保持程式碼整潔，將它們移除。

    // 取得影片檔案 URL
    func videoURL(for course: Course, idx: Int) -> URL? {
        guard idx >= 0 && idx < course.videos.count else { return nil }
        let video = course.videos[idx]
        return course.folderURL.appendingPathComponent(video.fileName)
    }
}

// 5. 新增 String 的擴充以方便處理路徑
extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}

#Preview {
    ContentView()
}
