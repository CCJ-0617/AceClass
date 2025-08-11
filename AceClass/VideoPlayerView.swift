//
//  VideoPlayerView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

// MARK: - AppKit-backed Player View (to avoid _AVKit_SwiftUI runtime issues)
#if os(macOS)
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = false
        view.updatesNowPlayingInfoCenter = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
#endif

// 1. 用於右側欄位的標準影片播放器
struct VideoPlayerView: View {
    @ObservedObject var appState: AppState
    @Binding var isFullScreen: Bool
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Use the shared player directly from appState
            if let player = appState.player {
#if os(macOS)
                AVPlayerViewRepresentable(player: player)
                    .frame(minWidth: 1, minHeight: 1)
#else
                VideoPlayer(player: player)
                    .frame(minWidth: 1, minHeight: 1)
#endif
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
            
            // 字幕顯示層（置於播放器上方）
            if let player = appState.player, appState.showCaptions, appState.captionsFeatureEnabled {
                if !appState.captionsForCurrentVideo.isEmpty {
                    CaptionOverlayView(player: player, segments: appState.captionsForCurrentVideo)
                        .allowsHitTesting(false)
                        .padding(.bottom, 38)
                } else if appState.captionLoading {
                    VStack { Spacer(); Text("字幕載入中…")
                            .font(.custom("Songti TC", size: 16).weight(.semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 50)
                    }.allowsHitTesting(false)
                } else if let err = appState.captionError {
                    VStack { Spacer(); Text(err.isEmpty ? "字幕不可用" : err)
                            .font(.custom("Songti TC", size: 16).weight(.semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 50)
                    }.allowsHitTesting(false)
                } else {
                    // Captions enabled but empty and not loading -> show unavailable
                    VStack { Spacer(); Text("字幕不可用")
                            .font(.custom("Songti TC", size: 16).weight(.semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 50)
                    }.allowsHitTesting(false)
                }
            }
            
            // 控制按鈕群
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
            
            // 字幕開關
            if appState.captionsFeatureEnabled {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Toggle(isOn: $appState.showCaptions) {
                            Image(systemName: appState.showCaptions ? "captions.bubble.fill" : "captions.bubble")
                                .foregroundColor(.white)
                        }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .padding(.trailing, 56)
                        .padding(.bottom, 10)
                    }
                }
            }
            
            // Resume overlay text
            if let overlay = appState.resumeOverlayText {
                VStack { Spacer(); HStack { Spacer(); Text(overlay)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                }}.transition(.opacity).animation(.easeInOut(duration: 0.3), value: appState.resumeOverlayText)
            }
        }
    }
}

// 2. 用於全螢幕模式的影片播放器 (top-level)
struct FullScreenVideoPlayerView: View {
    let player: AVPlayer
    let onToggleFullScreen: () -> Void
    var showCaptions: Bool = false
    var captionSegments: [CaptionSegment] = []
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.edgesIgnoringSafeArea(.all)
#if os(macOS)
            AVPlayerViewRepresentable(player: player).frame(minWidth: 1, minHeight: 1)
#else
            VideoPlayer(player: player).frame(minWidth: 1, minHeight: 1)
#endif
            if showCaptions {
                CaptionOverlayView(player: player, segments: captionSegments).allowsHitTesting(false)
            }
            Button(action: onToggleFullScreen) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.35).background(.thinMaterial).clipShape(Circle()))
                    .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
}

// MARK: - Caption Overlay (top-level)
struct CaptionOverlayView: View {
    let player: AVPlayer
    let segments: [CaptionSegment]
    @State private var currentText: String = ""
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            Spacer()
            if !currentText.isEmpty {
                Text(currentText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
            }
        }
        .onReceive(timer) { _ in updateText() }
    }
    
    private func updateText() {
        guard let item = player.currentItem else { return }
        let time = CMTimeGetSeconds(item.currentTime())
        if let seg = segments.first(where: { time >= $0.start && time <= ($0.start + $0.duration) }) {
            if seg.text != currentText { currentText = seg.text }
        } else if !currentText.isEmpty {
            currentText = ""
        }
    }
}
