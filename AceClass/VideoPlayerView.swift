//
//  VideoPlayerView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI
import AVKit

// 1. 用於右側欄位的標準影片播放器
struct VideoPlayerView: View {
    let player: AVPlayer
    let onToggleFullScreen: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VideoPlayer(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // 全螢幕切換按鈕
            Button(action: onToggleFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        Color.black.opacity(0.35)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    )
                    .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
}

// 2. 用於全螢幕模式的影片播放器
struct FullScreenVideoPlayerView: View {
    let player: AVPlayer
    let onToggleFullScreen: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 播放器背景設為黑色並忽略安全區域
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            VideoPlayer(player: player)

            // 退出全螢幕按鈕
            Button(action: onToggleFullScreen) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        Color.black.opacity(0.35)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    )
                    .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
        // 增加過渡動畫
        .transition(.opacity.animation(.easeInOut))
    }
}
