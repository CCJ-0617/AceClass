//
//  VideoRowView.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI

struct VideoRowView: View {
    @Binding var video: VideoItem
    let isPlaying: Bool
    let playAction: () async -> Void
    let saveAction: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: play) {
                    ZStack {
                        Circle()
                            .fill((isPlaying ? Color.accentColor : .blue).opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: isPlaying ? "speaker.wave.2.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(isPlaying ? Color.accentColor : .blue)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("影片標題", text: $video.displayName)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .onChange(of: video.displayName) { _, _ in
                            save()
                        }

                    if !video.fileName.isEmpty {
                        Text(video.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 12)

                Button(action: toggleWatched) {
                    Label(video.watchStatusText, systemImage: video.watched ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(video.watched ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            FlowMetadataRow(items: metadataItems)

            TextField("筆記 / 學習重點", text: $video.note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onChange(of: video.note) { _, _ in
                    save()
                }
        }
        .padding(16)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor)
        )
    }

    private var metadataItems: [MetadataChipItem] {
        var items = [MetadataChipItem(title: video.fileTypeLabel, systemImage: "film", tint: .indigo)]

        if let formattedDateText = video.formattedDateText {
            items.append(MetadataChipItem(title: formattedDateText, systemImage: "calendar", tint: .blue))
        }

        if let playbackPositionText = video.playbackPositionText {
            items.append(MetadataChipItem(title: playbackPositionText, systemImage: "clock.arrow.circlepath", tint: .teal))
        }

        if let noteSummary = video.noteSummary {
            items.append(MetadataChipItem(title: noteSummary, systemImage: "note.text", tint: .orange))
        }

        return items
    }

    private var backgroundColor: Color {
        isPlaying ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05)
    }

    private var borderColor: Color {
        (isPlaying ? Color.accentColor : Color.secondary).opacity(isPlaying ? 0.30 : 0.10)
    }

    private func play() {
        Task {
            await playAction()
        }
    }

    private func toggleWatched() {
        Task {
            video.watched.toggle()
            await saveAction()
        }
    }

    private func save() {
        Task {
            await saveAction()
        }
    }
}
