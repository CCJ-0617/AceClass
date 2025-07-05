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
    
    private var formattedDate: String {
        guard let date = video.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(video.displayName.isEmpty ? video.fileName : video.displayName)
                    .lineLimit(1)
                    .font(.headline)
                
                Text(video.note.isEmpty ? "無註解" : video.note)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if !formattedDate.isEmpty {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            // 使用異步調用來避免在視圖更新期間修改狀態
            DispatchQueue.main.async {
                playAction()
            }
        }
    }
}
