//
//  ContentView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI
import AVKit

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var showFolderPicker = false
    @State private var localSelectedCourseID: UUID? // Local state to prevent direct binding issues
    @State private var showingCountdownCenter = false

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
            .toolbar(appState.isVideoPlayerFullScreen ? .hidden : .visible, for: .windowToolbar)
            .toolbar {
                if !appState.courses.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            showingCountdownCenter = true
                        } label: {
                            Image(systemName: "calendar.badge.clock")
                        }
                        .help("倒數中心")
                        
                        Button {
                            showingCountdownCenter = true
                        } label: {
                            Image(systemName: "gear")
                        }
                        .help("倒數中心")
                        .disabled(localSelectedCourseID == nil)
                    }
                }
            }
            .sheet(isPresented: $showingCountdownCenter) {
                CountdownCenterView(appState: appState, initialSelectedCourseID: localSelectedCourseID)
            }
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                Task {
                    await appState.handleFolderSelection(result)
                }
            }
            
            // 依賴 isFullScreen 和 player 來決定是否顯示全螢幕播放器
            if appState.isVideoPlayerFullScreen, let player = appState.player {
                // 傳遞共享的播放器實例給全螢幕 View
                FullScreenVideoPlayerView(player: player, onToggleFullScreen: appState.toggleFullScreen, showCaptions: appState.showCaptions, captionSegments: appState.captionsForCurrentVideo)
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
            if let url = appState.sourceFolderURL {
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
            if appState.courses.isEmpty {
                Spacer()
                Text("請先選擇來源資料夾")
                    .foregroundColor(.secondary)
                    .padding()
                Spacer()
            } else {
                List(selection: $localSelectedCourseID) {
                    ForEach(appState.courses) { course in
                        CourseRowView(course: course)
                            .tag(course.id)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: localSelectedCourseID) { _, newValue in
                    if newValue != appState.selectedCourseID {
                        // Use the safe selection method
                        appState.selectCourse(newValue)
                    }
                }
                .onChange(of: appState.selectedCourseID) { _, newValue in
                    if newValue != localSelectedCourseID {
                        localSelectedCourseID = newValue
                    }
                }
            }
        }
    }
    
    private var videoList: some View {
        Group {
            if let idx = appState.selectedCourseIndex, appState.courses.indices.contains(idx) {
                // 使用一個綁定來確保 UI 能響應內部 video 陣列的變化
                let courseBinding = $appState.courses[idx]
                let course = courseBinding.wrappedValue

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
                            ForEach(courseBinding.videos) { $video in
                                VideoRowView(
                                    video: $video,
                                    isPlaying: appState.currentVideo?.id == video.id,
                                    playAction: { 
                                        await appState.selectVideo(video) 
                                    },
                                    saveAction: { 
                                        await appState.saveVideos(for: course.id)
                                    }
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
            // 現在只檢查是否有影片被選中，播放器由 AppState 自己管理
            if let video = appState.currentVideo {
                VStack(spacing: 0) {
                    // 影片標題區
                    Text(video.note)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)

                    // 播放器區
                    VideoPlayerView(appState: appState, isFullScreen: $appState.isVideoPlayerFullScreen)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 5, y: 3)
                .padding(20)

            } else if let course = appState.selectedCourse {
                let stats = calculateCourseStats(for: course)
                let unwatched = course.videos.filter { !$0.watched }
                CourseStatisticsView(
                    stats: stats,
                    course: course,
                    unwatchedVideos: unwatched,
                    playUnwatchedVideoAction: { video in
                        await appState.selectVideo(video)
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

    // MARK: - Helper Methods
    
    private func calculateCourseStats(for course: Course) -> CourseStats {
        let total = course.videos.count
        let watched = course.videos.filter { $0.watched }.count
        return CourseStats(totalVideos: total, watchedVideos: watched)
    }
}

// MARK: - Sheet Wrappers for Countdown Views
struct CountdownOverviewSheet: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool
    
    var body: some View {
        CountdownOverviewView(appState: appState)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") {
                        isPresented = false
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 600)  // 設定視窗大小
    }
}

struct CountdownSettingsSheet: View {
    @ObservedObject var appState: AppState
    let courseID: UUID
    @Binding var isPresented: Bool
    
    var body: some View {
        CountdownSettingsView(appState: appState, courseID: courseID)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") {
                        isPresented = false
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 500)  // 設定視窗大小
    }
}

#Preview {
    ContentView()
}
