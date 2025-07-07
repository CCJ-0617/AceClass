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
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Use the shared player directly from appState
            if let player = appState.player {
                VideoPlayer(player: player)
                    .onAppear {
                        // The player's lifecycle is managed by AppState, so we don't need to call play() here.
                    }
            } else {
                // Display a loading indicator if a video is selected but the player isn't ready yet
                // Otherwise, show the placeholder text.
                VStack {
                    if appState.currentVideo != nil {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(.circular)
                    } else {
                        Text("請選擇一部影片")
                            .foregroundColor(.white)
                            .padding()
                    }
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
