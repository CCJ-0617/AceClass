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

                if appState.isInitializingPlayer {
                    playerLoadingOverlay
                        .padding(24)
                        .transition(.opacity)
                }
            } else {
                playerPlaceholder
            }
            
            // 字幕顯示層（置於播放器上方）
            if let player = appState.player, appState.showCaptions, appState.captionsFeatureEnabled {
                if !appState.captionsForCurrentVideo.isEmpty {
                    CaptionOverlayView(player: player, segments: appState.captionsForCurrentVideo)
                        .allowsHitTesting(false)
                        .padding(.bottom, 38)
                } else if appState.captionLoading {
                    VStack { Spacer(); Text(L10n.tr("player.captions_loading"))
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
                    VStack { Spacer(); Text(err.isEmpty ? L10n.tr("player.captions_unavailable") : err)
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
                    VStack { Spacer(); Text(L10n.tr("player.captions_unavailable"))
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

    private var playerPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color.accentColor.opacity(0.18),
                    Color.black.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.18))
            }

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 84, height: 84)

                    Image(systemName: placeholderIconName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                }

                VStack(spacing: 10) {
                    Text(placeholderTitle)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(placeholderSubtitle)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }

                if appState.currentVideo != nil {
                    playerLoadingCard
                        .frame(maxWidth: 520)
                }
            }
            .padding(32)
        }
        .ignoresSafeArea()
    }

    private var playerLoadingOverlay: some View {
        VStack {
            Spacer()

            playerLoadingCard
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var playerLoadingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill((isLoadingFailure ? Color.red : Color.accentColor).opacity(0.18))
                        .frame(width: 48, height: 48)

                    if isLoadingFailure {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.92)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.playerLoadingTitle ?? L10n.tr("player.loading.video"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    if let video = appState.currentVideo {
                        Text(video.resolvedTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(2)
                    }

                    if let detail = appState.playerLoadingDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.white.opacity(0.9), Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 6)

                HStack(spacing: 8) {
                    statusChip(icon: "externaldrive.fill.badge.checkmark", text: L10n.tr("player.status.check_source"))
                    statusChip(icon: "play.rectangle.on.rectangle", text: L10n.tr("player.status.create_player"))
                    if let resumeText = appState.currentVideo?.playbackPositionText {
                        statusChip(icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", text: resumeText)
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24))
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 12)
    }

    private func statusChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.84))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private var placeholderIconName: String {
        if isLoadingFailure {
            return "exclamationmark.triangle.fill"
        }
        if appState.currentVideo != nil {
            return "play.circle.fill"
        }
        return "film.stack"
    }

    private var placeholderTitle: String {
        if appState.currentVideo != nil {
            return appState.playerLoadingTitle ?? L10n.tr("player.loading.video")
        }
        return L10n.tr("player.placeholder.select_video")
    }

    private var placeholderSubtitle: String {
        if let detail = appState.playerLoadingDetail, !detail.isEmpty {
            return detail
        }
        if let video = appState.currentVideo {
            return L10n.tr("player.placeholder.loading_subtitle", video.resolvedTitle)
        }
        return L10n.tr("player.placeholder.idle_subtitle")
    }

    private var isLoadingFailure: Bool {
        guard let title = appState.playerLoadingTitle else { return false }
        return title == L10n.tr("player.loading.failed") || title == L10n.tr("player.loading.unable")
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
