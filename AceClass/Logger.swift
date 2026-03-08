import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            self?.flushNow()
        }
    }
    private func flushNow() {
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
    let appState: AppState?
    @ObservedObject private var logger = Logger.shared
    @Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true
    @State private var searchText = ""
    @State private var cacheCount: Int = 0
    @State private var cacheBytes: Int64 = 0
    @State private var isClearingCache = false
    
    var body: some View {
        VStack(spacing: 16) {
            header
            summaryGrid
            controlsBar
            logList
            footer
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 640)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.05), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear { loadCacheStats() }
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("debug.title"))
                    .font(.title2.weight(.bold))
                Text(L10n.tr("debug.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Toggle(L10n.tr("debug.logging_enabled"), isOn: $logger.loggingEnabled)
                    .toggleStyle(.switch)

                Picker(L10n.tr("debug.minimum_level"), selection: $logger.minimumLevel) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.menu)

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24))
        )
    }
    
    private var summaryGrid: some View {
        HStack(spacing: 12) {
            DebugMetricCard(
                title: L10n.tr("debug.metric.visible"),
                value: "\(displayedEntries.count)",
                detail: L10n.tr("debug.metric.total_entries", logger.entries.count),
                tint: .blue,
                systemImage: "text.alignleft"
            )
            DebugMetricCard(
                title: L10n.tr("debug.metric.warnings"),
                value: "\(entriesCount(for: .warn))",
                detail: L10n.tr("debug.metric.errors", entriesCount(for: .error) + entriesCount(for: .critical)),
                tint: .orange,
                systemImage: "exclamationmark.triangle"
            )
            DebugMetricCard(
                title: L10n.tr("debug.metric.cache"),
                value: "\(cacheCount)",
                detail: sizeString(cacheBytes),
                tint: .teal,
                systemImage: "internaldrive"
            )
            runtimeStatusCard
        }
    }

    private var runtimeStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.tr("debug.runtime_status"), systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(playerStateText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(playerStateColor)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(playerStateColor.opacity(0.12), in: Capsule())
            }

            DebugKeyValueRow(key: L10n.tr("debug.key.source"), value: appState?.sourceFolderURL?.lastPathComponent ?? L10n.tr("debug.not_selected"))
            DebugKeyValueRow(key: L10n.tr("debug.key.course"), value: appState?.selectedCourse?.displayTitle ?? L10n.tr("debug.not_selected"))
            DebugKeyValueRow(key: L10n.tr("debug.key.video"), value: appState?.currentVideo?.resolvedTitle ?? L10n.tr("debug.not_playing"))
            if let detail = appState?.playerLoadingDetail, !detail.isEmpty, appState?.isInitializingPlayer == true {
                DebugKeyValueRow(key: L10n.tr("debug.key.loading"), value: detail)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20))
        )
    }

    private var controlsBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.tr("debug.search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker(L10n.tr("debug.display_level"), selection: $logger.filterLevel) {
                Text(L10n.tr("common.all")).tag(LogLevel?.none)
                ForEach(LogLevel.allCases) { level in
                    Text(level.rawValue).tag(LogLevel?.some(level))
                }
            }
            .pickerStyle(.menu)

            Toggle(L10n.tr("common.auto_scroll"), isOn: $autoScroll)
                .toggleStyle(.switch)

            Spacer()

            Button(role: .destructive) { logger.clear() } label: {
                Label(L10n.tr("debug.clear_records"), systemImage: "trash")
            }

            Button { copyVisibleLogs() } label: {
                Label(L10n.tr("debug.copy_visible"), systemImage: "doc.on.doc")
            }

            Button { exportLog() } label: {
                Label(L10n.tr("debug.open_log"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            Group {
                if displayedEntries.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("debug.empty_title"),
                        systemImage: "text.magnifyingglass",
                        description: Text(searchText.isEmpty ? L10n.tr("debug.empty_subtitle") : L10n.tr("debug.empty_search_subtitle"))
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(displayedEntries) { entry in
                                DebugLogRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20))
            )
            .onChange(of: displayedEntries.count) { _, _ in
                if autoScroll, let last = displayedEntries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
    
    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("debug.log_file"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Logger.shared.exportLog()?.path ?? "-")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: { loadCacheStats() }) {
                    Label(L10n.tr("debug.refresh_cache"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    clearCache()
                } label: {
                    if isClearingCache {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.tr("debug.clear_cache"), systemImage: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isClearingCache || cacheCount == 0)
            }
        }
        .padding(.horizontal, 4)
    }
    
    private func exportLog() {
        guard let url = Logger.shared.exportLog() else { return }
        // macOS share: show in Finder
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyVisibleLogs() {
        let text = displayedEntries
            .map { "\($0.formattedTime) [\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

    private var displayedEntries: [LogEntry] {
        let base = logger.filteredEntries
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { entry in
            entry.message.localizedCaseInsensitiveContains(query) ||
            entry.level.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private func entriesCount(for level: LogLevel) -> Int {
        displayedEntries.filter { $0.level == level }.count
    }

    private var playerStateText: String {
        guard let appState else { return L10n.tr("debug.player_state.disconnected") }
        if appState.isInitializingPlayer {
            return appState.playerLoadingTitle ?? L10n.tr("debug.player_state.initializing")
        }
        if appState.player != nil {
            return L10n.tr("debug.player_state.ready")
        }
        if appState.currentVideo != nil {
            return L10n.tr("debug.player_state.selected")
        }
        return L10n.tr("debug.player_state.idle")
    }

    private var playerStateColor: Color {
        guard let appState else { return .secondary }
        if appState.isInitializingPlayer {
            return .orange
        }
        if appState.player != nil {
            return .green
        }
        return .secondary
    }
}

private struct DebugMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.16))
        )
    }
}

private struct DebugKeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct DebugLogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.formattedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Label(entry.level.rawValue, systemImage: entry.level.symbol)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(entry.level.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(entry.level.color.opacity(0.12), in: Capsule())
                Spacer()
            }

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(entry.level.color.opacity(0.10))
        )
    }
}

// MARK: - Convenience Global Function
@inline(__always) func ACLog(_ message: String, level: LogLevel = .info) {
    Task { @MainActor in
        Logger.shared.log(message, level: level)
    }
}
