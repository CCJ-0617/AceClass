# AceClass 開發文檔

## 1. 專案概覽

AceClass 是一個為 macOS 設計的 SwiftUI 應用程式，旨在幫助使用者管理和觀看本地儲存的補課影片。使用者可以選擇一個包含多個課程資料夾的根目錄，應用程式會自動掃描課程和影片，並提供一個方便的介面來播放、追蹤觀看狀態和做筆記。

此專案最初由 Xcode 的文件導向（Document-Based）應用程式模板建立，但後續已重構為一個標準的單視窗應用程式，以更符合其直接操作檔案系統的功能需求。

---

## 2. 核心架構與設計

### 2.1. 架構模式

本專案採用了類似 MVVM (Model-View-ViewModel) 的架構，利用 SwiftUI 的特性實現：

-   **Model**: 由 `Models.swift` 中的 `Course` 和 `VideoItem` 結構體定義。它們是純粹的資料結構，負責表示課程和影片的狀態，並包含編碼/解碼邏輯以進行 JSON 持久化。
-   **View**: 所有的 UI 視圖檔案：
    - `ContentView.swift`: 主視圖容器，採用 `NavigationSplitView` 實現三欄布局
    - `CourseRowView.swift`: 側邊欄課程列表項
    - `VideoRowView.swift`: 中間影片列表項，包含編輯功能
    - `UnwatchedVideoRowView.swift`: 統計視圖中的未觀看影片項
    - `CourseStatisticsView.swift`: 課程統計面板
    - `VideoPlayerView.swift`: 影片播放器（支援全螢幕）
-   **ViewModel/State Management**: `AppState.swift` 作為主要的狀態管理器，使用 `ObservableObject` 協議管理應用程式全域狀態。

### 2.2. 狀態管理架構

```swift
class AppState: ObservableObject {
    @Published var courses: [Course] = []
    @Published var selectedCourseID: UUID?
    @Published var currentVideo: VideoItem?
    @Published var currentVideoURL: URL?
    @Published var isVideoPlayerFullScreen = false
    @Published var sourceFolderURL: URL?
    
    private var securityScopedURL: URL?
    private var currentlyAccessedVideoURL: URL?
}
```

### 2.3. 並發和線程安全

- **主線程**: 所有 UI 更新使用 `Task { @MainActor in }` 確保在主線程執行
- **後台線程**: 檔案 I/O 操作在 `DispatchQueue.global(qos: .background)` 執行
- **狀態更新**: 避免在視圖更新期間修改狀態，使用 `Task.detached` 處理副作用

---

## 3. 資料模型與持久化

### 3.1. 核心資料結構

```swift
struct VideoItem: Identifiable, Codable {
    let id: UUID
    let fileName: String         // 實際檔名
    var displayName: String      // 顯示名稱
    var note: String             // 註解
    var watched: Bool            // 是否已看
    let date: Date?              // 從檔名解析出的日期
}

struct Course: Identifiable, Hashable {
    let id = UUID()
    let folderURL: URL
    var videos: [VideoItem]
}
```

### 3.2. 混合儲存策略

應用程式採用本地優先的混合儲存策略：

#### 本地儲存 (主要)
```swift
class LocalMetadataStorage {
    static let baseDirectory: URL = {
        // ~/Library/Containers/App/Data/Library/Application Support/AceClass/
    }()
    
    static let coursesDirectory: URL = {
        // baseDirectory/Courses/
    }()
}
```

#### 外部同步 (輔助)
- 嘗試在每個課程資料夾建立 `videos.json`
- 使用 "best effort" 原則，失敗不影響應用功能
- 可透過 `LocalMetadataStorage.shouldAttemptWriteToExternalDrives` 控制

### 3.3. 日期解析算法

```swift
static func extractDate(from fileName: String) -> Date? {
    let pattern = "(?:20)?(\\d{2})(\\d{2})(\\d{2})"
    // 支援 20250704 和 250704 格式
    // 自動補充 "20" 前綴處理兩位數年份
}
```

---

## 4. macOS 沙盒權限管理

### 4.1. Entitlements 配置

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.files.bookmarks.document-scope</key>
<true/>
```

### 4.2. 安全作用域書籤流程

```swift
// 1. 使用者選擇資料夾
func handleFolderSelection(_ result: Result<[URL], Error>) {
    // 2. 啟動安全作用域存取
    guard folder.startAccessingSecurityScopedResource() else { return }
    
    // 3. 建立持久化書籤
    let bookmarkData = try folder.bookmarkData(options: .withSecurityScope)
    UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    
    // 4. 保持權限直到應用關閉
    self.securityScopedURL = folder
}

// 5. 應用啟動時恢復權限
func loadBookmark() {
    let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope)
    guard url.startAccessingSecurityScopedResource() else { return }
    self.securityScopedURL = url
}
```

### 4.3. 權限繼承策略

- **根權限**: 對選擇的根資料夾持有一個安全作用域權限
- **子資料夾繼承**: 所有子資料夾和檔案操作自動繼承根權限
- **避免重複請求**: 不在每個檔案操作時重複呼叫 `startAccessingSecurityScopedResource()`

---

## 5. 影片播放架構

### 5.1. AVPlayer 整合

```swift
// 標準播放
if let url = appState.currentVideoURL {
    VideoPlayer(player: AVPlayer(url: url))
}

// 全螢幕播放
FullScreenVideoPlayerView(
    player: AVPlayer(url: url), 
    onToggleFullScreen: appState.toggleFullScreen
)
```

### 5.2. 全螢幕模式

- 使用 `ZStack` 覆蓋實現
- 快捷鍵支援: `Cmd+Ctrl+F`
- 狀態管理: `@Published var isVideoPlayerFullScreen`

---

## 6. 錯誤處理與調試

### 6.1. 權限調試工具

```swift
func debugPermissionStatus() {
    print("=== 權限狀態調試 ===")
    // 檢查可讀/可寫權限
    // 測試目錄存取
    // 輸出詳細診斷資訊
}
```

### 6.2. 常見問題解決

1. **"Publishing changes from within view updates"**
   - 解決方案: 使用 `Task { @MainActor in }` 而非 `DispatchQueue.main.async`

2. **權限問題**
   - 確保正確的 entitlements 配置
   - 檢查安全作用域權限的獲取順序

3. **檔案存取失敗**
   - 驗證書籤的有效性
   - 檢查檔案系統權限

---

## 7. 建置與部署

### 7.1. 開發環境需求

- Xcode 14.0+
- macOS 12.0+ (deployment target)
- Swift 5.7+

### 7.2. 關鍵建置設定

- **Code Signing**: 需要適當的開發者憑證
- **Hardened Runtime**: 啟用以符合 notarization 需求
- **Entitlements**: 確保沙盒權限正確配置

### 7.3. 測試建議

1. **權限測試**: 測試首次授權和書籤恢復
2. **外部驅動器測試**: 驗證在不同儲存裝置上的行為
3. **大量檔案測試**: 測試包含大量影片的資料夾
4. **權限撤銷測試**: 測試使用者撤銷權限後的應用行為

---

## 8. 架構決策記錄

### 8.1. 為什麼選擇混合儲存策略？

- **可靠性**: 本地儲存確保資料不會遺失
- **可移植性**: 外部同步支援跨裝置使用
- **彈性**: 即使外部寫入失敗也不影響功能

### 8.2. 為什麼使用單一安全作用域權限？

- **效能**: 避免重複權限請求的開銷
- **穩定性**: 減少權限相關的錯誤
- **簡化**: 權限管理邏輯更清晰

### 8.3. 為什麼重構為非文件導向應用？

- **使用模式**: 使用者操作整個資料夾而非單一文件
- **權限模型**: 更適合安全作用域書籤的使用方式
- **UI 設計**: 三欄布局更適合課程/影片的層次結構

---

**最後更新**: 2025年7月6日  
**專案版本**: 1.0
