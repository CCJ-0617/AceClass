//
//  CourseStatisticsView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI

// 1. 新增一個結構來存放課程的統計數據
struct CourseStats {
    let totalVideos: Int
    let watchedVideos: Int
    
    var percentageWatched: Double {
        totalVideos > 0 ? Double(watchedVideos) / Double(totalVideos) : 0.0
    }
    
    var formattedPercentage: String {
        String(format: "%.1f%%", percentageWatched * 100)
    }
    
    var unwatchedCount: Int {
        totalVideos - watchedVideos
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
            Text("\(stats.unwatchedCount)")
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

// 3. 將未觀看影片列表抽離成獨立的 View
struct UnwatchedVideosListView: View {
    let unwatchedVideos: [VideoItem]
    let playAction: (VideoItem) async -> Void

    var body: some View {
        if !unwatchedVideos.isEmpty {
            Divider()
                .padding(.vertical, 10)

            Text("待觀看影片")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unwatchedVideos) { video in
                        UnwatchedVideoRowView(video: video, playAction: { await playAction(video) })
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
}


// 2. 新增一個專門顯示統計數據的 View（加入內圈倒數環）
struct CourseStatisticsView: View {
    let stats: CourseStats
    let course: Course
    let unwatchedVideos: [VideoItem]
    let playUnwatchedVideoAction: (VideoItem) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 標題
            Text(course.folderURL.lastPathComponent)
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 5)

            // 進度環與統計數據
            HStack(spacing: 50) {
                ZStack {
                    // 外圈背景
                    Circle()
                        .stroke(lineWidth: 20)
                        .opacity(0.25)
                        .foregroundColor(.blue)

                    // 外圈已觀看進度
                    Circle()
                        .trim(from: 0.0, to: stats.percentageWatched)
                        .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                        .foregroundColor(.blue)
                        .rotationEffect(Angle(degrees: -90))
                        .animation(.linear, value: stats.percentageWatched)

                    // 內圈倒數（若有）
                    if let countdown = countdownProgress {
                        Circle()
                            .trim(from: 0.0, to: countdown.progress)
                            .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                            .foregroundColor(countdown.color)
                            .rotationEffect(Angle(degrees: -90))
                            .scaleEffect(0.70) // 內圈縮小
                            .animation(.linear, value: countdown.progress)
                    }

                    VStack {
                        Text(stats.formattedPercentage)
                            .font(.title)
                            .bold()
                        Text("完成")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 15) {
                    StatRow(label: "總影片數", value: "\(stats.totalVideos)")
                    StatRow(label: "已觀看", value: "\(stats.watchedVideos)")
                    StatRow(label: "未觀看", value: "\(stats.unwatchedCount)")
                }
            }
            .padding(.bottom, 20)

            // 未觀看影片列表
            VStack(alignment: .leading, spacing: 10) {
                Text("未觀看的影片")
                    .font(.title2)
                    .bold()

                if unwatchedVideos.isEmpty {
                    Text("恭喜！您已觀看所有影片。")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(unwatchedVideos) { video in
                                UnwatchedVideoRowView(video: video) {
                                    // Use Task to handle the async action
                                    await playUnwatchedVideoAction(video)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }

            Spacer()
        }
        .padding(30)
    }

    // 內圈倒數進度（以 30 天為視覺窗，不足/超過會分別飽和為 1 / 0）
    private var countdownProgress: (progress: Double, color: Color)? {
        guard let target = course.targetDate else { return nil }
        let now = Date()
        let remainingSeconds = target.timeIntervalSince(now) // 正值：未到期；負值：已過期
        let dayInSeconds = 24.0 * 60.0 * 60.0
        let windowSeconds = 30.0 * dayInSeconds
        if remainingSeconds <= 0 { return (1.0, .red) }
        let clamped = min(remainingSeconds, windowSeconds)
        let progress = 1.0 - (clamped / windowSeconds)
        let color: Color = remainingSeconds <= 3.0 * dayInSeconds ? .orange : .blue
        return (progress, color)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.title3)
                .bold()
        }
    }
}

#Preview {
    CourseStatisticsView(
        stats: CourseStats(totalVideos: 10, watchedVideos: 4),
        course: Course(folderURL: URL(fileURLWithPath: "/test"), targetDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()), targetDescription: "期末考"),
        unwatchedVideos: [
            VideoItem(fileName: "範例影片1.mp4", note: "未觀看的影片1"),
            VideoItem(fileName: "範例影片2.mp4", note: "未觀看的影片2")
        ],
        playUnwatchedVideoAction: { _ in }
    )
    .frame(width: 600, height: 500)
}
