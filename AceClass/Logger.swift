import Foundation
import SwiftUI

// MARK: - LogLevel
enum LogLevel: String, CaseIterable, Codable, Identifiable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .trace: return .gray
        case .debug: return .cyan
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        case .critical: return .red.opacity(0.9)
        }
    }
    
    var symbol: String {
        switch self {
        case .trace: return "point.topleft.down.curvedto.point.bottomright.up"
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .critical: return "bolt.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - LogEntry
struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    
    init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Logger
@MainActor
final class Logger: ObservableObject {
    static let shared = Logger()
    
    @Published private(set) var entries: [LogEntry] = []
    @Published var filterLevel: LogLevel? = nil
    @Published var minimumLevel: LogLevel = .trace // runtime severity gate
    @Published var loggingEnabled: Bool = true
    
    private let queue = DispatchQueue(label: "aceclass.logger.write", qos: .utility)
    private let fileURL: URL
    private let maxEntriesInMemory = 2000
    private let maxFileSizeBytes: Int64 = 5 * 1024 * 1024 // 5 MB rotate threshold
    private let logDirectory: URL
    private var pendingLines: [String] = [] // MainActor guarded
    private var flushTaskScheduled = false  // MainActor guarded
    private let flushInterval: TimeInterval = 0.5
    
    private init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("AceClass/Logs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.logDirectory = dir
        self.fileURL = dir.appendingPathComponent("aceclass.log")
        loadExistingTail()
        logInternal("Logger initialized at path: \(fileURL.path)", level: .debug)
    }
    
    // Public API
    func log(_ message: String, level: LogLevel = .info, file: String = #fileID, function: String = #function, line: Int = #line) {
        let enriched = "[\(level.rawValue)] \(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function) - \(message)"
        logInternal(enriched, level: level)
    }
    
    func clear() {
        entries.removeAll()
        queue.async { [fileURL] in
            try? "".data(using: .utf8)?.write(to: fileURL)
        }
    }
    
    func exportLog() -> URL? {
        // Return current log file URL (caller can present share panel / save panel)
        return fileURL
    }
    
    var filteredEntries: [LogEntry] {
        guard let level = filterLevel else { return entries }
        // Show selected level and more severe levels
        let ordered: [LogLevel] = [.trace, .debug, .info, .warn, .error, .critical]
        guard let idx = ordered.firstIndex(of: level) else { return entries }
        let allowed = Set(ordered[idx...])
        return entries.filter { allowed.contains($0.level) }
    }
    
    // MARK: - Internal
    private func logInternal(_ message: String, level: LogLevel) {
        guard loggingEnabled else { return }
        // Drop if below minimumLevel
        if orderIndex(of: level) < orderIndex(of: minimumLevel) { return }
        let entry = LogEntry(level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntriesInMemory { entries.removeFirst(entries.count - maxEntriesInMemory) }
    Swift.print(entry.formattedTime, message)
    bufferPersist(entry)
    }

    private func orderIndex(of level: LogLevel) -> Int {
        switch level {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .warn: return 3
        case .error: return 4
        case .critical: return 5
        }
    }
    
    private func bufferPersist(_ entry: LogEntry) {
        let line = "\(entry.formattedTime) [\(entry.level.rawValue)] \(entry.message)\n"
        pendingLines.append(line)
        if !flushTaskScheduled { flushTaskScheduled = true; scheduleFlush() }
    }
    private func scheduleFlush() {
        let interval = flushInterval
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            await self?.flushNow()
        }
    }
    @MainActor private func flushNow() {
        let lines = pendingLines
        pendingLines.removeAll()
        flushTaskScheduled = false
        if !lines.isEmpty { writeLines(lines) }
    }
    private func writeLines(_ lines: [String]) {
        queue.async { [fileURL, weak self] in
            let joined = lines.joined()
            if let data = joined.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
            Task { @MainActor [weak self] in self?.rotateIfNeeded() }
        }
    }
    
    private func rotateIfNeeded() {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attrs[.size] as? NSNumber, size.int64Value > maxFileSizeBytes {
                let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let rotated = logDirectory.appendingPathComponent("aceclass_\(ts).log")
                try FileManager.default.moveItem(at: fileURL, to: rotated)
                // Write a marker into new file
                let header = "Log rotated. Previous file: \(rotated.lastPathComponent)\n"
                try header.data(using: .utf8)?.write(to: fileURL)
            }
        } catch {
            Swift.print("Logger rotation error: \(error.localizedDescription)")
        }
    }
    
    private func loadExistingTail() {
        guard let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) else { return }
        // Parse last N lines
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let tail = lines.suffix(500)
        for line in tail {
            // Attempt simple parsing: time [LEVEL] message
            if let bracketRange = line.firstIndex(of: "]"),
               let levelStart = line.firstIndex(of: "[") {
                let levelToken = line[line.index(after: levelStart)..<bracketRange]
                let level = LogLevel(rawValue: String(levelToken)) ?? .info
                // Message after space
                let parts = line.split(separator: "]", maxSplits: 1, omittingEmptySubsequences: true)
                let message = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : String(line)
                let entry = LogEntry(level: level, message: message)
                entries.append(entry)
            } else {
                entries.append(LogEntry(level: .info, message: String(line)))
            }
        }
    }
}

// MARK: - Debug Console View
struct DebugConsoleView: View {
    @ObservedObject private var logger = Logger.shared
    @Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true
    @State private var cacheCount: Int = 0
    @State private var cacheBytes: Int64 = 0
    @State private var isClearingCache = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logList
            Divider()
            footer
        }
        .frame(minWidth: 800, minHeight: 500)
        .task(id: logger.filteredEntries.count) {
            // Keep at bottom if autoScroll
        }
    .onAppear { loadCacheStats() }
    }
    
    private var header: some View {
        HStack {
            Text("偵錯主控台").font(.title3).bold()
            Spacer()
            Picker("層級", selection: $logger.filterLevel) {
                Text("全部").tag(LogLevel?.none)
                ForEach(LogLevel.allCases) { level in
                    Text(level.rawValue).tag(LogLevel?.some(level))
                }
            }
            .pickerStyle(.menu)
            Toggle("自動捲動", isOn: $autoScroll).toggleStyle(.switch)
            Button(role: .destructive) { logger.clear() } label: {
                Label("清除", systemImage: "trash")
            }
            Button { exportLog() } label: {
                Label("匯出", systemImage: "square.and.arrow.up")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
    }
    
    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(logger.filteredEntries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(entry.formattedTime)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            Image(systemName: entry.level.symbol)
                                .foregroundColor(entry.level.color)
                                .frame(width: 18)
                            Text(entry.level.rawValue)
                                .font(.system(.caption2, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(entry.level.color.opacity(0.15))
                                .cornerRadius(4)
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .id(entry.id)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .onChange(of: logger.filteredEntries.count) { _, _ in
                if autoScroll, let last = logger.filteredEntries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
    
    private var footer: some View {
        HStack {
            Text("目前記憶體內紀錄: \(logger.entries.count) 行").font(.caption).foregroundColor(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    Text("快取影片: \(cacheCount) 個").font(.caption).foregroundColor(.secondary)
                    Text(sizeString(cacheBytes)).font(.caption).foregroundColor(.secondary)
                    Button(action: { loadCacheStats() }) {
                        Image(systemName: "arrow.clockwise")
                    }.help("刷新快取統計").buttonStyle(.borderless)
                    Button(role: .destructive) {
                        clearCache()
                    } label: {
                        if isClearingCache { ProgressView().scaleEffect(0.6) } else { Text("清除快取").font(.caption) }
                    }
                    .disabled(isClearingCache || (cacheCount == 0))
                }
                Text("Log 檔案: \(Logger.shared.exportLog()?.path ?? "-")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(6)
    }
    
    private func exportLog() {
        guard let url = Logger.shared.exportLog() else { return }
        // macOS share: show in Finder
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Cache Helpers
    private func loadCacheStats() {
        let stats = VideoCacheManager.shared.cacheStats()
        cacheCount = stats.count
        cacheBytes = stats.totalBytes
    }
    private func clearCache() {
        isClearingCache = true
        Task {
            await VideoCacheManager.shared.clearCache()
            await MainActor.run {
                isClearingCache = false
                loadCacheStats()
            }
        }
    }
    private func sizeString(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        let units = ["B","KB","MB","GB","TB"]
        var value = Double(bytes)
        var idx = 0
        while value > 1024 && idx < units.count-1 { value /= 1024; idx += 1 }
        return String(format: "%.2f %@", value, units[idx])
    }
}

// MARK: - Convenience Global Function
@inline(__always) func ACLog(_ message: String, level: LogLevel = .info) {
    Task { @MainActor in
        Logger.shared.log(message, level: level)
    }
}
