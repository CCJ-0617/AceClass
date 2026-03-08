import Foundation

struct VideoItem: Identifiable, Codable {
    private static let dateRegex = try? NSRegularExpression(pattern: "(?:20)?(\\d{2})(\\d{2})(\\d{2})")
    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    private static let metadataDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    let id: UUID
    let fileName: String         // 實際檔名
    let relativePath: String     // 相對於課程資料夾的檔案路徑
    var displayName: String      // 顯示名稱
    var note: String             // 註解
    var watched: Bool            // 是否已看
    let date: Date?              // 從檔名解析出的日期
    var lastPlaybackPosition: Double? // 最後播放位置（秒）
    
    init(
        fileName: String,
        relativePath: String? = nil,
        displayName: String? = nil,
        note: String = "",
        watched: Bool = false,
        lastPlaybackPosition: Double? = nil
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.relativePath = relativePath ?? fileName
        self.displayName = displayName ?? fileName
        self.note = note.isEmpty ? fileName : note // 如果註解為空，則預設為檔名
        self.watched = watched
        self.date = Self.extractDate(from: fileName) // 初始化時自動解析日期
        self.lastPlaybackPosition = lastPlaybackPosition
    }
    
    // 增加一個靜態方法來解析日期，使其在初始化時就能被呼叫
    static func extractDate(from fileName: String) -> Date? {
        guard let regex = dateRegex else {
            return nil
        }
        
        let nsRange = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        if let match = regex.firstMatch(in: fileName, options: [], range: nsRange) {
            // 提取年份、月份、日期
            let yearRange = Range(match.range(at: 1), in: fileName)!
            let monthRange = Range(match.range(at: 2), in: fileName)!
            let dayRange = Range(match.range(at: 3), in: fileName)!
            
            var yearStr = String(fileName[yearRange])
            let monthStr = String(fileName[monthRange])
            let dayStr = String(fileName[dayRange])
            
            // 如果是兩位數年份，補上前綴 "20"
            if yearStr.count == 2 {
                yearStr = "20" + yearStr
            }
            
            let dateString = "\(yearStr)\(monthStr)\(dayStr)"
            return filenameDateFormatter.date(from: dateString)
        }
        
        return nil
    }
    
    // 為了讓 Codable 能正確運作，我們需要自訂編碼和解碼過程
    enum CodingKeys: String, CodingKey {
        case id, fileName, relativePath, displayName, note, watched, date, lastPlaybackPosition
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) ?? fileName
        displayName = try container.decode(String.self, forKey: .displayName)
        note = try container.decode(String.self, forKey: .note)
        watched = try container.decode(Bool.self, forKey: .watched)
        // 如果解碼時 date 不存在（舊資料），則重新解析一次
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Self.extractDate(from: fileName)
        lastPlaybackPosition = try container.decodeIfPresent(Double.self, forKey: .lastPlaybackPosition)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(note, forKey: .note)
        try container.encode(watched, forKey: .watched)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(lastPlaybackPosition, forKey: .lastPlaybackPosition)
    }

    func updatingRelativePath(_ relativePath: String) -> VideoItem {
        VideoItem(
            id: id,
            fileName: fileName,
            relativePath: relativePath,
            displayName: displayName,
            note: note,
            watched: watched,
            date: date,
            lastPlaybackPosition: lastPlaybackPosition
        )
    }

    var resolvedTitle: String {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }

        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return baseName.isEmpty ? fileName : baseName
    }

    var noteSummary: String? {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return nil }
        guard trimmedNote != fileName, trimmedNote != displayName else { return nil }
        return trimmedNote
    }

    var fileTypeLabel: String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.uppercased()
        return ext.isEmpty ? "VIDEO" : ext
    }

    var formattedDateText: String? {
        guard let date else { return nil }
        return Self.metadataDateFormatter.string(from: date)
    }

    var playbackPositionText: String? {
        guard let lastPlaybackPosition, lastPlaybackPosition >= 5 else { return nil }
        return "續播 \(Self.formatTime(lastPlaybackPosition))"
    }

    var watchStatusText: String {
        watched ? "已觀看" : "未觀看"
    }

    private static func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        let hours = minutes / 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private init(
        id: UUID,
        fileName: String,
        relativePath: String,
        displayName: String,
        note: String,
        watched: Bool,
        date: Date?,
        lastPlaybackPosition: Double?
    ) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.displayName = displayName
        self.note = note
        self.watched = watched
        self.date = date
        self.lastPlaybackPosition = lastPlaybackPosition
    }
}

struct Course: Identifiable, Hashable, Codable {
    let id: UUID
    let folderURL: URL
    var videos: [VideoItem]
    var targetDate: Date?        // 目標完成日期
    var targetDescription: String // 目標描述
    
    var jsonFileURL: URL {
        folderURL.appendingPathComponent("videos.json")
    }
    
    // 計算剩餘天數
    var daysRemaining: Int? {
        guard let targetDate = targetDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: targetDate)
        let components = calendar.dateComponents([.day], from: today, to: target)
        return components.day
    }
    
    // 是否已過期
    var isOverdue: Bool {
        guard let daysRemaining = daysRemaining else { return false }
        return daysRemaining < 0
    }
    
    // 格式化的倒數計日文字
    var countdownText: String {
        guard let daysRemaining = daysRemaining else { return "未設定目標日期" }
        
        if daysRemaining < 0 {
            return "已過期 \(abs(daysRemaining)) 天"
        } else if daysRemaining == 0 {
            return "今天到期"
        } else {
            return "剩餘 \(daysRemaining) 天"
        }
    }
    
    init(folderURL: URL, videos: [VideoItem] = [], targetDate: Date? = nil, targetDescription: String = "") {
        self.id = UUID()
        self.folderURL = folderURL
        self.videos = videos
        self.targetDate = targetDate
        self.targetDescription = targetDescription
    }
    
    // 特殊的初始化器用於從存儲中恢復
    init(id: UUID, folderURL: URL, videos: [VideoItem] = [], targetDate: Date? = nil, targetDescription: String = "") {
        self.id = id
        self.folderURL = folderURL
        self.videos = videos
        self.targetDate = targetDate
        self.targetDescription = targetDescription
    }
    
    static func == (lhs: Course, rhs: Course) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayTitle: String {
        folderURL.lastPathComponent
    }

    var totalVideoCount: Int {
        videos.count
    }

    var watchedVideoCount: Int {
        videos.filter(\.watched).count
    }

    var unwatchedVideoCount: Int {
        totalVideoCount - watchedVideoCount
    }

    var completionRatio: Double {
        guard totalVideoCount > 0 else { return 0 }
        return Double(watchedVideoCount) / Double(totalVideoCount)
    }

    var completionText: String {
        "\(watchedVideoCount)/\(totalVideoCount) 已完成"
    }

    var progressPercentText: String {
        totalVideoCount == 0 ? "尚無影片" : "\(Int((completionRatio * 100).rounded()))% 完成"
    }

    var targetDateText: String? {
        guard let targetDate else { return nil }
        return targetDate.formatted(date: .abbreviated, time: .omitted)
    }

    var targetSummaryText: String? {
        if let targetDate {
            let description = targetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if description.isEmpty {
                return targetDate.formatted(date: .abbreviated, time: .omitted)
            }
            return "\(description) ・ \(targetDate.formatted(date: .abbreviated, time: .omitted))"
        }

        return nil
    }

    var learningStatusText: String {
        if totalVideoCount == 0 {
            return "等待匯入影片"
        }
        if unwatchedVideoCount == 0 {
            return "全部影片已完成"
        }
        return "還有 \(unwatchedVideoCount) 部待看"
    }
}
