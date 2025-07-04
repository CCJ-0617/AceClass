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
        ScrollView {
            VStack(spacing: 24) {
                // 標題
                Text(courseName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)

                // 環圈進度圖
                ProgressRingView(stats: stats)

                // 數據統計列
                StatisticsRowsView(stats: stats)

                // 待觀看列表
                UnwatchedVideosListView(
                    unwatchedVideos: unwatchedVideos,
                    playAction: playUnwatchedVideoAction
                )
            }
            .padding(.horizontal, 30)
            .padding(.vertical)
        }
    }
}

// 4. 新增：環圈進度圖 View
struct ProgressRingView: View {
    let stats: CourseStats

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 20.0)
                .opacity(0.1)
                .foregroundColor(.blue)

            Circle()
                .trim(from: 0.0, to: CGFloat(min(stats.progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 20.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(.blue)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: stats.progress)

            VStack {
                Text(String(format: "%.1f%%", stats.progress * 100))
                    .font(.largeTitle)
                    .bold()
                Text("完成度")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 200, height: 200)
        .padding()
    }
}
