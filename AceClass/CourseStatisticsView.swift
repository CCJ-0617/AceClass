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
    let playAction: (VideoItem) -> Void

    var body: some View {
        if !unwatchedVideos.isEmpty {
            Divider()
                .padding(.vertical, 10)

            Text("待觀看影片")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unwatchedVideos) { video in
                        UnwatchedVideoRowView(video: video, playAction: { playAction(video) })
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
    let unwatchedVideos: [VideoItem]
    let playUnwatchedVideoAction: (VideoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 標題
            Text(courseName)
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 5)

            // 進度環與統計數據
            HStack(spacing: 50) {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 20)
                        .opacity(0.3)
                        .foregroundColor(.blue)

                    Circle()
                        .trim(from: 0.0, to: stats.percentageWatched)
                        .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                        .foregroundColor(.blue)
                        .rotationEffect(Angle(degrees: -90))
                        .animation(.linear, value: stats.percentageWatched)

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
                                    // 使用異步調用來避免在視圖更新期間修改狀態
                                    DispatchQueue.main.async {
                                        playUnwatchedVideoAction(video)
                                    }
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
        courseName: "測試課程",
        unwatchedVideos: [
            VideoItem(fileName: "範例影片1.mp4", note: "未觀看的影片1"),
            VideoItem(fileName: "範例影片2.mp4", note: "未觀看的影片2")
        ],
        playUnwatchedVideoAction: { _ in }
    )
    .frame(width: 600, height: 500)
}
