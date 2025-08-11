@preconcurrency import AVFoundation
import Foundation
import Speech
import NaturalLanguage

final class LocalTranscriptionService {
    static let shared = LocalTranscriptionService()
    private init() {}
    
    private struct LSeg { let locale: String; let seg: CaptionSegment }
    
    private let maxSegmentDuration: Double = 300 // 5 minutes per chunk
    private let segmentOverlap: Double = 0.5
    private let longAudioThreshold: Double = 600 // 10 min for poor-result segmentation fallback
    private let minSegmentCountForLong: Int = 40
    // NEW: Force direct segmentation without whole-file attempt beyond this length
    private let forceSegmentationDuration: Double = 900 // 15 min
    // NEW: Limit how much audio we fully decode for analysis (avoid huge memory)
    private let maxPCMAnalysisDuration: Double = 120 // seconds
    // NEW: per recognition attempt timeout
    private let recognitionTimeout: UInt64 = 180 * 1_000_000_000 // 180s
    
    private var audioExtractionCache: [URL: URL] = [:]
    private var audioAnalysisCache: [URL: AudioAnalysis] = [:]
    
    private var allowCloudFallback: Bool = true
    func setAllowCloudFallback(_ flag: Bool) { allowCloudFallback = flag }
    
    private var currentTranscriptionTask: Task<[CaptionSegment], Error>? {
        didSet { oldValue?.cancel() }
    }
    func cancelOngoingTranscription() { currentTranscriptionTask?.cancel(); currentTranscriptionTask = nil }
    
    private struct AudioAnalysis { let duration: Double; let fileSize: Int64; let averageRMS: Double; let leadingSilence: Double; let url: URL }
    
    // MARK: - Locale Helpers
    private func onDeviceCapableLocales(from locales: [String]) -> [String] {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.lowercased() })
        var result: [String] = []
        var seen: Set<String> = []
        for id in locales {
            let low = id.lowercased()
            guard supported.contains(low) else { continue }
            guard let r = SFSpeechRecognizer(locale: Locale(identifier: id)) else { continue }
            if #available(macOS 12.0, iOS 13.0, *) { guard r.supportsOnDeviceRecognition else { continue } }
            if !seen.contains(low) { result.append(id); seen.insert(low) }
        }
        return result
    }
    private func supportedLocales(from locales: [String]) -> [String] {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.lowercased() })
        var out: [String] = []
        var seen: Set<String> = []
        for id in locales {
            let low = id.lowercased(); guard supported.contains(low) else { continue }
            if !seen.contains(low) { out.append(id); seen.insert(low) }
        }
        return out
    }
    
    // MARK: Authorization
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
    }
    
    // MARK: Public Multilingual Entry (sequential + analysis)
    func transcribe(url: URL, locales: [String]) async throws -> [CaptionSegment] {
        // Cancel any prior task and replace with new one
        let task = Task<[CaptionSegment], Error> { [weak self] in
            guard let self else { return [] }
            if Task.isCancelled { return [] }
            let requested = locales.isEmpty ? [Locale.current.identifier] : locales
            let chosenLocales = allowCloudFallback ? supportedLocales(from: requested) : onDeviceCapableLocales(from: requested)
            guard !chosenLocales.isEmpty else {
                throw NSError(domain: "LocalTranscription", code: -3, userInfo: [NSLocalizedDescriptionKey: allowCloudFallback ? "無可用支援語系" : "無可用離線語系，且未啟用雲端 fallback"]) }
            ACLog("SPEECH Requested locales=\(requested) -> using=\(chosenLocales) allowCloud=\(allowCloudFallback) sequential=true", level: .debug)
            var preparedOpt: AudioAnalysis? = nil
            do {
                preparedOpt = try await prepareAudio(url: url)
                if let p = preparedOpt {
                    ACLog("AUDIO duration=\(String(format: "%.2f", p.duration))s size=\(p.fileSize)B avgRMS=\(String(format: "%.1f", p.averageRMS))dBFS leadingSilence=\(String(format: "%.2f", p.leadingSilence))s", level: .debug)
                    // NEW: explicit debug for original and prepared audio
                    self.debugAudioFile(url, label: "original.container after prepareAudio")
                    self.debugAudioFile(p.url, label: "prepared.pcm after prepareAudio")
                }
            } catch {
                ACLog("AUDIO prepareAudio failed, fallback to original container: \(error.localizedDescription)", level: .warn)
            }
            var all: [(String, [CaptionSegment])] = []
            for loc in chosenLocales { if Task.isCancelled { break }
                do {
                    let segs = try await transcribeSingleAudio(originalURL: url, prepared: preparedOpt, locale: loc)
                    all.append((loc, segs))
                } catch {
                    ACLog("SPEECH locale \(loc) failed: \(error.localizedDescription)", level: .warn)
                }
            }
            if Task.isCancelled { return [] }
            return mergeSegmentsByLanguage(all.map { ($0.0, $0.1) })
        }
        currentTranscriptionTask = task
        return try await task.value
    }
    
    // MARK: Single-locale transcription with improved fallback ordering
    private func transcribeSingleAudio(originalURL: URL, prepared: AudioAnalysis?, locale: String) async throws -> [CaptionSegment] {
        if Task.isCancelled { return [] }
        
        // Force segmentation immediately for ultra-long audio
        if let prepared = prepared, prepared.duration >= forceSegmentationDuration {
            ACLog("SPEECH force segmentation duration=\(String(format: "%.1f", prepared.duration)) locale=\(locale)", level: .debug)
            let segmented = try await transcribeSegmented(locale: locale, analysis: prepared)
            if !segmented.isEmpty { return segmented }
            // If segmentation produced nothing, fall through to whole-file attempts (unlikely)
        }
        
        debugAudioFile(originalURL, label: "pre-attempt original locale=\(locale)")
        if let prepared = prepared { debugAudioFile(prepared.url, label: "pre-attempt prepared(locale=\(locale))") }
        
        func attempt(_ url: URL, stage: String) async -> Result<[CaptionSegment], Error> {
            debugAudioFile(url, label: "attempt.stage=\(stage) locale=\(locale)")
            do { let segs = try await runRecognizerWithTimeout(url: url, localeIdentifier: locale, stage: stage); return .success(segs) } catch { return .failure(error) }
        }
        
        var lastError: Error? = nil
        var wholeFileResult: [CaptionSegment] = []
        
        switch await attempt(originalURL, stage: "original") {
        case .success(let segs): wholeFileResult = segs
        case .failure(let e1):
            lastError = e1
            let ns1 = e1 as NSError
            if let prepared = prepared {
                switch await attempt(prepared.url, stage: "prepared") {
                case .success(let segs): wholeFileResult = segs
                case .failure(let e2):
                    lastError = e2
                    let ns2 = e2 as NSError
                    if (e2.localizedDescription.contains("No speech") || ns2.code == 203) && prepared.duration > 15 && prepared.leadingSilence > 0.5 {
                        let trimStart = max(0, prepared.leadingSilence - 0.2)
                        ACLog("SPEECH trim retry locale=\(locale) trimStart=\(String(format: "%.2f", trimStart))", level: .debug)
                        if let trimmed = try? await trimAudio(prepared.url, start: trimStart) {
                            switch await attempt(trimmed, stage: "trimmed") {
                            case .success(let segs): wholeFileResult = segs.map { CaptionSegment(text: $0.text, start: $0.start + trimStart, duration: $0.duration) }
                            case .failure(let etrim): ACLog("SPEECH trim retry failed locale=\(locale) error=\(etrim.localizedDescription)", level: .warn)
                            }
                        }
                    }
                    if wholeFileResult.isEmpty && (e1.localizedDescription.contains("Cannot Open") || e2.localizedDescription.contains("Cannot Open") || ns1.domain == NSOSStatusErrorDomain || ns2.domain == NSOSStatusErrorDomain) {
                        ACLog("SPEECH fallback m4a export locale=\(locale)", level: .debug)
                        if let m4a = try? await exportToM4A(originalURL) {
                            switch await attempt(m4a, stage: "m4a") {
                            case .success(let segs): wholeFileResult = segs
                            case .failure(let em4a): ACLog("SPEECH m4a fallback failed locale=\(locale) error=\(em4a.localizedDescription)", level: .warn)
                            }
                        }
                    }
                }
            } else {
                if e1.localizedDescription.contains("Cannot Open") || ns1.domain == NSOSStatusErrorDomain {
                    ACLog("SPEECH fallback m4a export (no prepared) locale=\(locale)", level: .debug)
                    if let m4a = try? await exportToM4A(originalURL) {
                        switch await attempt(m4a, stage: "m4a") {
                        case .success(let segs): wholeFileResult = segs
                        case .failure(let em4a): ACLog("SPEECH m4a fallback failed locale=\(locale) error=\(em4a.localizedDescription)", level: .warn)
                        }
                    }
                }
            }
        }
        
        if Task.isCancelled { return [] }
        
        if let prepared = prepared {
            let needSegmentation: Bool = {
                if wholeFileResult.isEmpty { return prepared.duration > 120 }
                if prepared.duration >= longAudioThreshold && wholeFileResult.count < minSegmentCountForLong { return true }
                return false
            }()
            if needSegmentation {
                ACLog("SPEECH segmentation fallback triggered locale=\(locale) existing=\(wholeFileResult.count) duration=\(String(format: "%.1f", prepared.duration))", level: .debug)
                do {
                    let segmented = try await transcribeSegmented(locale: locale, analysis: prepared)
                    if segmented.count > wholeFileResult.count { return segmented }
                    if wholeFileResult.isEmpty && segmented.isEmpty, let lastError = lastError { throw lastError }
                } catch {
                    ACLog("SPEECH segmentation fallback failed locale=\(locale) error=\(error.localizedDescription)", level: .warn)
                    if wholeFileResult.isEmpty, let lastError = lastError { throw lastError }
                }
            }
        }
        return wholeFileResult
    }
    
    // MARK: Prepare audio (Option A: M4A-first export + analysis)
    private func prepareAudio(url: URL) async throws -> AudioAnalysis {
        if let cached = audioAnalysisCache[url], FileManager.default.fileExists(atPath: cached.url.path) { return cached }
    ACLog("AUDIO prepareAudio start for \(url.lastPathComponent)", level: .debug)
        let lowerExt = url.pathExtension.lowercased()
        var baseURL: URL = url
        if !["m4a","caf","wav","aif","aiff"].contains(lowerExt) {
            do { baseURL = try await exportToM4A(url); ACLog("AUDIO exported M4A base=\(baseURL.lastPathComponent)", level: .debug) }
            catch { ACLog("AUDIO M4A export failed, fallback to original container error=\(error.localizedDescription)", level: .warn) }
        }
        debugAudioFile(baseURL, label: "analysis.base start")
    ACLog("AUDIO analyzeAudio start", level: .trace)
        let analysis = try await analyzePCM(url: baseURL)
    ACLog("AUDIO analyzeAudio done rms=\(String(format: "%.1f", analysis.averageRMS)) leading=\(String(format: "%.2f", analysis.leadingSilence)) duration=\(String(format: "%.2f", analysis.duration))", level: .debug)
        audioAnalysisCache[url] = analysis
        return analysis
    }
    
    // NEW: Segmentation + transcription for large or fallback paths
    private func transcribeSegmented(locale: String, analysis: AudioAnalysis) async throws -> [CaptionSegment] {
        let segments = try await segmentAudio(analysis.url, segmentLength: maxSegmentDuration, overlap: segmentOverlap)
    ACLog("SPEECH segment count=\(segments.count) locale=\(locale)", level: .debug)
        var out: [CaptionSegment] = []
        for (segURL, baseStart) in segments {
            if Task.isCancelled { break }
            debugAudioFile(segURL, label: "segment.start offset=\(String(format: "%.2f", baseStart)) locale=\(locale)")
            do {
                let segs = try await runRecognizer(url: segURL, localeIdentifier: locale)
                let adjusted = segs.map { CaptionSegment(text: $0.text, start: $0.start + baseStart, duration: $0.duration) }
                out.append(contentsOf: adjusted)
            } catch {
                ACLog("SPEECH segment failed offset=\(String(format: "%.2f", baseStart)) locale=\(locale) error=\(error.localizedDescription)", level: .warn)
            }
        }
        return coalesceContinuous(out.sorted { $0.start < $1.start })
    }
    
    // Export time-sliced segments (M4A)
    private func segmentAudio(_ url: URL, segmentLength: Double, overlap: Double) async throws -> [(url: URL, start: Double)] {
        let asset = AVURLAsset(url: url)
        let durationCM = try await asset.load(.duration)
        let total = CMTimeGetSeconds(durationCM)
        var results: [(URL, Double)] = []
        var start: Double = 0
        while start < total {
            if Task.isCancelled { break }
            let baseDuration = min(segmentLength, total - start)
            let extra = (start + baseDuration < total) ? overlap : 0
            let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: durationCM.timescale), duration: CMTime(seconds: baseDuration + extra, preferredTimescale: durationCM.timescale))
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw NSError(domain: "LocalTranscription", code: -50, userInfo: [NSLocalizedDescriptionKey: "無法建立分段匯出會話"]) }
            let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + String(format: "_%.0fs.m4a", start))
            try? FileManager.default.removeItem(at: outURL)
            export.timeRange = timeRange
            export.outputURL = outURL
            export.outputFileType = .m4a
            if #available(macOS 15.0, iOS 18.0, *) {
                try await export.export(to: outURL, as: .m4a)
            } else {
                final class Box: @unchecked Sendable { let e: AVAssetExportSession; init(_ e: AVAssetExportSession){ self.e = e } }
                let box = Box(export)
                try await withCheckedThrowingContinuation { cont in
                    box.e.exportAsynchronously {
                        switch box.e.status {
                        case .completed: cont.resume()
                        case .failed, .cancelled: cont.resume(throwing: box.e.error ?? NSError(domain: "LocalTranscription", code: -51, userInfo: [NSLocalizedDescriptionKey: "分段匯出失敗"]))
                        default: break
                        }
                    }
                }
            }
            debugAudioFile(outURL, label: "segment.exported start=\(String(format: "%.2f", start))")
            results.append((outURL, start))
            start += baseDuration
        }
        return results
    }
    
    // Coalesce adjacent identical text segments (single-locale)
    private func coalesceContinuous(_ segments: [CaptionSegment]) -> [CaptionSegment] {
        var out: [CaptionSegment] = []
        for seg in segments {
            if let last = out.last, last.text == seg.text, last.start + last.duration + 0.15 >= seg.start {
                out.removeLast()
                let newDuration = max(last.duration, (seg.start + seg.duration) - last.start)
                out.append(CaptionSegment(text: last.text, start: last.start, duration: newDuration))
            } else { out.append(seg) }
        }
        return out
    }
    
    // Extract linear PCM CAF
    private func extractLinearPCMAudio(url: URL) async throws -> URL {
    ACLog("AUDIO extracting PCM from \(url.lastPathComponent)", level: .trace)
        if ["wav","caf","aif","aiff"].contains(url.pathExtension.lowercased()) { return url }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let firstTrack = tracks.first else { throw NSError(domain: "LocalTranscription", code: -10, userInfo: [NSLocalizedDescriptionKey: "影片沒有可用音訊軌"]) }
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".caf")
        try? FileManager.default.removeItem(at: outURL)
        guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .caf) else { throw NSError(domain: "LocalTranscription", code: -11, userInfo: [NSLocalizedDescriptionKey: "無法建立音訊寫入器"]) }
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16000
        ]
        let fds = try await firstTrack.load(.formatDescriptions)
        let sourceFormat = fds.first // Direct optional; avoid redundant cast warning
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: pcmSettings, sourceFormatHint: sourceFormat)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw NSError(domain: "LocalTranscription", code: -12, userInfo: [NSLocalizedDescriptionKey: "無法添加寫入輸入"]) }
        writer.add(input)
        let reader = try AVAssetReader(asset: asset)
        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16000
        ]
        let output = AVAssetReaderTrackOutput(track: firstTrack, outputSettings: readerOutputSettings)
        guard reader.canAdd(output) else { throw NSError(domain: "LocalTranscription", code: -13, userInfo: [NSLocalizedDescriptionKey: "無法添加讀取輸出"]) }
        reader.add(output)
        writer.startWriting(); reader.startReading(); writer.startSession(atSourceTime: .zero)
        return try await withCheckedThrowingContinuation { cont in
            let queue = DispatchQueue(label: "pcm.extract")
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                        if !input.append(sample) { reader.cancelReading(); input.markAsFinished(); break }
                    } else { input.markAsFinished(); break }
                }
                if reader.status == .completed {
                    writer.finishWriting { cont.resume(returning: outURL) }
                } else if reader.status == .failed || reader.status == .cancelled {
                    let err = reader.error ?? writer.error ?? NSError(domain: "LocalTranscription", code: -14, userInfo: [NSLocalizedDescriptionKey: "音訊匯出失敗"])
                    writer.cancelWriting()
                    cont.resume(throwing: err)
                }
            }
        }
    }
    
    private func trimAudio(_ url: URL, start: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let durationCM = try await asset.load(.duration)
        let newURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + "_trim.caf")
        try? FileManager.default.removeItem(at: newURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { throw NSError(domain: "LocalTranscription", code: -20, userInfo: [NSLocalizedDescriptionKey: "無法建立裁剪工作"]) }
        let startTime = CMTime(seconds: max(0, start), preferredTimescale: durationCM.timescale)
        export.timeRange = CMTimeRange(start: startTime, duration: CMTimeSubtract(durationCM, startTime))
        if #available(macOS 15.0, iOS 18.0, *) {
            try await export.export(to: newURL, as: .caf)
            return newURL
        } else {
            // Wrapper to satisfy Sendable closure capture
            final class ExportSessionBox: @unchecked Sendable { let s: AVAssetExportSession; init(_ s: AVAssetExportSession){ self.s = s } }
            let box = ExportSessionBox(export)
            box.s.outputFileType = .caf
            box.s.outputURL = newURL
            return try await withCheckedThrowingContinuation { cont in
                box.s.exportAsynchronously {
                    switch box.s.status {
                    case .completed: cont.resume(returning: newURL)
                    case .failed, .cancelled:
                        cont.resume(throwing: box.s.error ?? NSError(domain: "LocalTranscription", code: -21, userInfo: [NSLocalizedDescriptionKey: "裁剪失敗"]))
                    default: break
                    }
                }
            }
        }
    }
    
    // Add missing M4A export helper
    private func exportToM4A(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "LocalTranscription", code: -40, userInfo: [NSLocalizedDescriptionKey: "無法建立 m4a 匯出會話"]) }
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".m4a")
        try? FileManager.default.removeItem(at: outURL)
        export.outputURL = outURL
        export.outputFileType = .m4a
        if #available(macOS 15.0, iOS 18.0, *) {
            try await export.export(to: outURL, as: .m4a)
            return outURL
        } else {
            final class Box: @unchecked Sendable { let e: AVAssetExportSession; init(_ e: AVAssetExportSession){ self.e = e } }
            let box = Box(export)
            return try await withCheckedThrowingContinuation { cont in
                box.e.exportAsynchronously {
                    switch box.e.status {
                    case .completed: cont.resume(returning: outURL)
                    case .failed, .cancelled:
                        cont.resume(throwing: box.e.error ?? NSError(domain: "LocalTranscription", code: -41, userInfo: [NSLocalizedDescriptionKey: "m4a 匯出失敗"]))
                    default: break
                    }
                }
            }
        }
    }
    
    // Adjusted analyzePCM to limit decoding for huge files
    private func analyzePCM(url: URL) async throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = file.length
        let duration = Double(totalFrames) / sampleRate
        let analysisFramesLimit = duration > maxPCMAnalysisDuration ? AVAudioFramePosition(sampleRate * maxPCMAnalysisDuration) : totalFrames
        let frameCount = AVAudioFrameCount(analysisFramesLimit)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try file.read(into: buffer, frameCount: frameCount)
        guard let channel = buffer.floatChannelData?[0] else { return AudioAnalysis(duration: duration, fileSize: fileSize(url: url), averageRMS: -120, leadingSilence: 0, url: url) }
        let usedFrames = Int(buffer.frameLength)
        let window = Int(sampleRate * 0.02)
        var sumSquares: Float = 0
        var leadingSilenceFrames = 0
        var foundSpeech = false
        let speechThreshold: Float = dbToLinear(-45)
        var idx = 0
        while idx < usedFrames {
            let end = min(idx + window, usedFrames)
            var localMax: Float = 0
            var j = idx
            while j < end { let v = abs(channel[j]); if v > localMax { localMax = v }; sumSquares += channel[j]*channel[j]; j += 1 }
            if !foundSpeech { if localMax >= speechThreshold { foundSpeech = true } else { leadingSilenceFrames = end } }
            idx = end
        }
        let rms = sqrt(sumSquares / Float(max(1, usedFrames)))
        let avgDB = linearToDB(rms)
        let leadingSilence = Double(leadingSilenceFrames) / sampleRate
        return AudioAnalysis(duration: duration, fileSize: fileSize(url: url), averageRMS: avgDB, leadingSilence: leadingSilence, url: url)
    }
    
    // Timeout wrapper
    private func runRecognizerWithTimeout(url: URL, localeIdentifier: String, stage: String) async throws -> [CaptionSegment] {
        let start = Date()
        return try await withThrowingTaskGroup(of: [CaptionSegment].self) { group in
            group.addTask { [weak self] in
                guard let self else { return [] }
                return try await self.runRecognizer(url: url, localeIdentifier: localeIdentifier)
            }
            group.addTask { [recognitionTimeout] in
                try await Task.sleep(nanoseconds: recognitionTimeout)
                throw NSError(domain: "LocalTranscription", code: -60, userInfo: [NSLocalizedDescriptionKey: "辨識逾時 stage=\(stage)"])
            }
            let result = try await group.next()!
            group.cancelAll()
            let elapsed = Date().timeIntervalSince(start)
            ACLog("SPEECH stage=\(stage) elapsed=\(String(format: "%.1f", elapsed))s segments=\(result.count)", level: .debug)
            return result
        }
    }
    
    // ADD BACK missing low-level helpers & recognizer (restored after refactor)
    private func fileSize(url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
    private func dbToLinear(_ db: Float) -> Float { pow(10, db/20) }
    private func linearToDB(_ lin: Float) -> Double { lin > 0 ? Double(20*log10(lin)) : -160 }
    
    private func runRecognizer(url: URL, localeIdentifier: String) async throws -> [CaptionSegment] {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let sz = attrs[.size] as? NSNumber, sz.intValue < 4000 {
            debugAudioFile(url, label: "runRecognizer.tooSmall locale=\(localeIdentifier)")
            throw NSError(domain: "LocalTranscription", code: -30, userInfo: [NSLocalizedDescriptionKey: "音訊檔案太短或無有效內容 (<4KB)"])
        }
        debugAudioFile(url, label: "runRecognizer.begin locale=\(localeIdentifier)")
        if Task.isCancelled { return [] }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw NSError(domain: "LocalTranscription", code: -1, userInfo: [NSLocalizedDescriptionKey: "不支援的語系"]) }
        let hasOnDevice: Bool = { if #available(macOS 12.0, iOS 13.0, *) { return recognizer.supportsOnDeviceRecognition } else { return false } }()
        if !hasOnDevice && !allowCloudFallback {
            throw NSError(domain: "LocalTranscription", code: -2, userInfo: [NSLocalizedDescriptionKey: "此語系未安裝離線模型且未允許雲端辨識"]) }
        let request = SFSpeechURLRecognitionRequest(url: url)
        if #available(macOS 12.0, iOS 13.0, *) { request.requiresOnDeviceRecognition = hasOnDevice && !allowCloudFallback }
        request.shouldReportPartialResults = false
    ACLog("SPEECH start locale=\(localeIdentifier) onDevice=\(hasOnDevice) allowCloud=\(allowCloudFallback) url=\(url.lastPathComponent)", level: .info)
        return try await withCheckedThrowingContinuation { cont in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let result = result, result.isFinal else { return }
                let captions = result.bestTranscription.segments.map { seg in CaptionSegment(text: seg.substring, start: seg.timestamp, duration: seg.duration) }
                ACLog("SPEECH finished locale=\(localeIdentifier) segments=\(captions.count)", level: .info)
                cont.resume(returning: captions)
            }
            Task { if Task.isCancelled { task.finish() } }
        }
    }
    
    // MARK: - Merging helpers (unchanged below except comments)
    private func mergeSegmentsByLanguage(_ inputs: [(locale: String, segments: [CaptionSegment])]) -> [CaptionSegment] {
        var pool: [LSeg] = []
        for (loc, segs) in inputs { pool.append(contentsOf: segs.map { LSeg(locale: loc, seg: $0) }) }
        pool.sort { $0.seg.start < $1.seg.start }
        var result: [CaptionSegment] = []
        let overlapTolerance: TimeInterval = 0.15
        var i = 0
        while i < pool.count {
            var current = pool[i]
            var j = i + 1
            var group: [LSeg] = [current]
            while j < pool.count {
                let next = pool[j]
                if overlaps(current.seg, next.seg, tolerance: overlapTolerance) {
                    group.append(next)
                    if next.seg.start + next.seg.duration > current.seg.start + current.seg.duration { current = next }
                    j += 1
                } else { break }
            }
            let chosen = chooseBestSegment(from: group)
            if let last = result.last, overlaps(last, chosen, tolerance: overlapTolerance) {
                if last.text != chosen.text { result.append(chosen) }
            } else { result.append(chosen) }
            i = j
        }
        var coalesced: [CaptionSegment] = []
        for seg in result.sorted(by: { $0.start < $1.start }) {
            if let last = coalesced.last, last.text == seg.text, last.start + last.duration + 0.1 >= seg.start {
                coalesced.removeLast()
                let newDuration = max(last.duration, (seg.start + seg.duration) - last.start)
                coalesced.append(CaptionSegment(text: last.text, start: last.start, duration: newDuration))
            } else { coalesced.append(seg) }
        }
        return coalesced
    }
    private func overlaps(_ a: CaptionSegment, _ b: CaptionSegment, tolerance: TimeInterval) -> Bool {
        let aEnd = a.start + a.duration; let bEnd = b.start + b.duration
        return !(aEnd + tolerance < b.start || bEnd + tolerance < a.start)
    }
    private func chooseBestSegment(from group: [LSeg]) -> CaptionSegment {
        var best: LSeg?; var bestScore = -Double.infinity
        for item in group { let s = score(text: item.seg.text, preferredLocale: item.locale); if s > bestScore { bestScore = s; best = item } }
        return best!.seg
    }
    private func score(text: String, preferredLocale: String) -> Double {
        let zhCount = countCJK(in: text); let enCount = countLatin(in: text)
        let total = max(1, text.trimmingCharacters(in: .whitespacesAndNewlines).count)
        let zhRatio = Double(zhCount)/Double(total); let enRatio = Double(enCount)/Double(total)
        var s = 0.0
        if preferredLocale.lowercased().hasPrefix("zh") { s += zhRatio * 2 }
        if preferredLocale.lowercased().hasPrefix("en") { s += enRatio * 2 }
        s += (zhRatio + enRatio)
        s += Double(total) * 0.01
        if let lang = detectLanguage(for: text) { if lang == .simplifiedChinese || lang == .traditionalChinese { s += 0.3 }; if lang == .english { s += 0.3 } }
        return s
    }
    private func countCJK(in text: String) -> Int { var c=0; for s in text.unicodeScalars { switch s.value { case 0x4E00...0x9FFF,0x3400...0x4DBF,0x20000...0x2A6DF,0x2A700...0x2B73F,0x2B740...0x2B81F,0x2B820...0x2CEAF,0xF900...0xFAFF: c+=1; default: break } }; return c }
    private func countLatin(in text: String) -> Int { var c=0; for s in text.unicodeScalars { if (0x41...0x5A).contains(Int(s.value)) || (0x61...0x7A).contains(Int(s.value)) { c+=1 } }; return c }
    private func detectLanguage(for text: String) -> NLLanguage? { let r = NLLanguageRecognizer(); r.processString(text); return r.dominantLanguage }
    
    // Diagnostics helper
    private func debugAudioFile(_ url: URL, label: String) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            var lengthSeconds: Double = -1
            if let af = try? AVAudioFile(forReading: url) {
                let sr = af.processingFormat.sampleRate
                lengthSeconds = Double(af.length) / max(1, sr)
            }
            ACLog("AUDIO DEBUG label=\(label) path=\(url.lastPathComponent) exists=\(FileManager.default.fileExists(atPath: url.path)) size=\(size)B duration=\(lengthSeconds < 0 ? "?" : String(format: "%.2f", lengthSeconds))s", level: .trace)
        } catch {
            ACLog("AUDIO DEBUG label=\(label) path=\(url.lastPathComponent) error=\(error.localizedDescription)", level: .warn)
        }
    }
}

struct CaptionSegment: Codable, Hashable { let text: String; let start: TimeInterval; let duration: TimeInterval }
