import AVFoundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor
final class VideoThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()
    private var loadTask: Task<Void, Never>?

    func load(from url: URL) {
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }

        loadTask?.cancel()
        image = nil
        loadTask = Task { [weak self] in
            let generatedImage = await Self.generateThumbnail(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let generatedImage {
                    Self.cache.setObject(generatedImage, forKey: url as NSURL)
                }
                self?.image = generatedImage
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    private static func generateThumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)

            let candidateTimes = [
                CMTime(seconds: 2, preferredTimescale: 600),
                CMTime(seconds: 0.5, preferredTimescale: 600),
                .zero
            ]

            for time in candidateTimes {
                if Task.isCancelled {
                    return nil
                }

                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            }

            return nil
        }.value
    }
}

struct VideoThumbnailView: View {
    let url: URL
    let isPlaying: Bool

    @StateObject private var loader = VideoThumbnailLoader()

    var body: some View {
        ZStack {
            thumbnailBackground

            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.30),
                        Color.blue.opacity(0.18),
                        Color.black.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "film")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.05),
                            Color.black.opacity(0.20),
                            Color.black.opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial.opacity(0.92))
                    .frame(width: 28, height: 28)

                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                    .offset(x: isPlaying ? 0 : 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isPlaying ? 0.34 : 0.16))
        )
        .task(id: url) {
            loader.load(from: url)
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var thumbnailBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill((isPlaying ? Color.accentColor : Color.secondary).opacity(0.12))
    }
}
