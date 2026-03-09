import SwiftUI
import AVKit
import Combine

@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var courses: [Course] = [] {
        didSet {
            rebuildCourseDerivedData()
            ACLog("courses changed: \(oldValue.count) -> \(courses.count)", level: .debug)
            ACLog("courses changed in @MainActor context", level: .trace)
        }
    }
    @Published var selectedCourseID: UUID? {
        didSet {
            if oldValue != selectedCourseID {
                ACLog("selectedCourseID changed from \(oldValue?.uuidString.prefix(8) ?? "nil") to \(selectedCourseID?.uuidString.prefix(8) ?? "nil")", level: .debug)
                // Schedule the change processing to avoid publishing during view updates.
                // Use asyncAfter to ensure we're completely outside the current update cycle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
                    guard let self = self else { return }
                    Task { @MainActor in
                        ACLog("Processing selectedCourseID change in delayed Task", level: .trace)
                        
                        // When the course changes, stop the current video playback.
                        await self.selectVideo(nil)
                        
                        // Load videos for the newly selected course if it doesn't have videos yet
                        if let course = self.selectedCourse, course.videos.isEmpty {
                            ACLog("Loading videos for course: \(course.folderURL.lastPathComponent)", level: .debug)
                            await self.loadVideos(for: course)
                        }
                    }
                }
            }
        }
    }
    @Published var currentVideo: VideoItem? {
        didSet {
            ACLog("currentVideo changed: \(oldValue?.fileName ?? "nil") -> \(currentVideo?.fileName ?? "nil")", level: .debug)
            ACLog("currentVideo changed in @MainActor context", level: .trace)
        }
    }
    @Published var player: AVPlayer? {
        didSet {
            ACLog("player changed: \(oldValue != nil ? "not nil" : "nil") -> \(player != nil ? "not nil" : "nil")", level: .debug)
            ACLog("player changed in @MainActor context", level: .trace)
        }
    }
    @Published var isVideoPlayerFullScreen = false
    @Published var showCaptions: Bool = false
    @Published var captionsForCurrentVideo: [CaptionSegment] = []
    @Published var captionError: String? = nil
    @Published var captionLoading: Bool = false // NEW: loading state
    @Published var sourceFolderURL: URL?
    @Published var resumeOverlayText: String? // 顯示「從上次位置續播」提示
    @Published var captionsFeatureEnabled: Bool = false // 全域字幕功能開關（暫時停用字幕）
    @Published var isInitializingPlayer: Bool = false // 影片播放器初始化狀態
    @Published var enableVideoCaching: Bool = true // 小於閾值影片先複製到本地快取
    @Published var playerLoadingTitle: String? = nil
    @Published var playerLoadingDetail: String? = nil
    @Published var isLoadingCourses: Bool = false
    @Published var coursesLoadingProgress: String? = nil

    // MARK: - Private Properties
    private let bookmarkKey = "selectedFolderBookmark"
    private var securityScopedURL: URL? // 持有主資料夾的安全作用域存取權
    private var currentlyAccessedVideoURL: URL? // 持有當前播放影片的獨立安全作用域存取權
    private var activeCacheOriginalPath: String? // 正在播放的影片原始路徑，用於快取保護
    private var timeObserverToken: Any? // NEW periodic time observer token
    private let playbackProgressAutoMarkThreshold: Double = 0.75 // 75%
    private let playbackPeriodicUpdateInterval: CMTime = CMTime(seconds: 5, preferredTimescale: 600) // every ~5s
    private var playbackDebounceTask: Task<Void, Never>? // 續播位置寫入 debounce
    private let playbackDebounceInterval: TimeInterval = 12 // 秒
    // Debounce for rapid video selection to avoid churn causing benign cancellation errors
    private var pendingVideoSelectionTask: Task<Void, Never>? = nil
    private let videoSelectionDebounceInterval: TimeInterval = 0.15
    private let videoSelectionDebounceIntervalWhileInitializing: TimeInterval = 0.3
    // Observer for player item failure notifications
    private var playerItemFailedObserver: NSObjectProtocol? = nil
    private var playerItemStatusObserver: NSKeyValueObservation? = nil
    private var playerItemErrorLogObserver: NSObjectProtocol? = nil
    // Diagnostics
    private struct PlayerDiagnostics { var selectionRequests=0; var executedSelections=0; var playerInitSuccess=0; var playerInitFailure=0; var benignCancellations=0; var lastInitDuration: TimeInterval=0; var avgInitDuration: TimeInterval=0 }
    private var diagnostics = PlayerDiagnostics()
    private var loadCoursesTask: Task<Void, Never>? = nil
    private var currentInitStart: Date? = nil
    nonisolated static let supportedVideoExtensions: [String] = [
        "mp4", "mov", "m4v", "mkv",
        "avi", "mpg", "mpeg",
        "mts", "m2ts", "ts",
        "3gp", "3g2"
    ]
    nonisolated private static let supportedVideoExtensionSet = Set(supportedVideoExtensions)
    private struct CourseDerivedData {
        var courseIndexByID: [UUID: Int] = [:]
        var coursesWithTargets: [Course] = []
        var upcomingDeadlines: [Course] = []
        var overdueCourses: [Course] = []
    }
    private var courseDerivedData = CourseDerivedData()

    // MARK: - Computed Properties
    var selectedCourse: Course? {
        guard let index = selectedCourseIndex else { return nil }
        return courses[index]
    }

    var selectedCourseIndex: Int? {
        guard let id = selectedCourseID else { return nil }
        return courseDerivedData.courseIndexByID[id]
    }

    var coursesWithTargets: [Course] {
        courseDerivedData.coursesWithTargets
    }

    var upcomingDeadlines: [Course] {
        courseDerivedData.upcomingDeadlines
    }

    var overdueCourses: [Course] {
        courseDerivedData.overdueCourses
    }

    nonisolated static var supportedVideoFormatsDescription: String {
        supportedVideoExtensions.map { ".\($0)" }.joined(separator: ", ")
    }
    
    // MARK: - Initializer & Deinitializer
    init(loadPersistedBookmark: Bool = true) {
        if loadPersistedBookmark {
            Task {
                await loadBookmark()
            }
        }
    }

    deinit {
        // App 結束時，清理所有安全作用域存取權
    if let obs = playerItemFailedObserver { NotificationCenter.default.removeObserver(obs) }
    playerItemStatusObserver?.invalidate()
        if let url = currentlyAccessedVideoURL {
            url.stopAccessingSecurityScopedResource()
            currentlyAccessedVideoURL = nil
            ACLog("AppState deinit: 已停止影片檔案安全作用域存取", level: .info)
        }
        // Since we can't call actor-isolated methods from deinit, directly stop accessing the resource
        if let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
            ACLog("AppState deinit: 已停止主資料夾安全作用域存取", level: .info)
        }
    }

    private func rebuildCourseDerivedData() {
        courseDerivedData.courseIndexByID = Dictionary(
            uniqueKeysWithValues: courses.enumerated().map { ($1.id, $0) }
        )

        let coursesWithTargets = courses.filter { $0.targetDate != nil }
        courseDerivedData.coursesWithTargets = coursesWithTargets
        courseDerivedData.upcomingDeadlines = coursesWithTargets
            .filter {
                guard let daysRemaining = $0.daysRemaining else { return false }
                return daysRemaining >= 0 && daysRemaining <= 7
            }
            .sorted { ($0.daysRemaining ?? Int.max) < ($1.daysRemaining ?? Int.max) }
        courseDerivedData.overdueCourses = coursesWithTargets
            .filter(\.isOverdue)
            .sorted { abs($0.daysRemaining ?? 0) > abs($1.daysRemaining ?? 0) }
    }

    private func courseIndex(for courseID: UUID) -> Int? {
        courseDerivedData.courseIndexByID[courseID]
    }

    private func normalizedCoursePath(_ folderURL: URL) -> String {
        folderURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    nonisolated static func isSupportedVideoFile(_ url: URL) -> Bool {
        supportedVideoExtensionSet.contains(url.pathExtension.lowercased())
    }

    private func shouldScanCourseRecursively(_ course: Course) -> Bool {
        shouldScanCourseRecursively(folderURL: course.folderURL)
    }

    private func shouldScanCourseRecursively(folderURL: URL, knownCourseFolderPaths: Set<String>? = nil) -> Bool {
        guard let sourceFolderURL else { return true }
        let coursePath = normalizedCoursePath(folderURL)
        let sourcePath = normalizedCoursePath(sourceFolderURL)
        if coursePath != sourcePath {
            return true
        }

        let candidatePaths = knownCourseFolderPaths ?? Set(courses.map { normalizedCoursePath($0.folderURL) })
        return !candidatePaths.contains {
            $0 != sourcePath && $0.hasPrefix(sourcePath + "/")
        }
    }

    private func loadVideoSnapshot(for folderURL: URL, recursive: Bool) async throws -> [VideoItem] {
        try await Task.detached {
            func isSupportedVideo(_ url: URL) -> Bool {
                AppState.isSupportedVideoFile(url)
            }

            func collectVideoFiles(in folderURL: URL, recursive: Bool) throws -> [URL] {
                if recursive {
                    guard let enumerator = FileManager.default.enumerator(
                        at: folderURL,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else {
                        return []
                    }

                    var files: [URL] = []
                    for case let fileURL as URL in enumerator where isSupportedVideo(fileURL) {
                        files.append(fileURL)
                    }
                    return files
                }

                let contents = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                return contents.filter(isSupportedVideo)
            }

            let loadedVideos = LocalMetadataStorage.loadVideos(for: folderURL)

            let videoFiles = try collectVideoFiles(in: folderURL, recursive: recursive)
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            let loadedVideosByPath = Dictionary(uniqueKeysWithValues: loadedVideos.map { ($0.relativePath, $0) })
            let loadedVideosByFileName = Dictionary(uniqueKeysWithValues: loadedVideos.map { ($0.fileName, $0) })

            var updatedVideos: [VideoItem] = []

            for fileURL in videoFiles {
                let fileName = fileURL.lastPathComponent
                let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
                if let existing = loadedVideosByPath[relativePath] {
                    updatedVideos.append(existing)
                } else if let existing = loadedVideosByFileName[fileName] {
                    updatedVideos.append(existing.updatingRelativePath(relativePath))
                } else {
                    updatedVideos.append(VideoItem(fileName: fileName, relativePath: relativePath))
                }
            }

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
    }

    // MARK: - Safe UI Update Methods
    
    /// Safely set selectedCourseID without triggering publishing during view updates
    func selectCourse(_ courseID: UUID?) {
    ACLog("selectCourse called with: \(courseID?.uuidString.prefix(8) ?? "nil")", level: .debug)
        
        // Always defer the change to the next run loop to avoid publishing during view updates
        Task { @MainActor in
            ACLog("Processing selectCourse in Task", level: .trace)
            self.selectedCourseID = courseID
        }
    }

    @MainActor
    private func handlePlaybackPeriodicUpdate(time: CMTime, player: AVPlayer) {
        guard let courseIndex = self.selectedCourseIndex,
              let cv = self.currentVideo,
              let videoIndex = self.courses[courseIndex].videos.firstIndex(where: { $0.id == cv.id }) else { return }
        let currentSeconds = time.seconds
        if currentSeconds.isFinite && currentSeconds >= 0 {
            // Update last playback position in model (threshold 2s)
            if self.courses[courseIndex].videos[videoIndex].lastPlaybackPosition == nil || abs((self.courses[courseIndex].videos[videoIndex].lastPlaybackPosition ?? 0) - currentSeconds) > 2 {
                self.courses[courseIndex].videos[videoIndex].lastPlaybackPosition = currentSeconds
                // Debounce saving position (no immediate disk write)
                self.playbackDebounceTask?.cancel()
                let courseID = self.courses[courseIndex].id
                self.playbackDebounceTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(self?.playbackDebounceInterval ?? 12 * 1_000_000_000))
                        await self?.saveVideos(for: courseID)
                        ACLog("Saved playback position for course=\(courseID.uuidString.prefix(8)) at=\(currentSeconds)s", level: .info)
                    } catch { }
                }
            }
            let duration = player.currentItem?.duration.seconds ?? 0
            if duration > 0, currentSeconds / duration >= self.playbackProgressAutoMarkThreshold {
                if self.courses[courseIndex].videos[videoIndex].watched == false {
                    ACLog("Marking video as watched at progress \(currentSeconds/duration)", level: .info)
                    self.courses[courseIndex].videos[videoIndex].watched = true
                    // Immediate save (override debounce)
                    self.playbackDebounceTask?.cancel(); self.playbackDebounceTask = nil
                    Task { await self.saveVideos(for: self.courses[courseIndex].id) }
                }
            }
        }
    }

    @MainActor
    private func flushPlaybackProgress() {
        self.playbackDebounceTask?.cancel(); self.playbackDebounceTask = nil
        if let courseID = self.selectedCourse?.id {
            Task { await self.saveVideos(for: courseID) }
        }
    }

    // MARK: - Video & Player Logic
    @MainActor
    func selectVideo(_ video: VideoItem?) async {
    ACLog("selectVideo called with: \(video?.fileName ?? "nil")", level: .debug)
    ACLog("selectVideo - Running on @MainActor", level: .trace)

        // If we're trying to select the same video, don't do anything
        if currentVideo?.id == video?.id && video != nil {
            ACLog("selectVideo - Same video already selected, skipping", level: .trace)
            return
        }

    // Cancel any pending scheduled selection (since we are executing one now)
    pendingVideoSelectionTask?.cancel(); pendingVideoSelectionTask = nil
    diagnostics.executedSelections += 1
    currentInitStart = Date()
    isInitializingPlayer = true
        
        // Flush any pending debounce before switching
        flushPlaybackProgress()
        // Cleanup previous observer when switching videos
        if let player = self.player, let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
            ACLog("Removed previous time observer", level: .trace)
        }
    // Remove failure observer from previous item if any
    if let obs = playerItemFailedObserver { NotificationCenter.default.removeObserver(obs); playerItemFailedObserver = nil }
    playerItemStatusObserver?.invalidate(); playerItemStatusObserver = nil
    if let obs = playerItemErrorLogObserver { NotificationCenter.default.removeObserver(obs); playerItemErrorLogObserver = nil }
        
        // 1. Stop accessing the previous video's resources.
            if let previousURL = currentlyAccessedVideoURL {
                previousURL.stopAccessingSecurityScopedResource()
                currentlyAccessedVideoURL = nil
                ACLog("Stopped accessing previous video resource: \(previousURL.path)", level: .trace)
            }
            // Release cache protection for the previous video
            if let prevCachePath = activeCacheOriginalPath {
                VideoCacheManager.shared.markInactive(originalPath: prevCachePath)
                activeCacheOriginalPath = nil
            }

            // 2. If the video is deselected, clear the player and state.
            if video == nil {
                ACLog("Clearing video and player state", level: .debug)
                self.currentVideo = nil
                self.player = nil
                self.captionsForCurrentVideo = []
                self.captionError = nil
                self.playerLoadingTitle = nil
                self.playerLoadingDetail = nil
                isInitializingPlayer = false
                return
            }

            // 3. Set the current video and show a loading state.
            ACLog("Setting currentVideo to: \(video?.fileName ?? "unknown")", level: .debug)
            self.currentVideo = video
            self.player = nil
            self.playerLoadingTitle = L10n.tr("player.loading.preparing")
            self.playerLoadingDetail = video?.fileName

            guard let course = selectedCourse, let videoToPlay = video else { return }
            guard let sourceFolderURL = self.securityScopedURL else {
                ACLog("Cannot play video because the main folder's security scope is missing.", level: .critical)
                self.playerLoadingTitle = L10n.tr("player.loading.unable")
                self.playerLoadingDetail = L10n.tr("player.loading.missing_folder_access")
                diagnostics.playerInitFailure += 1
                finalizeInitDiagnostics(success: false)
                return
            }

            // 4. Start security access and create the player.
            if sourceFolderURL.startAccessingSecurityScopedResource() {
                var fileURL = course.folderURL.appendingPathComponent(videoToPlay.relativePath)
                ACLog("Preparing video URL: \(fileURL.lastPathComponent)", level: .debug)
                self.playerLoadingTitle = L10n.tr("player.loading.checking_source")
                self.playerLoadingDetail = videoToPlay.fileName
                if enableVideoCaching {
                    self.playerLoadingTitle = L10n.tr("player.loading.preparing_file")
                    self.playerLoadingDetail = L10n.tr("player.loading.checking_cache")
                    let originalPath = fileURL.path
                    do {
                        let cached = try await VideoCacheManager.shared.preparePlaybackURL(for: fileURL)
                        if cached != fileURL {
                            ACLog("Using cached local copy for playback: \(cached.lastPathComponent)", level: .info)
                            // Mark this file as actively playing so cache won't evict it
                            VideoCacheManager.shared.markActive(originalPath: originalPath)
                            activeCacheOriginalPath = originalPath
                            fileURL = cached
                            self.playerLoadingDetail = L10n.tr("player.loading.using_cached_copy")
                        } else {
                            self.playerLoadingDetail = L10n.tr("player.loading.using_original")
                        }
                    } catch {
                        ACLog("Cache prepare failed (use original): \(error.localizedDescription)", level: .warn)
                        self.playerLoadingDetail = L10n.tr("player.loading.cache_unavailable")
                    }
                }
                ACLog("Creating AVPlayer for: \(fileURL.path)", level: .debug)
                self.playerLoadingTitle = L10n.tr("player.loading.starting")
                self.playerLoadingDetail = L10n.tr("player.loading.session_setup")
                let newPlayer = AVPlayer(url: fileURL)
                self.player = newPlayer
                let initSuccessMark: @Sendable () -> Void = { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.diagnostics.playerInitSuccess += 1
                        self.finalizeInitDiagnostics(success: true)
                    }
                }
                // Attach failure observer
                if let item = newPlayer.currentItem {
                    playerItemFailedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                                let ns = err as NSError
                                if ns.domain == NSOSStatusErrorDomain && ns.code == -128 {
                                    ACLog("Playback canceled (benign code -128) currentVideo=\(self.currentVideo?.fileName ?? "nil")", level: .trace)
                                    self.diagnostics.benignCancellations += 1
                                } else {
                                    ACLog("Playback failed code=\(ns.code) domain=\(ns.domain) desc=\(err.localizedDescription)", level: .error)
                                    self.playerLoadingTitle = L10n.tr("player.loading.failed")
                                    self.playerLoadingDetail = err.localizedDescription
                                    self.diagnostics.playerInitFailure += 1
                                }
                                self.finalizeInitDiagnostics(success: false)
                            } else {
                                ACLog("Playback failed (no error info)", level: .error)
                                self.playerLoadingTitle = L10n.tr("player.loading.failed")
                                self.playerLoadingDetail = L10n.tr("player.loading.no_error_details")
                                self.diagnostics.playerInitFailure += 1
                                self.finalizeInitDiagnostics(success: false)
                            }
                        }
                    }

                    // KVO observer for item status — catches -12860 and similar parse/access errors
                    playerItemStatusObserver = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
                        guard let item = item, item.status == .failed else { return }
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let err = item.error
                            let desc = err?.localizedDescription ?? "Unknown error"
                            let code = (err as? NSError)?.code ?? 0
                            ACLog("AVPlayerItem status failed: code=\(code) desc=\(desc)", level: .error)
                            self.player?.pause()
                            self.playerLoadingTitle = L10n.tr("player.loading.failed")
                            self.playerLoadingDetail = desc
                            self.isInitializingPlayer = true // Show error overlay
                        }
                    }

                    // Error log observer — logs non-fatal AVPlayer errors (e.g. intermittent read failures)
                    playerItemErrorLogObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak item] _ in
                        guard let item = item, let log = item.errorLog(), let last = log.events.last else { return }
                        ACLog("AVPlayer error log: code=\(last.errorStatusCode) domain=\(last.errorDomain) comment=\(last.errorComment ?? "-")", level: .warn)
                    }
                }
                // Setup resume logic after player item is ready
                if let savedPosition = videoToPlay.lastPlaybackPosition, savedPosition > 5 { // skip very small
                    let seekTime = CMTime(seconds: savedPosition, preferredTimescale: 600)
                    // Async load duration then seek; UI updates on MainActor
                    Task { [weak self, weak newPlayer] in
                        guard let self = self, let newPlayer = newPlayer, let asset = newPlayer.currentItem?.asset else { return }
                        do {
                            let duration = try await asset.load(.duration)
                            let durationSeconds = duration.seconds
                            if durationSeconds > 0, savedPosition < durationSeconds * 0.95 {
                                await MainActor.run {
                                    newPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                                    let mm = Int(savedPosition) / 60; let ss = Int(savedPosition) % 60
                                    self.resumeOverlayText = L10n.tr("player.resume_overlay", mm, ss)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.resumeOverlayText = nil }
                                    ACLog("Seeked to saved position: \(savedPosition)s (duration=\(durationSeconds)s)", level: .info)
                                }
                            }
                        } catch {
                            ACLog("Failed to load duration asynchronously: \(error.localizedDescription)", level: .error)
                        }
                    }
                }
                self.player?.play()
                self.playerLoadingTitle = nil
                self.playerLoadingDetail = nil
                initSuccessMark()
                // Setup periodic observer for position + auto-mark
                if timeObserverToken == nil, let player = self.player {
                    timeObserverToken = player.addPeriodicTimeObserver(forInterval: playbackPeriodicUpdateInterval, queue: .main) { [weak self, weak player] time in
                        guard let self = self, let player = player else { return }
                        Task { @MainActor [weak self, weak player] in
                            guard let self = self, let player = player else { return }
                            self.handlePlaybackPeriodicUpdate(time: time, player: player)
                        }
                    }
                    ACLog("Added periodic time observer for playback tracking", level: .trace)
                }
                if self.captionsFeatureEnabled {
                    // Reset caption states only if feature enabled
                    self.captionsForCurrentVideo = []
                    self.captionError = nil
                    self.captionLoading = true
                    if !self.showCaptions { self.showCaptions = true }
                    Task.detached { [weak self] in
                        guard let self = self else { return }
                        do {
                            let status = await LocalTranscriptionService.shared.requestAuthorization()
                            guard status == .authorized else {
                                ACLog("Speech not authorized: \(status.rawValue)", level: .warn)
                                await MainActor.run {
                                    self.captionError = L10n.tr("player.captions_unavailable")
                                    self.captionLoading = false
                                }
                                return
                            }
                            let segments = try await LocalTranscriptionService.shared.transcribe(url: fileURL, locales: ["zh-Hant", "zh-TW", "en-US"])
                            await MainActor.run {
                                self.captionLoading = false
                                if segments.isEmpty {
                                    self.captionError = L10n.tr("player.captions_unavailable")
                                } else {
                                    self.captionsForCurrentVideo = segments
                                    self.captionError = nil
                                }
                            }
                            ACLog("Generated \(segments.count) segments (multi-locale)", level: .info)
                        } catch {
                            ACLog("Transcription failed: \(error.localizedDescription)", level: .error)
                            await MainActor.run {
                                self.captionLoading = false
                                self.captionError = L10n.tr("player.captions_unavailable")
                            }
                        }
                    }
                } else {
                    // 功能停用：確保相關狀態清空且不顯示
                    self.showCaptions = false
                    self.captionsForCurrentVideo = []
                    self.captionError = nil
                    self.captionLoading = false
                }
                self.currentlyAccessedVideoURL = sourceFolderURL
            } else {
                ACLog("Failed to start security-scoped access for the source folder.", level: .error)
                self.playerLoadingTitle = L10n.tr("player.loading.unable")
                self.playerLoadingDetail = L10n.tr("player.loading.security_scope_failed")
                diagnostics.playerInitFailure += 1
                finalizeInitDiagnostics(success: false)
            }
    }

    /// Debounced scheduling of video selection; coalesces rapid taps into the last one.
    func scheduleSelectVideo(_ video: VideoItem?) {
        // Skip scheduling if the same video is already playing
        if currentVideo?.id == video?.id && video != nil {
            ACLog("scheduleSelectVideo - Same video already selected, skipping", level: .trace)
            return
        }
        ACLog("scheduleSelectVideo requested: \(video?.fileName ?? "nil")", level: .trace)
        pendingVideoSelectionTask?.cancel()
        diagnostics.selectionRequests += 1
        pendingVideoSelectionTask = Task { [weak self] in
            let interval = (self?.isInitializingPlayer == true) ? (self?.videoSelectionDebounceIntervalWhileInitializing ?? 0.3) : (self?.videoSelectionDebounceInterval ?? 0.15)
            do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.selectVideo(video) }
            }
        }
    }

    // MARK: - Diagnostics helpers
    private func finalizeInitDiagnostics(success: Bool) {
        guard isInitializingPlayer else { return }
        isInitializingPlayer = false
        if let start = currentInitStart { diagnostics.lastInitDuration = Date().timeIntervalSince(start) }
        // EWMA for average (alpha=0.3)
        let alpha = 0.3
        if diagnostics.avgInitDuration == 0 { diagnostics.avgInitDuration = diagnostics.lastInitDuration }
        else { diagnostics.avgInitDuration = alpha*diagnostics.lastInitDuration + (1-alpha)*diagnostics.avgInitDuration }
        logPlayerDiagnostics(context: success ? "init-success" : "init-end-failure")
    }
    private func logPlayerDiagnostics(context: String) {
        ACLog("DIAG[\(context)] selReq=\(diagnostics.selectionRequests) exec=\(diagnostics.executedSelections) success=\(diagnostics.playerInitSuccess) fail=\(diagnostics.playerInitFailure) benignCancel=\(diagnostics.benignCancellations) lastInit=\(String(format: "%.3f", diagnostics.lastInitDuration))s avgInit=\(String(format: "%.3f", diagnostics.avgInitDuration))s", level: .trace)
    }

    @MainActor
    private func markVideoAsWatched(_ video: VideoItem) async {
        // deprecated in favor of observer-based auto mark; keep for manual calls if needed
    ACLog("(Deprecated immediate) markVideoAsWatched called for: \(video.fileName)", level: .trace)
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
            ACLog("fileImporter returned \(urls.count) URL(s)", level: .debug)
            if let first = urls.first {
                logURLDiagnostics(first, context: "fileImporter selection (pre-security-scope)")
            }
            guard let folder = urls.first else { return }

            // First, stop all previous resource access on the main thread.
            stopAccessingAllResources()

            // Perform blocking file I/O and bookmarking on a background thread.
            Task.detached(priority: .userInitiated) {
                ACLog("Attempting startAccessingSecurityScopedResource on selected folder…", level: .debug)
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

        // Cancel any previous in-flight load
        loadCoursesTask?.cancel()
        loadCoursesTask = nil

        isLoadingCourses = true
        coursesLoadingProgress = L10n.tr("loading.scanning_folders")

        do {
            // ── Phase 1: Discover course folders (fast, no video enumeration) ──
            let loadResult = try await Task.detached { () -> (courseFolders: [URL], rootVideoFiles: [URL], debugListing: [String]) in
                let genericUnitFolderNames: Set<String> = ["單元_未分類", "未分類"]

                func isSupportedVideo(_ url: URL) -> Bool {
                    AppState.isSupportedVideoFile(url)
                }

                func isGenericUnitFolder(_ folderURL: URL) -> Bool {
                    genericUnitFolderNames.contains(folderURL.lastPathComponent)
                }

                func immediateDirectoryContents(of folderURL: URL) throws -> [URL] {
                    try FileManager.default.contentsOfDirectory(
                        at: folderURL,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: .skipsHiddenFiles
                    )
                }

                func immediateChildFolders(of folderURL: URL) throws -> [URL] {
                    try immediateDirectoryContents(of: folderURL)
                        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                }

                func immediateVideoFiles(in folderURL: URL) throws -> [URL] {
                    try immediateDirectoryContents(of: folderURL)
                        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false }
                        .filter(isSupportedVideo)
                }

                func directoryContainsSupportedVideos(_ folderURL: URL) throws -> Bool {
                    guard let enumerator = FileManager.default.enumerator(
                        at: folderURL,
                        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else {
                        return false
                    }

                    for case let fileURL as URL in enumerator {
                        if isSupportedVideo(fileURL) {
                            return true
                        }
                    }

                    return false
                }

                func discoverCourseFolders(in folderURL: URL) throws -> [URL] {
                    if !(try immediateVideoFiles(in: folderURL)).isEmpty {
                        return [folderURL]
                    }

                    let childFolders = try immediateChildFolders(of: folderURL)
                    let childFoldersWithVideos = try childFolders.filter { try directoryContainsSupportedVideos($0) }

                    guard !childFoldersWithVideos.isEmpty else {
                        return []
                    }

                    if childFoldersWithVideos.count == 1 {
                        let onlyChild = childFoldersWithVideos[0]
                        if isGenericUnitFolder(onlyChild) {
                            return [folderURL]
                        }
                        return try discoverCourseFolders(in: onlyChild)
                    }

                    if childFoldersWithVideos.contains(where: isGenericUnitFolder) {
                        return [folderURL]
                    }

                    return try childFoldersWithVideos.flatMap { try discoverCourseFolders(in: $0) }
                }

                let contents = try FileManager.default.contentsOfDirectory(
                    at: sourceURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: .skipsHiddenFiles
                )
                let files = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false }
                let rootVideos = files.filter(isSupportedVideo)
                let courseFolders = try discoverCourseFolders(in: sourceURL)
                let debugListing = contents.prefix(20).map { url in
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return "- \(url.lastPathComponent) \(isDir ? "[DIR]" : "[FILE] ext=\(url.pathExtension.lowercased())")"
                }
                return (courseFolders, rootVideos, debugListing)
            }.value
            
            let courseFolders = loadResult.courseFolders
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            let rootVideoFiles = loadResult.rootVideoFiles
            
            print("📚 [DEBUG] Found \(courseFolders.count) course folders; root has \(rootVideoFiles.count) supported video files")

            let existingCoursesByPath = Dictionary(uniqueKeysWithValues: self.courses.map {
                (self.normalizedCoursePath($0.folderURL), $0)
            })

            let includeRootAsCourse = !rootVideoFiles.isEmpty
            let candidateFolders = (includeRootAsCourse ? [sourceURL] : []) + courseFolders

            if candidateFolders.isEmpty {
                print("📚 [DEBUG] No supported video files found under the selected folder tree")
                if !loadResult.debugListing.isEmpty {
                    print("📚 [DEBUG] Directory listing (up to 20):\n" + loadResult.debugListing.joined(separator: "\n"))
                }
                // Check fallback: root has videos but discoverCourseFolders missed it
                if !rootVideoFiles.isEmpty {
                    let folderPath = self.normalizedCoursePath(sourceURL)
                    let existingCourse = existingCoursesByPath[folderPath]
                    let (targetDate, targetDescription) = await self.loadCourseMetadata(for: sourceURL)
                    let placeholder = Course(
                        id: existingCourse?.id ?? UUID(),
                        folderURL: sourceURL,
                        videos: existingCourse?.videos ?? [],
                        targetDate: targetDate,
                        targetDescription: targetDescription
                    )
                    self.courses = [placeholder]
                } else {
                    self.courses = []
                }
                self.isLoadingCourses = false
                self.coursesLoadingProgress = nil
                return
            }

            // ── Show courses immediately with previously-cached videos (no blocking scan) ──
            let candidateFolderPaths = Set(candidateFolders.map { self.normalizedCoursePath($0) })
            var placeholderCourses: [Course] = []
            for folderURL in candidateFolders {
                let folderPath = self.normalizedCoursePath(folderURL)
                let existingCourse = existingCoursesByPath[folderPath]
                let (targetDate, targetDescription) = await self.loadCourseMetadata(for: folderURL)
                placeholderCourses.append(Course(
                    id: existingCourse?.id ?? UUID(),
                    folderURL: folderURL,
                    videos: existingCourse?.videos ?? [],
                    targetDate: targetDate,
                    targetDescription: targetDescription
                ))
            }
            self.courses = placeholderCourses
            print("📚 [DEBUG] Phase 1 done: showing \(placeholderCourses.count) courses (videos pending)")

            // Auto-select first course immediately so the UI is interactive
            if self.selectedCourseID == nil, let firstCourse = self.courses.first {
                self.selectCourse(firstCourse.id)
            }

            // ── Phase 2: Load videos for each course incrementally ──
            let totalCourses = self.courses.count
            let courseSnapshots: [(id: UUID, folderURL: URL, index: Int)] = self.courses.enumerated().map { (i, c) in (c.id, c.folderURL, i) }

            // Start the incremental load as a cancellable task
            let incrementalTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for (offset, snapshot) in courseSnapshots.enumerated() {
                    try Task.checkCancellation()
                    self.coursesLoadingProgress = L10n.tr("loading.courses_progress", offset + 1, totalCourses)
                    let recursiveScan = self.shouldScanCourseRecursively(
                        folderURL: snapshot.folderURL,
                        knownCourseFolderPaths: candidateFolderPaths
                    )
                    let videos: [VideoItem]
                    do {
                        videos = try await self.loadVideoSnapshot(for: snapshot.folderURL, recursive: recursiveScan)
                    } catch {
                        print("📚 [DEBUG] Failed to load videos for \(snapshot.folderURL.lastPathComponent): \(error.localizedDescription)")
                        continue
                    }
                    try Task.checkCancellation()
                    // Update the matching course (it may have shifted index)
                    if let idx = self.courseIndex(for: snapshot.id) {
                        self.courses[idx].videos = videos
                    }
                }
                self.isLoadingCourses = false
                self.coursesLoadingProgress = nil
                print("📚 [DEBUG] Phase 2 done: all course videos loaded")

                // Ensure selected course has videos loaded
                if let selectedID = self.selectedCourseID,
                   let idx = self.courseIndex(for: selectedID),
                   self.courses[idx].videos.isEmpty {
                    await self.loadVideos(for: self.courses[idx])
                }
            }
            self.loadCoursesTask = incrementalTask

            // Await completion (cancellation propagates naturally)
            do { try await incrementalTask.value } catch {
                ACLog("loadCourses incremental phase cancelled", level: .debug)
            }

            if let selectedCourseID = self.selectedCourseID,
               self.courseIndex(for: selectedCourseID) == nil {
                self.selectedCourseID = nil
            }
        } catch {
            print("讀取課程資料夾失敗: \(error.localizedDescription) at: \(sourceURL.path)")
            print("請確認應用程式有存取所選資料夾的權限，或嘗試重新選擇資料夾")
        }
        self.isLoadingCourses = false
        self.coursesLoadingProgress = nil
    }

    func loadVideos(for course: Course) async {
        print("🎬 [DEBUG] loadVideos called for course: \(course.folderURL.lastPathComponent)")
        guard courseIndex(for: course.id) != nil else {
            print("🎬 [DEBUG] Course not found in courses array: \(course.folderURL.lastPathComponent)")
            return 
        }

        // 使用 Task.detached 在背景執行檔案操作
        do {
            let shouldScanRecursively = shouldScanCourseRecursively(course)
            let updatedVideos = try await self.loadVideoSnapshot(for: course.folderURL, recursive: shouldScanRecursively)

            if updatedVideos.isEmpty {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: course.folderURL,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                let debugList = contents.prefix(20).map { url in "- \(url.lastPathComponent) [ext=\(url.pathExtension.lowercased())]" }
                print("🎬 [DEBUG] No supported video files found. Directory sample (up to 20):\n" + debugList.joined(separator: "\n"))
            }

            print("🎬 [DEBUG] Found \(updatedVideos.count) videos for \(course.folderURL.lastPathComponent), scheduling UI update")
            guard let courseIndex = self.courseIndex(for: course.id) else { return }
            print("🎬 [DEBUG] Applying loadVideos result on @MainActor for: \(course.folderURL.lastPathComponent)")
            self.courses[courseIndex].videos = updatedVideos
            print("為課程 \(course.folderURL.lastPathComponent) 載入/更新了 \(updatedVideos.count) 個影片。")
            
            // Save updated video data
            await self.saveVideos(for: course.id)
        } catch {
            print("讀取影片檔案失敗: \(error.localizedDescription)")
            print("請確認應用程式有存取所選資料夾的權限")
        }
    }

    @MainActor
    func saveVideos(for courseID: UUID) async {
        guard let courseIndex = courseIndex(for: courseID) else { return }
        let course = courses[courseIndex]
        
        // Capture all needed data before going to background
        let videosToSave = course.videos
        let folderURL = course.folderURL
        
        // Perform the file I/O on a background thread
        await Task.detached {
            LocalMetadataStorage.saveVideos(videosToSave, for: folderURL)
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
        ACLog("Setting target date for course: \(courseID.uuidString.prefix(8))", level: .debug)
        
        guard let courseIndex = courseIndex(for: courseID) else {
            ACLog("Course not found for setting target date", level: .warn)
            return
        }
        
        courses[courseIndex].targetDate = targetDate
        courses[courseIndex].targetDescription = description
        
        ACLog("Target date set: \(targetDate?.formatted(date: .abbreviated, time: .omitted) ?? "nil"), description: \(description)", level: .debug)
        
        // 保存課程數據
        await saveCourseMetadata(for: courseID)
    }
    
    /// 獲取指定課程的倒數計日資訊
    func getCountdownInfo(for courseID: UUID) -> (daysRemaining: Int?, countdownText: String, isOverdue: Bool) {
        guard let courseIndex = courseIndex(for: courseID) else {
            return (nil, L10n.tr("course.not_found"), false)
        }
        let course = courses[courseIndex]
        
        return (course.daysRemaining, course.countdownText, course.isOverdue)
    }
    
    /// 保存課程元數據（包括倒數計日資訊）
    @MainActor
    private func saveCourseMetadata(for courseID: UUID) async {
        guard let courseIndex = courseIndex(for: courseID) else { return }
        let course = courses[courseIndex]
        let metadata = LocalMetadataStorage.CourseMetadata(
            targetDate: course.targetDate,
            targetDescription: course.targetDescription
        )
        
        // 在背景線程保存數據
        await Task.detached {
            LocalMetadataStorage.saveCourseMetadata(metadata, for: course.folderURL)
            ACLog("Course metadata saved for folder: \(course.folderURL.lastPathComponent)", level: .info)
        }.value
    }
    
    /// 載入課程元數據（包括倒數計日資訊）
    @MainActor
    private func loadCourseMetadata(for folderURL: URL) async -> (targetDate: Date?, targetDescription: String) {
        return await Task.detached {
            guard let metadata = LocalMetadataStorage.loadCourseMetadata(for: folderURL) else {
                return (nil, "")
            }
            return (metadata.targetDate, metadata.targetDescription)
        }.value
    }
}
