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
    @ObservedObject var appState: AppState
    @Binding var isFullScreen: Bool
    
    // 將 player 設為此 View 的狀態，由 appState 的 videoURL 驅動
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        // 當 View 消失時（例如切換課程），暫停播放
                        player.pause()
                    }
            } else {
                // 沒有選擇影片時的預留位置
                VStack {
                    Text("請選擇一部影片")
                        .foregroundColor(.white)
                        .padding()
                    Spacer()
                }
                .background(Color.black)
                .edgesIgnoringSafeArea(.all)
            }

            // 全螢幕切換按鈕
            Button(action: {
                withAnimation {
                    isFullScreen.toggle()
                }
            }) {
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
        .onChange(of: appState.currentVideoURL) { _, newURL in
            // 使用異步調用確保不會在視圖更新期間修改狀態
            DispatchQueue.main.async {
                if let url = newURL {
                    // 當 AppState 中的 URL 變更時，建立新的播放器
                    self.player = AVPlayer(url: url)
                    self.player?.play()
                } else {
                    // 如果 URL 為 nil，則清空播放器
                    self.player = nil
                }
            }
        }
        .onAppear {
            // 當 View 首次出現時，根據當前的 URL 初始化播放器
            DispatchQueue.main.async {
                if let url = appState.currentVideoURL {
                    self.player = AVPlayer(url: url)
                } else {
                    self.player = nil
                }
            }
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
    }
}
