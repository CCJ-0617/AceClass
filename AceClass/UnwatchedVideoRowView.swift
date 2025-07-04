//
//  UnwatchedVideoRowView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI

// 1. 未觀看影片列表的視圖，整列皆可點擊
struct UnwatchedVideoRowView: View {
    let video: VideoItem
    let playAction: () -> Void

    var body: some View {
        // 1. 將整列視圖改為按鈕，提升互動性
        Button(action: playAction) {
            HStack {
                // 2. 增加播放圖示，更直觀
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                // 3. 顯示註解，並在滑鼠懸停時顯示原始檔名
                Text(video.note)
                    .help(video.fileName)
                
                Spacer()
                
                // 4. 增加指示符號
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // 確保整個 HStack 區域都能響應點擊
        }
        .buttonStyle(.plain) // 使用 .plain 風格以避免預設的按鈕外觀
    }
}
