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
        view.showsFullScreenToggleButton = false
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

    private struct LoadingCheckpoint: Identifiable {
        enum Status {
            case done
            case active
            case pending
            case failed
        }

        let stage: AppState.PlayerLoadingStage
        let icon: String
        let title: String
        let status: Status

        var id: AppState.PlayerLoadingStage { stage }
    }

    private let loadingOverlayAnimation = Animation.smooth(duration: 0.20)
    private let selectionAnimation = Animation.smooth(duration: 0.18)
    private let loadingOverlayTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.985))
    private let resumeOverlayTransition = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Use the shared player directly from appState
            if let player = appState.player {
#if os(macOS)
                AVPlayerViewRepresentable(player: player)
                    .frame(minWidth: 1, minHeight: 1)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
#else
                VideoPlayer(player: player)
                    .frame(minWidth: 1, minHeight: 1)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
#endif

                Group {
                    if appState.isInitializingPlayer {
                        playerLoadingOverlay
                            .padding(24)
                            .transition(loadingOverlayTransition)
                    }
                }
                .animation(loadingOverlayAnimation, value: appState.isInitializingPlayer)
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
                isFullScreen.toggle()
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
            Group {
                if let overlay = appState.resumeOverlayText {
                    VStack { Spacer(); HStack { Spacer(); Text(overlay)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                    }}
                    .transition(resumeOverlayTransition)
                }
            }
            .animation(selectionAnimation, value: appState.resumeOverlayText)
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
                        .font(.system(size: 26, weight: .bold))
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(loadingTint.opacity(0.18))
                        .frame(width: 54, height: 54)

                    Circle()
                        .strokeBorder(loadingTint.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 54, height: 54)

                    if isLoadingFailure {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.white)
                            .scaleEffect(0.92)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
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
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 0)

                Text(loadingProgressText)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("player.loading.auto_play_hint"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.74))
                    Spacer(minLength: 12)
                    if let resumeText = appState.currentVideo?.playbackPositionText {
                        Label(resumeText, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.09))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [loadingTint.opacity(0.95), Color.white.opacity(0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(18, proxy.size.width * loadingProgressValue))
                            .shadow(color: loadingTint.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
                }
                .frame(height: 10)

                HStack(spacing: 10) {
                    ForEach(loadingCheckpoints) { checkpoint in
                        loadingCheckpointCard(checkpoint)
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 12)
    }

    private func loadingCheckpointCard(_ checkpoint: LoadingCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: checkpoint.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(checkpointAccent(for: checkpoint.status))

                Spacer(minLength: 0)

                Circle()
                    .fill(checkpointAccent(for: checkpoint.status))
                    .frame(width: 8, height: 8)
            }

            Text(checkpoint.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(checkpoint.status == .pending ? 0.58 : 0.88))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(checkpointBackground(for: checkpoint.status))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(checkpointAccent(for: checkpoint.status).opacity(0.24))
        )
    }

    private var loadingTint: Color {
        isLoadingFailure ? .red : .accentColor
    }

    private var loadingProgressValue: Double {
        min(max(appState.playerLoadingProgress, appState.currentVideo == nil ? 0 : 0.08), 1)
    }

    private var loadingProgressText: String {
        "\(Int((loadingProgressValue * 100).rounded()))%"
    }

    private var loadingCheckpoints: [LoadingCheckpoint] {
        var specs: [(AppState.PlayerLoadingStage, String, String)] = [
            (.preparing, "sparkles", L10n.tr("player.status.prepare")),
            (.checkingSource, "externaldrive.fill.badge.checkmark", L10n.tr("player.status.check_source"))
        ]

        if appState.enableVideoCaching || appState.playerLoadingStage == .checkingCache {
            specs.append((.checkingCache, "internaldrive.fill.badge.checkmark", L10n.tr("player.status.check_cache")))
        }

        specs.append((.creatingPlayer, "play.rectangle.on.rectangle", L10n.tr("player.status.create_player")))

        return specs.map { stage, icon, title in
            let status: LoadingCheckpoint.Status

            if appState.playerLoadingDidFail {
                if stage.rawValue < appState.playerLoadingStage.rawValue {
                    status = .done
                } else if stage == appState.playerLoadingStage {
                    status = .failed
                } else {
                    status = .pending
                }
            } else if appState.playerLoadingStage == .ready {
                status = .done
            } else if stage.rawValue < appState.playerLoadingStage.rawValue {
                status = .done
            } else if stage == appState.playerLoadingStage {
                status = .active
            } else {
                status = .pending
            }

            return LoadingCheckpoint(stage: stage, icon: icon, title: title, status: status)
        }
    }

    private func checkpointAccent(for status: LoadingCheckpoint.Status) -> Color {
        switch status {
        case .done:
            return Color.green.opacity(0.92)
        case .active:
            return loadingTint
        case .pending:
            return Color.white.opacity(0.34)
        case .failed:
            return Color.red.opacity(0.95)
        }
    }

    private func checkpointBackground(for status: LoadingCheckpoint.Status) -> Color {
        switch status {
        case .done:
            return Color.green.opacity(0.10)
        case .active:
            return loadingTint.opacity(0.14)
        case .pending:
            return Color.white.opacity(0.05)
        case .failed:
            return Color.red.opacity(0.14)
        }
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
        appState.playerLoadingDidFail
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
            AVPlayerViewRepresentable(player: player)
                .frame(minWidth: 1, minHeight: 1)
                .transaction { transaction in
                    transaction.animation = nil
                }
#else
            VideoPlayer(player: player)
                .frame(minWidth: 1, minHeight: 1)
                .transaction { transaction in
                    transaction.animation = nil
                }
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
                    .font(.system(size: 16, weight: .semibold))
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
