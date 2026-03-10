//
//  ContentView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI
import AVKit

struct AppCardSurface: View {
    let colorScheme: ColorScheme
    var cornerRadius: CGFloat = 24
    var tint: Color = .accentColor
    var tintStrength: Double = 0.08
    var isSelected: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(baseStyle)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: overlayColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.4 : 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: shadowColor, radius: isSelected ? 22 : 14, y: isSelected ? 12 : 7)
            .shadow(color: topGlowColor, radius: 1.5, y: -1)
    }

    private var baseStyle: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(.thinMaterial)
        }
        return AnyShapeStyle(Color.white.opacity(isSelected ? 0.94 : 0.88))
    }

    private var overlayColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(0.10),
                tint.opacity(tintStrength),
                Color.clear
            ]
        }
        return [
            Color.white.opacity(isSelected ? 0.78 : 0.62),
            tint.opacity(tintStrength + (isSelected ? 0.05 : 0)),
            Color.clear
        ]
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return isSelected ? tint.opacity(0.44) : Color.white.opacity(0.14)
        }
        return isSelected ? tint.opacity(0.34) : Color.black.opacity(0.06)
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return .black.opacity(isSelected ? 0.20 : 0.14)
        }
        return .black.opacity(isSelected ? 0.10 : 0.06)
    }

    private var topGlowColor: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .white.opacity(isSelected ? 0.72 : 0.52)
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var appState = AppState()
    @State private var showFolderPicker = false
    @State private var localSelectedCourseID: UUID?
    @State private var showingCountdownCenter = false
    @State private var showingDebugConsole = false

    var body: some View {
        ZStack {
            NavigationSplitView {
                courseSidebar
            } content: {
                videoList
                    .navigationSplitViewColumnWidth(min: 340, ideal: 460, max: 640)
            } detail: {
                videoPlayerArea
            }
            .navigationTitle(L10n.tr("app.title"))
            .toolbar(appState.isVideoPlayerFullScreen ? .hidden : .visible, for: .windowToolbar)
            .toolbar {
                if !appState.courses.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            showFolderPicker = true
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .help(L10n.tr("toolbar.change_folder"))

                        Button {
                            showingCountdownCenter = true
                        } label: {
                            Image(systemName: "calendar.badge.clock")
                        }
                        .help(L10n.tr("toolbar.countdown_center"))

                        Button {
                            showingDebugConsole = true
                        } label: {
                            Image(systemName: "ladybug")
                        }
                        .help(L10n.tr("toolbar.debug_console"))
                    }
                }
            }
            .sheet(isPresented: $showingCountdownCenter) {
                CountdownCenterView(appState: appState, initialSelectedCourseID: localSelectedCourseID)
            }
            .sheet(isPresented: $showingDebugConsole) {
                DebugConsoleView(appState: appState)
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await appState.handleFolderSelection(result)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      window === NSApplication.shared.mainWindow else { return }
                if !window.occlusionState.contains(.visible) {
                    appState.player?.pause()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                appState.player?.pause()
            }

            if appState.isVideoPlayerFullScreen, let player = appState.player {
                FullScreenVideoPlayerView(
                    player: player,
                    onToggleFullScreen: appState.toggleFullScreen,
                    showCaptions: appState.showCaptions,
                    captionSegments: appState.captionsForCurrentVideo
                )
            }
        }
    }

    private var courseSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            SidebarHeroCard(
                sourceFolderURL: appState.sourceFolderURL,
                totalCourses: appState.courses.count,
                totalVideos: totalVideoCount,
                onPickFolder: { showFolderPicker = true }
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if !appState.courses.isEmpty {
                HStack(spacing: 10) {
                    MetricCard(title: L10n.tr("metric.courses"), value: "\(appState.courses.count)", tint: .blue)
                    MetricCard(title: L10n.tr("metric.videos"), value: "\(totalVideoCount)", tint: .indigo)
                    MetricCard(title: L10n.tr("metric.remaining"), value: "\(remainingVideoCount)", tint: .orange)
                }
                .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.tr("sidebar.course_list"))
                        .font(.headline)
                    Spacer()
                    if appState.isLoadingCourses {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("\(appState.courses.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                if appState.isLoadingCourses, let progress = appState.coursesLoadingProgress {
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                if appState.courses.isEmpty {
                    EmptyStateCard(
                        icon: "folder",
                        title: L10n.tr("empty.no_source.title"),
                        subtitle: L10n.tr("empty.no_source.subtitle")
                    )
                    .padding(.horizontal, 16)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(appState.courses) { course in
                                CourseRowView(course: course, isSelected: localSelectedCourseID == course.id)
                                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .onTapGesture {
                                        if localSelectedCourseID != course.id {
                                            withAnimation(.smooth(duration: 0.18)) {
                                                localSelectedCourseID = course.id
                                            }
                                        }
                                        if course.id != appState.selectedCourseID {
                                            appState.selectCourse(course.id)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .onChange(of: appState.selectedCourseID) { _, newValue in
                        if newValue != localSelectedCourseID {
                            withAnimation(.smooth(duration: 0.18)) {
                                localSelectedCourseID = newValue
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 300)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var videoList: some View {
        Group {
            if let idx = appState.selectedCourseIndex, appState.courses.indices.contains(idx) {
                let courseBinding = $appState.courses[idx]
                let course = courseBinding.wrappedValue

                VStack(alignment: .leading, spacing: 16) {
                    CourseOverviewCard(course: course)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    if course.videos.isEmpty {
                        Spacer()
                        EmptyStateCard(
                            icon: "play.slash",
                            title: L10n.tr("empty.no_video.title"),
                            subtitle: L10n.tr("empty.no_video.subtitle", AppState.supportedVideoFormatsDescription)
                        )
                        .padding(.horizontal, 16)
                        Spacer()
                    } else {
                        List {
                            ForEach(courseBinding.videos) { $video in
                                VideoRowView(
                                    video: $video,
                                    videoURL: course.folderURL.appendingPathComponent(video.relativePath),
                                    isPlaying: appState.currentVideo?.id == video.id,
                                    changeAction: {
                                        appState.publishCoursesSnapshot()
                                    },
                                    playAction: {
                                        appState.scheduleSelectVideo(video)
                                    },
                                    saveAction: {
                                        await appState.saveVideos(for: course.id)
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                    }
                }
                .background(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.05), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                EmptyStateCard(
                    icon: "rectangle.stack",
                    title: L10n.tr("empty.no_course.title"),
                    subtitle: L10n.tr("empty.no_course.subtitle")
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var videoPlayerArea: some View {
        Group {
            if let video = appState.currentVideo {
                VStack(alignment: .leading, spacing: 16) {
                    videoMetadataHeader(for: video)
                    VideoPlayerView(appState: appState, isFullScreen: $appState.isVideoPlayerFullScreen)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
                }
                .padding(20)
            } else if let course = appState.selectedCourse {
                let stats = calculateCourseStats(for: course)
                let unwatched = course.videos.filter { !$0.watched }
                CourseStatisticsView(
                    stats: stats,
                    course: course,
                    unwatchedVideos: unwatched,
                    playUnwatchedVideoAction: { video in
                        appState.scheduleSelectVideo(video)
                    }
                )
            } else {
                EmptyStateCard(
                    icon: "film.stack",
                    title: L10n.tr("empty.ready.title"),
                    subtitle: L10n.tr("empty.ready.subtitle")
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private func videoMetadataHeader(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.resolvedTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)

                    if let selectedCourse = appState.selectedCourse {
                        Text(selectedCourse.displayTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let selectedCourse = appState.selectedCourse, selectedCourse.targetDate != nil {
                    CountdownDisplay(course: selectedCourse)
                }
            }

            FlowMetadataRow(items: metadataItems(for: video))

            Text(video.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .background {
            AppCardSurface(colorScheme: colorScheme, cornerRadius: 24, tint: .accentColor, tintStrength: 0.08)
        }
    }

    private func metadataItems(for video: VideoItem) -> [MetadataChipItem] {
        var items = [MetadataChipItem(
            title: video.watchStatusText,
            systemImage: video.watched ? "checkmark.circle.fill" : "circle",
            tint: video.watched ? .green : .orange
        )]

        items.append(MetadataChipItem(title: video.fileTypeLabel, systemImage: "film", tint: .indigo))

        if let formattedDateText = video.formattedDateText {
            items.append(MetadataChipItem(title: formattedDateText, systemImage: "calendar", tint: .blue))
        }

        if let playbackPositionText = video.playbackPositionText {
            items.append(MetadataChipItem(title: playbackPositionText, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", tint: .teal))
        }

        return items
    }

    private func calculateCourseStats(for course: Course) -> CourseStats {
        CourseStats(totalVideos: course.totalVideoCount, watchedVideos: course.watchedVideoCount)
    }

    private var totalVideoCount: Int {
        appState.courses.reduce(0) { $0 + $1.totalVideoCount }
    }

    private var remainingVideoCount: Int {
        appState.courses.reduce(0) { $0 + $1.unwatchedVideoCount }
    }
}

struct SidebarHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let sourceFolderURL: URL?
    let totalCourses: Int
    let totalVideos: Int
    let onPickFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("app.title"))
                        .font(.system(size: 28, weight: .bold))
                    Text(L10n.tr("app.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "graduationcap.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
            }

            Button(action: onPickFolder) {
                Label(sourceFolderURL == nil ? L10n.tr("sidebar.select_folder") : L10n.tr("sidebar.change_folder"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let sourceFolderURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("sidebar.current_source"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(sourceFolderURL.path)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            } else {
                Text(L10n.tr("sidebar.source_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if totalCourses > 0 || totalVideos > 0 {
                Text(L10n.tr("sidebar.courses_videos_summary", totalCourses, totalVideos))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background {
            AppCardSurface(colorScheme: colorScheme, cornerRadius: 24, tint: .accentColor, tintStrength: 0.14, isSelected: true)
        }
    }
}

struct CourseOverviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(course.displayTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)

                    Text(course.learningStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if course.targetDate != nil {
                    CountdownDisplay(course: course)
                }
            }

            HStack(spacing: 10) {
                MetadataChip(item: MetadataChipItem(title: course.completionText, systemImage: "checkmark.circle", tint: .green))
                MetadataChip(item: MetadataChipItem(title: course.progressPercentText, systemImage: "chart.bar.xaxis", tint: .blue))
                if let targetSummaryText = course.targetSummaryText {
                    MetadataChip(item: MetadataChipItem(title: targetSummaryText, systemImage: "calendar.badge.clock", tint: .orange))
                }
            }

            ProgressView(value: course.completionRatio)
                .tint(course.unwatchedVideoCount == 0 ? .green : .accentColor)
        }
        .padding(18)
        .background {
            AppCardSurface(colorScheme: colorScheme, cornerRadius: 24, tint: .accentColor, tintStrength: 0.09)
        }
    }
}

struct MetricCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? tint.opacity(0.10) : Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.52),
                                    tint.opacity(colorScheme == .dark ? 0.06 : 0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? tint.opacity(0.14) : Color.black.opacity(0.05))
                )
        )
    }
}

struct MetadataChipItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
}

struct MetadataChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MetadataChipItem

    var body: some View {
        Label(item.title, systemImage: item.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(item.tint)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? item.tint.opacity(0.10) : Color.white.opacity(0.78))
                    .overlay(
                        Capsule()
                            .fill(item.tint.opacity(colorScheme == .dark ? 0.04 : 0.10))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(colorScheme == .dark ? item.tint.opacity(0.12) : Color.black.opacity(0.04))
                    )
            )
    }
}

struct FlowMetadataRow: View {
    let items: [MetadataChipItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    MetadataChip(item: item)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    MetadataChip(item: item)
                }
            }
        }
    }
}

struct EmptyStateCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background {
            AppCardSurface(colorScheme: colorScheme, cornerRadius: 24, tint: .accentColor, tintStrength: 0.05)
        }
    }
}

#Preview {
    ContentView()
}
