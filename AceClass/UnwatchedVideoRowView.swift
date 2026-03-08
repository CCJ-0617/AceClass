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
    let playAction: () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(video.resolvedTitle)
                    .lineLimit(1)
                    .font(.headline)
                
                Text(video.fileName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if let formattedDateText = video.formattedDateText {
                Text(formattedDateText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await playAction()
            }
        }
    }
}
