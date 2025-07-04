import Foundation

struct VideoItem: Identifiable, Codable {
    let id: UUID
    let fileName: String         // 實際檔名
    var displayName: String      // 顯示名稱
    var note: String             // 註解
    var watched: Bool            // 是否已看
    let date: Date?              // 從檔名解析出的日期
    
    init(fileName: String, displayName: String? = nil, note: String = "", watched: Bool = false) {
        self.id = UUID()
        self.fileName = fileName
        self.displayName = displayName ?? fileName
        self.note = note.isEmpty ? fileName : note // 如果註解為空，則預設為檔名
        self.watched = watched
        self.date = Self.extractDate(from: fileName) // 初始化時自動解析日期
    }
    
    // 增加一個靜態方法來解析日期，使其在初始化時就能被呼叫
    static func extractDate(from fileName: String) -> Date? {
        // 正則表達式，尋找像 20250704 或 250704 這樣的日期格式
        let pattern = "(?:20)?(\\d{2})(\\d{2})(\\d{2})"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
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
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0) // 標準化時區
            
            return formatter.date(from: dateString)
        }
        
        return nil
    }
    
    // 為了讓 Codable 能正確運作，我們需要自訂編碼和解碼過程
    enum CodingKeys: String, CodingKey {
        case id, fileName, displayName, note, watched, date
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        displayName = try container.decode(String.self, forKey: .displayName)
        note = try container.decode(String.self, forKey: .note)
        watched = try container.decode(Bool.self, forKey: .watched)
        // 如果解碼時 date 不存在（舊資料），則重新解析一次
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Self.extractDate(from: fileName)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(note, forKey: .note)
        try container.encode(watched, forKey: .watched)
        try container.encode(date, forKey: .date)
    }
}

struct Course: Identifiable, Hashable {
    let id = UUID()
    let folderURL: URL
    var videos: [VideoItem]
    
    var jsonFileURL: URL {
        folderURL.appendingPathComponent("videos.json")
    }
    
    static func == (lhs: Course, rhs: Course) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}