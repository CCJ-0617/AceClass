# AceClass 使用者手冊

一個專為 macOS 設計的補課影片管理應用程式，幫助您輕鬆整理和觀看儲存在外部驅動器上的課程影片，並提供倒數計日功能來追蹤學習進度。

## 🚀 功能特色

- 📁 **智能課程掃描** - 自動識別資料夾結構並建立課程清單
- 🎥 **影片播放管理** - 內建播放器支援全螢幕播放
- ✅ **觀看狀態追蹤** - 標記已觀看的影片，記錄學習進度
- 📝 **筆記功能** - 為每個影片添加個人註解
- 📊 **學習統計** - 顯示課程進度和未觀看影片
- ⏰ **倒數計日管理** - 設定課程目標日期，追蹤學習進度
- 🔄 **資料同步** - 本地儲存元數據，並嘗試同步到外部裝置

## ⚙️ 系統需求

- macOS 15.4 或更新版本
- 支援 .mp4 格式的影片檔案

## 📖 快速開始指南

### 第一步：選擇課程資料夾

首次啟動應用程式時：

1. 點擊「選擇資料夾」按鈕
2. 選擇包含您課程影片的根資料夾
3. 授予應用程式存取權限

### 第二步：瀏覽課程

- 左側欄顯示所有檢測到的課程（子資料夾）
- 點擊課程名稱以瀏覽該課程的影片清單
- 影片會依照檔名中的日期自動排序
- 設定了倒數計日的課程會顯示倒數天數資訊

### 第三步：播放影片

- 點擊影片名稱開始播放
- 使用 `Cmd+Ctrl+F` 快捷鍵切換全螢幕模式
- 已觀看的影片會自動標記為已看

### 第四步：管理影片資訊

- **編輯顯示名稱**：點擊影片名稱旁的編輯按鈕
- **添加註解**：在註解欄位輸入個人筆記
- **標記觀看狀態**：手動切換已看/未看狀態

## ⏰ 倒數計日功能完全指南

### 設定課程目標日期

1. 選擇要設定目標的課程
2. 點擊工具欄中的齒輪圖標（⚙️）
3. 在設定視窗中：
   - 啟用「設定目標日期」開關
   - 選擇目標完成日期
   - 輸入目標描述（如：期末考試、作業截止等）
   - 或使用快速設定按鈕選擇常見時間間隔
4. 點擊「保存設定」或「完成」

### 查看倒數計日資訊

- **課程列表顯示**：設定了目標日期的課程會在名稱下方顯示倒數計日資訊
- **顏色代碼**：
  - 🔵 藍色：正常倒數（超過3天）
  - 🟠 橙色：即將到期（3天內）
  - 🔴 紅色：已過期

### 倒數計日概覽

點擊工具欄中的日曆圖標（📅）查看全部倒數計日狀態：

- **即將到期課程**：7天內到期的課程
- **已過期課程**：已超過目標日期的課程
- **所有目標課程**：已設定目標日期的所有課程
- **課程進度**：顯示每個課程的觀看進度（已觀看/總數）

### 快速設定選項

提供以下預設時間間隔：

- 1週（7天）
- 2週（14天）
- 1個月（30天）
- 2個月（60天）
- 3個月（90天）
- 6個月（180天）

### 倒數計日最佳實踐

1. **設定實際可達成的目標**：根據課程內容和個人時間安排設定合理的完成日期
2. **SMART 原則**：設定具體、可測量、可達成、相關且有時限的目標
3. **緩衝時間**：在實際截止日期前 2-3 天設定目標，留出調整空間
4. **定期檢查進度**：使用概覽功能查看所有課程的學習狀態
5. **靈活調整目標**：可隨時修改目標日期和描述
6. **關注即將到期的課程**：優先完成即將到期的課程

### 目標描述技巧

- **具體說明**：如「期末考試 - 第5-8章」而非僅「考試」
- **包含里程碑**：「週四測驗準備 + 週末複習第3章」
- **連結動機**：「求職面試準備 - Python 基礎必須熟練」
- **標示重要性**：「⭐ 必須完成」或「📚 可選進階」

## 📁 資料夾結構範例

```
課程根資料夾/
├── 數學課程/
│   ├── 20250101_第一堂課.mp4
│   ├── 20250102_第二堂課.mp4
│   └── videos.json (自動生成)
├── 英文課程/
│   ├── 20250101_文法課.mp4
│   ├── 20250103_聽力練習.mp4
│   └── videos.json (自動生成)
└── 科學課程/
    ├── 20250105_物理實驗.mp4
    └── videos.json (自動生成)
```

### 檔案命名建議

- **日期格式**：使用 `YYYYMMDD` 格式確保正確排序
- **描述性名稱**：包含課程主題或章節號
- **版本控制**：如有多個版本，使用 `v1`、`v2` 後綴
- **避免特殊字元**：不使用 `/`、`:`、`*` 等特殊符號

## 🔒 權限與隱私

AceClass 需要以下權限以正常運作：

- **檔案存取權限** - 讀取您選擇的課程資料夾中的影片
- **資料寫入權限** - 儲存觀看記錄、註解和倒數計日設定

> 📌 **隱私保護**：應用程式只會存取您明確選擇的資料夾，不會掃描其他系統檔案。

### 資料安全保證

- **本地儲存**：所有資料都儲存在您的 Mac 上
- **沙盒保護**：應用程式在 macOS 沙盒環境中執行
- **隱私保護**：不會收集或傳送任何使用者資料
- **權限最小化**：只請求必要的檔案存取權限

## 💾 資料儲存方式

### 本地儲存（主要）

您的觀看記錄、註解和倒數計日設定會安全地儲存在：

```
~/Library/Containers/ChenChiJiun.AceClass/Data/Library/Application Support/AceClass/
├── Courses/
│   ├── [CourseID]_videos.json      # 影片資訊和觀看記錄
│   └── course_metadata_[CourseID]  # 倒數計日設定（UserDefaults）
```

### 外部同步（輔助）

應用程式會嘗試在每個課程資料夾中建立 `videos.json` 檔案，以便在不同裝置間同步觀看記錄。倒數計日設定僅存放在本地。

## 💡 使用技巧與學習管理

### 課程組織管理

#### 1. 資料夾結構最佳實踐

- 每個課程使用獨立的子資料夾
- 使用清晰的課程命名方式
- 定期整理和分類課程內容

#### 2. 學習記錄管理

- **即時標記**：觀看完畢立即標記為已看
- **詳細註解**：記錄重要概念、疑問點、實作心得
- **定期複習**：使用統計功能檢查未完成的課程
- **交叉參考**：在註解中連結相關課程或外部資源

### 進階功能運用

#### 1. 多裝置協作

儘管倒數計日設定無法跨裝置同步，您仍可透過以下方式協調：

- **主要裝置**：在主要學習的 Mac 上設定所有倒數計日
- **次要裝置**：僅用於觀看影片，會自動同步觀看記錄
- **手動同步**：使用雲端筆記或待辦事項 App 記錄重要目標日期

#### 2. 與其他工具整合

- **行事曆應用**：將重要目標日期加入系統行事曆
- **筆記軟體**：將 AceClass 的學習記錄整合到 Notion、Obsidian 等
- **時間管理**：配合番茄鐘技術，每 25 分鐘暫停並記錄學習心得
- **任務管理**：使用 Things、Todoist 等 App 追蹤學習任務

### 學習進度追蹤

#### 1. 設定學習里程碑

- **週目標**：每週設定要完成的課程數量
- **月目標**：每月設定要掌握的技能或章節
- **專案導向**：以完成特定專案為目標設定學習計劃
- **考試準備**：根據考試日期倒推設定各階段目標

#### 2. 進度監控技巧

- **視覺化追蹤**：利用顏色編碼快速識別學習狀態
- **數據分析**：定期檢查觀看進度統計，了解學習效率
- **問題記錄**：在影片註解中記錄不理解的部分，安排複習時間
- **成果驗證**：觀看後進行小測試或實作練習驗證理解程度

## 🔧 常見問題與故障排除

### 基本使用問題

#### Q: 為什麼有些影片無法播放？

A: 請檢查以下項目：

- 確認影片格式為 .mp4
- 檢查檔案是否損壞（可嘗試用其他播放器開啟）
- 驗證應用程式是否有足夠的權限存取該資料夾
- 重新啟動應用程式並重新授權資料夾

#### Q: 為什麼應用程式無法掃描到課程？

A: 可能的原因和解決方案：

- **資料夾結構不正確**：確保每個課程是一個獨立的子資料夾
- **權限問題**：嘗試重新選擇資料夾並授權
- **資料夾為空**：確認子資料夾中包含 .mp4 檔案
- **隱藏檔案**：檢查是否有隱藏的系統檔案影響掃描

#### Q: 如何重新選擇課程資料夾？

A: 點擊左上角的「選擇資料夾」按鈕，選擇新的根資料夾即可。應用程式會自動載入新資料夾的內容。

### 倒數計日相關問題

#### Q: 我的倒數計日設定會遺失嗎？

A: 倒數計日設定儲存在本地系統中（macOS UserDefaults），具有以下特性：

- **不會隨意遺失**：設定會持久保存在系統中
- **裝置獨立**：每台 Mac 的設定是獨立的
- **應用程式綁定**：重新安裝應用程式會清除設定
- **備份建議**：建議記錄重要的目標日期，以備不時之需

#### Q: 倒數計日顯示的天數不正確？

A: 請檢查以下項目：

- **系統時間**：確認 Mac 的系統時間和時區設定正確
- **日期格式**：檢查是否選擇了正確的目標日期
- **應用程式重啟**：嘗試重新啟動應用程式
- **重新設定**：刪除並重新設定該課程的目標日期

#### Q: 可以同時在多台電腦上使用嗎？

A: 不同類型的資料有不同的同步行為：

- **觀看記錄**：可以透過外部硬碟上的 `videos.json` 檔案同步
- **影片註解**：與觀看記錄一同同步
- **倒數計日設定**：僅存在本地，無法跨裝置同步
- **建議做法**：在主要使用的電腦上設定倒數計日

#### Q: 倒數計日設定可以匯出或備份嗎？

A: 目前倒數計日設定存放在 macOS 的 UserDefaults 中，儲存位置為：

```
~/Library/Containers/$UserName$.AceClass/Data/Library/Preferences/ChenChiJiun.AceClass.plist
```

您可以：

- **手動備份**：複製上述 plist 檔案
- **截圖記錄**：對設定畫面截圖備份
- **文字記錄**：手動記錄重要的目標日期
- **未來版本**：我們計劃在未來版本中支援設定匯出功能

#### Q: 可以設定多個目標日期嗎？

A: 目前每個課程只能設定一個目標日期。如需追蹤多個里程碑，建議：

- 在目標描述中詳細說明多個階段目標
- 設定最重要或最緊急的截止日期
- 完成一個目標後更新為下一個目標日期

### 技術問題

#### Q: 為什麼應用程式啟動時無法存取之前選擇的資料夾？

A: 這通常是 macOS 安全機制相關的問題：

- **權限過期**：重新選擇資料夾並授權
- **外部裝置斷開**：確認外部硬碟已正確連接
- **裝置名稱變更**：硬碟重新命名後需要重新授權
- **系統更新**：macOS 更新後可能需要重新授權

#### Q: 影片播放時出現效能問題？

A: 優化建議：

- **檔案大小**：過大的影片檔案可能影響播放流暢度
- **系統資源**：關閉其他佔用記憶體的應用程式
- **硬碟速度**：使用 USB 3.0 或更快的外部硬碟
- **檔案完整性**：檢查影片檔案是否完整無損

#### Q: 應用程式突然停止回應？

A: 故障排除步驟：

1. **強制退出**：按 `Cmd+Option+Esc` 強制退出應用程式
2. **重新啟動**：重新開啟應用程式
3. **重新授權**：重新選擇並授權資料夾
4. **系統重啟**：如問題持續，嘗試重啟 Mac
5. **聯繫支援**：如問題無法解決，請提供詳細的錯誤資訊

### 資料安全相關

#### Q: 我的觀看記錄和設定資料安全嗎？

A: AceClass 的資料安全措施：

- **本地儲存**：所有資料都儲存在您的 Mac 上
- **沙盒保護**：應用程式在 macOS 沙盒環境中執行
- **隱私保護**：不會收集或傳送任何使用者資料
- **權限最小化**：只請求必要的檔案存取權限

#### Q: 解除安裝應用程式後資料會如何？

A: 解除安裝的影響：

- **觀看記錄**：外部硬碟上的 `videos.json` 會保留
- **倒數計日設定**：本地設定會被清除
- **應用程式資料**：`~/Library/Containers/ChenChiJiun.AceClass/` 目錄會被移除
- **建議**：重要設定請先備份再解除安裝

## 🛠️ 技術支援與診斷

### 自助診斷步驟

如果您遇到問題，請按照以下步驟進行診斷：

#### 1. 基本檢查清單

- [ ]  確認 macOS 版本為 15.4 或更新
- [ ]  檢查影片檔案格式為 .mp4
- [ ]  驗證資料夾結構正確（每個課程一個子資料夾）
- [ ]  確認系統時間和時區設定正確
- [ ]  檢查是否有足夠的磁碟空間

#### 2. 權限診斷

如果出現檔案存取問題：

```bash
# 檢查應用程式沙盒狀態（在終端機執行）
ls -la ~/Library/Containers/ChenChiJiun.AceClass/
```

#### 3. 重置步驟

當應用程式行為異常時：

1. **軟重置**：重新啟動應用程式
2. **重新授權**：重新選擇資料夾並授權
3. **清除快取**：刪除 `~/Library/Containers/ChenChiJiun.AceClass/Data/Library/Application Support/AceClass/`
4. **完全重置**：重新安裝應用程式（會清除所有本地設定）

#### 4. 效能最佳化建議

- 使用 SSD 硬碟以獲得更好的載入速度
- 定期整理課程資料夾，移除不需要的檔案
- 避免在同一資料夾中放置過多課程（建議少於 50 個）
- 確保影片檔案大小適中（建議單檔小於 2GB）

### 錯誤代碼參考

如果出現錯誤對話框，請參考以下代碼含義：


| 錯誤代碼  | 含義               | 解決方案             |
| --------- | ------------------ | -------------------- |
| FILE_001  | 檔案存取權限不足   | 重新授權資料夾       |
| FILE_002  | 檔案不存在或已損壞 | 檢查檔案完整性       |
| DATE_001  | 日期解析失敗       | 檢查檔名格式是否正確 |
| STORE_001 | 本地儲存寫入失敗   | 檢查磁碟空間和權限   |
| PLAY_001  | 影片解碼失敗       | 確認影片格式和編碼   |

### 聯繫支援

如果上述步驟無法解決您的問題，請提供以下資訊：

#### 必要資訊

- macOS 版本
- AceClass 應用程式版本
- 問題的詳細描述
- 重現問題的步驟
- 錯誤訊息截圖（如有）

#### 可選資訊（有助於快速診斷）

- 課程資料夾的大致結構
- 影片檔案的命名格式範例
- 問題發生的頻率
- 最近是否有系統更新

#### 聯繫方式

- **GitHub Issues**: [在此回報問題](https://github.com/your-repo/AceClass/issues)
- **電子郵件**: support@aceclass.app
- **文檔**: 查看開發者文檔 `DEVELOPER_GUIDE.md`

#### 隱私聲明

我們承諾：

- 不會要求您提供課程內容或個人學習資料
- 所有診斷資訊僅用於問題排解
- 您的使用習慣和檔案路徑等敏感資訊會被匿名化處理

## 📈 版本更新記錄

### v1.1 (2025年7月) - 倒數計日功能重大更新

#### 🎯 新功能

- **倒數計日管理系統**：為每個課程設定目標完成日期
- **三級狀態提醒**：正常（藍色）、即將到期（橙色）、已過期（紅色）
- **快速設定選項**：1週、2週、1個月、2個月、3個月、6個月預設選項
- **倒數計日概覽**：統一查看所有課程的目標狀態和學習進度
- **目標描述功能**：為每個目標添加詳細說明（如：期末考試、作業截止等）

#### 🔧 介面改進

- **專用設定界面**：CountdownSettingsView 提供完整的倒數計日設定功能
- **統一概覽界面**：CountdownOverviewView 顯示所有課程的倒數計日狀態
- **工具欄整合**：在主界面新增齒輪（設定）和日曆（概覽）按鈕
- **視窗尺寸最佳化**：調整最小視窗和 Sheet 尺寸改善使用體驗

#### 🛠️ 技術改進

- **macOS 相容性修復**：移除 iOS 專用元件，確保 macOS 完美執行
- **效能最佳化**：計算屬性實現即時的倒數計日更新
- **資料安全**：使用 macOS UserDefaults 確保設定安全存儲

### v1.0 (2025年6月) - 初始版本

#### 🎉 核心功能

- **智能課程掃描**：自動識別資料夾結構並建立課程清單
- **影片播放管理**：內建 AVPlayer 支援全螢幕播放
- **觀看狀態追蹤**：標記已觀看的影片，記錄學習進度
- **筆記功能**：為每個影片添加個人註解
- **學習統計**：顯示課程進度和未觀看影片統計
- **資料同步**：本地儲存元數據，並嘗試同步到外部裝置

---

**目前版本**: v1.1
**系統需求**: macOS 15.4+
**架構支援**: Apple Silicon (M1/M2/M3) & Intel

---

> 💡 **提示**：如需技術細節和開發相關資訊，請參考 `DEVELOPER_GUIDE.md`
