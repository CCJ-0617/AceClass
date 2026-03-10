import Foundation
import AVFoundation

final class PlaybackCompatibilityManager {
    static let shared = PlaybackCompatibilityManager()

    private init() {
        loadManifest()
    }

    private final class UncheckedSendableBox<Value>: @unchecked Sendable {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    enum PlaybackCompatibilityError: LocalizedError {
        case ffmpegNotInstalled
        case conversionFailed(String)
        case outputNotPlayable

        var errorDescription: String? {
            switch self {
            case .ffmpegNotInstalled:
                return L10n.tr("player.loading.ffmpeg_missing")
            case let .conversionFailed(detail):
                return detail.isEmpty
                    ? L10n.tr("player.loading.compatibility_failed")
                    : L10n.tr("player.loading.compatibility_failed_detail", detail)
            case .outputNotPlayable:
                return L10n.tr("player.loading.compatibility_output_unplayable")
            }
        }
    }

    private struct Entry: Codable {
        let originalPath: String
        let compatibleFileName: String
        let fileSize: Int64
        let modTime: TimeInterval
        var lastAccess: TimeInterval
    }

    private let fm = FileManager.default
    private lazy var compatibilityDir: URL = {
        let base = LocalMetadataStorage.baseDirectory.appendingPathComponent("Cache/PlaybackCompatibility", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }()
    private var manifestURL: URL {
        compatibilityDir.appendingPathComponent("PlaybackCompatibilityManifest.json")
    }
    private let queue = DispatchQueue(label: "aceclass.playbackcompatibility", qos: .utility)
    private var manifest: [String: Entry] = [:]
    private var inFlightConversions: Set<String> = []
    private var inFlightContinuations: [String: [CheckedContinuation<URL, Error>]] = [:]

    static func requiresCompatibilityCopy(for url: URL) -> Bool {
        url.pathExtension.lowercased() == "mkv"
    }

    static func ffmpegExecutableURL() throws -> URL {
        let fm = FileManager.default
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let candidatePaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ] + envPaths.map { "\($0)/ffmpeg" }

        for candidatePath in candidatePaths {
            guard !candidatePath.isEmpty, fm.isExecutableFile(atPath: candidatePath) else { continue }
            return URL(fileURLWithPath: candidatePath)
        }

        throw PlaybackCompatibilityError.ffmpegNotInstalled
    }

    static func isNativelyPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            return try await asset.load(.isPlayable)
        } catch {
            return false
        }
    }

    func preparePlayableURL(for original: URL) async throws -> URL {
        guard Self.requiresCompatibilityCopy(for: original) else { return original }
        if await Self.isNativelyPlayable(original) {
            return original
        }

        let attrs = try fm.attributesOfItem(atPath: original.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modDate = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        let key = original.standardizedFileURL.resolvingSymlinksInPath().path

        let cachedHit: URL? = queue.sync {
            guard let entry = manifest[key],
                  entry.fileSize == size,
                  abs(entry.modTime - modDate.timeIntervalSince1970) < 1 else { return nil }
            let cachedURL = compatibilityDir.appendingPathComponent(entry.compatibleFileName)
            guard fm.fileExists(atPath: cachedURL.path) else {
                manifest.removeValue(forKey: key)
                saveManifest()
                return nil
            }
            var updated = entry
            updated.lastAccess = Date().timeIntervalSince1970
            manifest[key] = updated
            saveManifest()
            return cachedURL
        }

        if let cachedHit {
            ACLog("Compatibility cache hit for: \(original.lastPathComponent)", level: .debug)
            return cachedHit
        }

        let shouldWait: Bool = queue.sync {
            if inFlightConversions.contains(key) {
                return true
            }
            inFlightConversions.insert(key)
            return false
        }

        if shouldWait {
            ACLog("Waiting for in-flight MKV compatibility conversion: \(original.lastPathComponent)", level: .debug)
            return try await withCheckedThrowingContinuation { continuation in
                let box = UncheckedSendableBox(self)
                queue.async {
                    box.value.inFlightContinuations[key, default: []].append(continuation)
                }
            }
        }

        let ffmpegURL = try Self.ffmpegExecutableURL()
        let outputFileName = compatibilityFileName(for: original, size: size, modDate: modDate)
        let outputURL = compatibilityDir.appendingPathComponent(outputFileName)

        do {
            try await Self.createCompatibleCopy(
                inputURL: original,
                outputURL: outputURL,
                ffmpegURL: ffmpegURL
            )
        } catch {
            let waiters: [CheckedContinuation<URL, Error>] = queue.sync {
                inFlightConversions.remove(key)
                return inFlightContinuations.removeValue(forKey: key) ?? []
            }
            for waiter in waiters {
                waiter.resume(throwing: error)
            }
            throw error
        }

        let entry = Entry(
            originalPath: key,
            compatibleFileName: outputFileName,
            fileSize: size,
            modTime: modDate.timeIntervalSince1970,
            lastAccess: Date().timeIntervalSince1970
        )

        let waiters: [CheckedContinuation<URL, Error>] = queue.sync {
            manifest[key] = entry
            saveManifest()
            inFlightConversions.remove(key)
            return inFlightContinuations.removeValue(forKey: key) ?? []
        }
        for waiter in waiters {
            waiter.resume(returning: outputURL)
        }

        return outputURL
    }

    private func compatibilityFileName(for original: URL, size: Int64, modDate: Date) -> String {
        let base = original.deletingPathExtension().lastPathComponent
        let stamp = Int(modDate.timeIntervalSince1970)
        return "\(base)_\(stamp)_\(size)_compatible.mp4"
    }

    private static func createCompatibleCopy(inputURL: URL, outputURL: URL, ffmpegURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        ACLog("Preparing MKV compatibility copy: \(inputURL.lastPathComponent)", level: .info)

        do {
            try await runFFmpeg(
                executableURL: ffmpegURL,
                arguments: remuxArguments(inputURL: inputURL, outputURL: outputURL)
            )
        } catch {
            ACLog("MKV remux failed, retrying with transcode: \(error.localizedDescription)", level: .warn)
            try? FileManager.default.removeItem(at: outputURL)
            do {
                try await runFFmpeg(
                    executableURL: ffmpegURL,
                    arguments: transcodeArguments(inputURL: inputURL, outputURL: outputURL, videoCodec: "h264_videotoolbox")
                )
            } catch {
                ACLog("VideoToolbox transcode failed, retrying with libx264: \(error.localizedDescription)", level: .warn)
                try? FileManager.default.removeItem(at: outputURL)
                try await runFFmpeg(
                    executableURL: ffmpegURL,
                    arguments: transcodeArguments(inputURL: inputURL, outputURL: outputURL, videoCodec: "libx264")
                )
            }
        }

        guard await isNativelyPlayable(outputURL) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw PlaybackCompatibilityError.outputNotPlayable
        }

        ACLog("Prepared MKV compatibility copy: \(outputURL.lastPathComponent)", level: .info)
    }

    private static func remuxArguments(inputURL: URL, outputURL: URL) -> [String] {
        [
            "-y",
            "-v", "error",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-dn",
            "-sn",
            "-c", "copy",
            "-movflags", "+faststart",
            outputURL.path
        ]
    }

    private static func transcodeArguments(inputURL: URL, outputURL: URL, videoCodec: String) -> [String] {
        [
            "-y",
            "-v", "error",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-dn",
            "-sn",
            "-c:v", videoCodec,
            "-allow_sw", "1",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "160k",
            "-movflags", "+faststart",
            outputURL.path
        ]
    }

    private static func runFFmpeg(executableURL: URL, arguments: [String]) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                throw PlaybackCompatibilityError.conversionFailed(error.localizedDescription)
            }

            process.waitUntilExit()

            let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let detail = summarizeFFmpegOutput(stdout: stdoutText, stderr: stderrText)

            guard process.terminationStatus == 0 else {
                throw PlaybackCompatibilityError.conversionFailed(detail)
            }
        }.value
    }

    private static func summarizeFFmpegOutput(stdout: String, stderr: String) -> String {
        let merged = [stderr, stdout]
            .joined(separator: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return merged.last ?? ""
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            manifest = decoded
        }
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
