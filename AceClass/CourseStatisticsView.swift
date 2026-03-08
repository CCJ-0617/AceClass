//
//  CourseStatisticsView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI

struct CourseStats {
    let totalVideos: Int
    let watchedVideos: Int

    var percentageWatched: Double {
        totalVideos > 0 ? Double(watchedVideos) / Double(totalVideos) : 0.0
    }

    var formattedPercentage: String {
        String(format: "%.0f%%", percentageWatched * 100)
    }

    var unwatchedCount: Int {
        totalVideos - watchedVideos
    }
}

struct UnwatchedVideosListView: View {
    let unwatchedVideos: [VideoItem]
    let playAction: (VideoItem) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("course.pending_videos"))
                .font(.headline)

            if unwatchedVideos.isEmpty {
                Text(L10n.tr("course.no_pending_videos"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(unwatchedVideos) { video in
                            UnwatchedVideoRowView(video: video, playAction: { await playAction(video) })
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }
}

struct CourseStatisticsView: View {
    let stats: CourseStats
    let course: Course
    let unwatchedVideos: [VideoItem]
    let playUnwatchedVideoAction: (VideoItem) async -> Void

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width - 48, 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

                    HStack(spacing: 12) {
                    MetricCard(title: L10n.tr("metric.total_videos"), value: "\(stats.totalVideos)", tint: .blue)
                    MetricCard(title: L10n.tr("metric.completed"), value: "\(stats.watchedVideos)", tint: .green)
                    MetricCard(title: L10n.tr("metric.pending"), value: "\(stats.unwatchedCount)", tint: .orange)
                    }

                    HStack(alignment: .center, spacing: 24) {
                        progressRing
                        VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.tr("course.progress_header"))
                                .font(.headline)
                            Text(course.learningStatusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ProgressView(value: stats.percentageWatched)
                                .tint(course.unwatchedVideoCount == 0 ? .green : .accentColor)

                            HStack(spacing: 8) {
                                MetadataChip(item: MetadataChipItem(title: course.completionText, systemImage: "checkmark.circle", tint: .green))
                                if let targetSummaryText = course.targetSummaryText {
                                    MetadataChip(item: MetadataChipItem(title: targetSummaryText, systemImage: "calendar.badge.clock", tint: .orange))
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(22)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    UnwatchedVideosListView(
                        unwatchedVideos: unwatchedVideos,
                        playAction: playUnwatchedVideoAction
                    )
                    .padding(22)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(course.displayTitle)
                .font(.system(size: 32, weight: .bold))

            Text(L10n.tr("course.statistics_intro"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FlowMetadataRow(items: headerMetadata)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35))
        )
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 18)

            Circle()
                .trim(from: 0.0, to: stats.percentageWatched)
                .stroke(
                    LinearGradient(colors: [.accentColor, .green], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if let countdown = countdownProgress {
                Circle()
                    .trim(from: 0.0, to: countdown.progress)
                    .stroke(countdown.color.opacity(0.7), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(0.72)
            }

            VStack(spacing: 4) {
                Text(stats.formattedPercentage)
                    .font(.title.bold())
                Text(L10n.tr("course.completed_short"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 164, height: 164)
    }

    private var headerMetadata: [MetadataChipItem] {
        var items = [MetadataChipItem(title: course.progressPercentText, systemImage: "chart.bar", tint: .blue)]

        if let targetSummaryText = course.targetSummaryText {
            items.append(MetadataChipItem(title: targetSummaryText, systemImage: "calendar", tint: .orange))
        }

        items.append(MetadataChipItem(title: course.learningStatusText, systemImage: "sparkles.rectangle.stack", tint: .teal))
        return items
    }

    private var countdownProgress: (progress: Double, color: Color)? {
        guard let target = course.targetDate else { return nil }
        let remainingSeconds = target.timeIntervalSince(Date())
        let dayInSeconds = 24.0 * 60.0 * 60.0
        let windowSeconds = 30.0 * dayInSeconds

        if remainingSeconds <= 0 {
            return (1.0, .red)
        }

        let clamped = min(remainingSeconds, windowSeconds)
        let progress = 1.0 - (clamped / windowSeconds)
        let color: Color = remainingSeconds <= 3.0 * dayInSeconds ? .orange : .blue
        return (progress, color)
    }
}

#Preview {
    CourseStatisticsView(
        stats: CourseStats(totalVideos: 10, watchedVideos: 4),
        course: Course(
            folderURL: URL(fileURLWithPath: "/test"),
            targetDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            targetDescription: "期末考"
        ),
        unwatchedVideos: [
            VideoItem(fileName: "範例影片1.mp4", note: "未觀看的影片1"),
            VideoItem(fileName: "範例影片2.mp4", note: "未觀看的影片2")
        ],
        playUnwatchedVideoAction: { _ in }
    )
    .frame(width: 700, height: 720)
}
