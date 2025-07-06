//
//  VideoRowView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI

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
                    .onChange(of: video.note) { _, _ in 
                        // 使用異步調用來避免在視圖更新期間觸發狀態變更
                        DispatchQueue.main.async {
                            saveAction()
                        }
                    }

                Spacer()

                // 播放按鈕保持在右上角
                Button(action: {
                    // 使用異步調用來避免在視圖更新期間觸發狀態變更
                    DispatchQueue.main.async {
                        playAction()
                    }
                }) {
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
                    .onChange(of: video.displayName) { _, _ in 
                        // 使用異步調用來避免在視圖更新期間觸發狀態變更
                        DispatchQueue.main.async {
                            saveAction() 
                        }
                    }

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
                    // 使用異步調用來避免在視圖更新期間觸發狀態變更
                    DispatchQueue.main.async {
                        video.watched.toggle()
                        saveAction()
                    }
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
