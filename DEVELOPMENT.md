# AceClass 開發文檔

## 1. 專案概覽

AceClass 是一個為 macOS 設計的 SwiftUI 應用程式，旨在幫助使用者管理和觀看本地儲存的補課影片。使用者可以選擇一個包含多個課程資料夾的根目錄，應用程式會自動掃描課程和影片，並提供一個方便的介面來播放、追蹤觀看狀態和做筆記。

此專案最初由 Xcode 的文件導向（Document-Based）應用程式模板建立，但後續已重構為一個標準的單視窗應用程式，以更符合其直接操作檔案系統的功能需求。

---

## 2. 核心架構與設計

### 2.1. 架構模式

本專案採用了類似 MVVM (Model-View-ViewModel) 的架構，利用 SwiftUI 的特性實現：

-   **Model**: 由 `Models.swift` 中的 `Course` 和 `VideoItem` 結構體定義。它們是純粹的資料結構，負責表示課程和影片的狀態，並包含編碼/解碼邏輯以進行 JSON 持久化。
-   **View**: 所有的 `*.swift` 檔案（除了 `AceClassApp.swift` 和 `Models.swift`）都定義了 UI 的一部分。遵循 SwiftUI 的組合式原則，`ContentView.swift` 作為主容器，將 `CourseRowView`, `VideoRowView`, `CourseStatisticsView` 等小型、可重複使用的視圖組合在一起。
-   **ViewModel**: `ContentView.swift` 扮演了主要的 ViewModel 角色。它持有並管理所有應用程式的狀態（如 `selectedCourseID`, `player`），並包含所有的業務邏輯（如載入課程、儲存影片資料、處理權限等）。`CourseManager` 則是一個專門用來發布課程列表變更的 `ObservableObject`。

### 2.2. 視圖拆分

為了提高可維護性，UI 被拆分成多個獨立的檔案：

-   `ContentView.swift`: 主視圖，作為所有子視圖的協調者和狀態管理器。
-   `CourseRowView.swift`: 側邊欄中顯示單一課程的列。
-   `VideoRowView.swift`: 中間列表中顯示單一影片的列，包含編輯和操作按鈕。
-   `UnwatchedVideoRowView.swift`: 在統計視圖中顯示未觀看影片的簡化列。
-   `CourseStatisticsView.swift`: 當未播放任何影片時，在右側面板顯示課程的統計數據。
-   `VideoPlayerView.swift`: 包含標準模式和全螢幕模式的影片播放器元件。

### 2.3. 狀態管理

-   **`@StateObject`**: 在 `ContentView` 中使用 `CourseManager`，確保其生命週期與視圖綁定。
-   **`@State`**: 用於管理 `ContentView` 內部簡單的、本地的 UI 狀態（如 `selectedCourseID`, `isVideoPlayerFullScreen`）。
-   **`@Binding`**: 用於在父視圖（`ContentView`）和子視圖（`VideoRowView`）之間傳遞可變狀態的引用，例如影片的註解或觀看狀態。
-   **`ObservableObject`**: `CourseManager` 遵循此協議，使其能夠在 `@Published` 的 `courses` 屬性變更時通知 SwiftUI 更新相關視圖。

---

## 3. 資料模型與持久化

### 3.1. 資料結構 (`Models.swift`)

-   **`Course`**: 代表一個課程，對應一個子資料夾。包含 `id`, `folderURL` 和一個 `videos` 陣列。
-   **`VideoItem`**: 代表一個 `.mp4` 影片檔案。
    -   `id`: 唯一標識符。
    -   `fileName`: 影片的原始檔名，作為與檔案系統關聯的關鍵。
    -   `displayName`: 可由使用者編輯的顯示名稱。
    -   `note`: 可由使用者編輯的註解，預設為檔名。
    -   `watched`: 布林值，標記影片是否已觀看。
    -   `date`: 從檔名中自動解析出的日期，用於排序。

### 3.2. 資料持久化

-   每個課程資料夾內都會儲存一個 `videos.json` 檔案。
-   這個 JSON 檔案儲存了該課程所有 `VideoItem` 的陣列，包含了使用者修改過的 `displayName`, `note` 和 `watched` 狀態。
-   當應用程式載入一個課程的影片時，它會：
    1.  讀取 `videos.json` 檔案（如果存在）。
    2.  掃描資料夾中的所有 `.mp4` 檔案。
    3.  將掃描結果與從 JSON 讀取的資料進行比對和合併，以確保檔案系統的變動（新增/刪除影片）能被正確反映，同時保留使用者的編輯。
    4.  任何對影片狀態的修改（如標記為已看、編輯註解）都會觸發 `saveVideos` 函式，將最新的資料寫回 `videos.json`。

---

## 4. 權限管理 (核心)

macOS 的沙盒機制要求應用程式必須明確獲得使用者授權才能存取檔案系統。本專案採用了**安全作用域書籤 (Security-Scoped Bookmarks)** 來實現持久化授權。

### 4.1. 運作流程

1.  **首次授權**: 當使用者第一次透過 `fileImporter` 選擇來源資料夾時，應用程式會請求對該資料夾的存取權限。
2.  **建立書籤**: 一旦獲得授權，應用程式會立即為該資料夾的 URL 建立一個安全作用域書籤，並將其儲存在 `UserDefaults` 中。
3.  **啟動時恢復權限**: 應用程式每次啟動時，會執行 `loadBookmark()`:
    -   從 `UserDefaults` 讀取書籤資料。
    -   使用書籤解析回安全的 URL，並**重新獲取該資料夾的存取權限**。
4.  **權限的持有與繼承**:
    -   **關鍵策略**：在 `loadBookmark()` 成功後，應用程式會呼叫 `url.startAccessingSecurityScopedResource()`，並且**在整個應用程式的生命週期內都持有此權限**。
    -   所有後續對該資料夾內部任何子目錄或檔案的存取（讀取課程、讀寫 `videos.json`、讀取影片進行播放）都會自動**繼承**這個已獲取的權限。
    -   這避免了在每次操作子目錄時都重複請求權限，從而解決了「無法取得安全作用域存取權限」的核心問題。
5.  **釋放權限**: 只有在應用程式即將關閉時（在 `ContentView` 的 `onDisappear` 修飾符中），才會呼叫 `stopAccessingSecurityScopedResource()` 來釋放權限。

### 4.2. 輔助權限檢查

-   `hasFullDiskAccess()`: 一個輔助函式，透過嘗試讀取一個受保護的系統目錄 (`~/Library/Application Support`) 來推斷應用程式是否擁有「完整磁碟取用權限」。
-   如果書籤載入失敗，或讀取目錄內容時發生錯誤，應用程式會顯示一個提示框，引導使用者前往「系統設定」手動授予權限。這為權限問題提供了一個備用的解決方案。
