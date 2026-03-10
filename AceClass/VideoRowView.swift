//
//  VideoRowView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI

struct VideoRowView: View {
    @Binding var video: VideoItem
    let videoURL: URL
    let isPlaying: Bool
    let changeAction: () -> Void
    let playAction: () async -> Void
    let saveAction: () async -> Void
    @FocusState private var isTitleFieldFocused: Bool
    @State private var isEditingTitle = false

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                cardContent
                    .padding(18)
                    .background(cardAccentWash)
                    .clipShape(cardShape)
                    .glassEffect(rowGlass, in: cardShape)
                    .overlay(
                        cardShape
                            .strokeBorder(Color.white.opacity(isPlaying ? 0.30 : 0.16))
                    )
            }
        } else {
            legacyCard
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                playControl

                VStack(alignment: .leading, spacing: 8) {
                    titleView

                    if !video.fileName.isEmpty {
                        Text(video.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                watchedControl
                    .fixedSize()
            }

            FlowMetadataRow(items: metadataItems)
        }
    }

    private var legacyCard: some View {
        cardContent
        .padding(16)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor)
        )
    }

    @ViewBuilder
    private var playControl: some View {
        Button(action: play) {
            VideoThumbnailView(url: videoURL, isPlaying: isPlaying)
                .frame(width: 108, height: 62)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var watchedControl: some View {
        if #available(macOS 26.0, *) {
            Button(action: toggleWatched) {
                Label(video.watchStatusText, systemImage: video.watched ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(video.watched ? .green : .primary)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
        } else {
            Button(action: toggleWatched) {
                Label(video.watchStatusText, systemImage: video.watched ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(video.watched ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var metadataItems: [MetadataChipItem] {
        var items = [MetadataChipItem(title: video.fileTypeLabel, systemImage: "film", tint: .indigo)]

        if let formattedDateText = video.formattedDateText {
            items.append(MetadataChipItem(title: formattedDateText, systemImage: "calendar", tint: .blue))
        }

        if let playbackPositionText = video.playbackPositionText {
            items.append(MetadataChipItem(title: playbackPositionText, systemImage: "clock.arrow.circlepath", tint: .teal))
        }

        return items
    }

    private var backgroundColor: Color {
        isPlaying ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05)
    }

    private var borderColor: Color {
        (isPlaying ? Color.accentColor : Color.secondary).opacity(isPlaying ? 0.30 : 0.10)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    private var cardAccentWash: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.18),
                isPlaying ? Color.accentColor.opacity(0.12) : Color.clear,
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @available(macOS 26.0, *)
    private var rowGlass: Glass {
        let tint = isPlaying ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.08)
        return Glass.regular.tint(tint).interactive()
    }

    private var liquidGlassBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.cyan.opacity(isPlaying ? 0.18 : 0.10),
                                Color.blue.opacity(isPlaying ? 0.20 : 0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.14),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 120
                        )
                    )
                    .frame(width: 170, height: 170)
                    .offset(x: -32, y: -58)
                    .blur(radius: 4)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(isPlaying ? 0.20 : 0.10),
                                Color.blue.opacity(isPlaying ? 0.18 : 0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 110
                        )
                    )
                    .frame(width: 150, height: 150)
                    .offset(x: 36, y: 44)
                    .blur(radius: 10)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isPlaying ? 0.24 : 0.16), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.10),
                                Color.cyan.opacity(isPlaying ? 0.30 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .padding(1)
            }
            .shadow(color: Color.white.opacity(0.14), radius: 1, y: -1)
    }

    private func play() {
        Task {
            await playAction()
        }
    }

    private func toggleWatched() {
        Task {
            video.watched.toggle()
            changeAction()
            await saveAction()
        }
    }

    private func save() {
        Task {
            await saveAction()
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField(L10n.tr("video.title_placeholder"), text: $video.displayName)
                .font(.headline)
                .textFieldStyle(.plain)
                .focused($isTitleFieldFocused)
                .onChange(of: video.displayName) { _, _ in
                    changeAction()
                    save()
                }
                .onChange(of: isTitleFieldFocused) { _, focused in
                    if !focused {
                        isEditingTitle = false
                    }
                }
                .onSubmit {
                    finishTitleEditing()
                }
        } else {
            HoverMarqueeText(text: video.resolvedTitle, font: .headline)
                .help(video.resolvedTitle)
                .onTapGesture {
                    beginTitleEditing()
                }
        }
    }

    private func beginTitleEditing() {
        isEditingTitle = true

        DispatchQueue.main.async {
            isTitleFieldFocused = true
        }
    }

    private func finishTitleEditing() {
        isTitleFieldFocused = false
        isEditingTitle = false
    }
}
