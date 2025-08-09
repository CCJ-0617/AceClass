# To-Do

## Immediate Tasks
1. Test the updated transcription logic with various locale combinations.
2. Verify that enabling Dictation and downloading language packs resolves remaining speech recognition issues.
3. (IN PROGRESS) 實作「影片續播與 75% 自動標記已看」功能（詳見下方說明）。
4. 新增：多語字幕後續強化與長影片最佳化（細節見下方新章節「多語字幕後續強化規劃」）。

## Future Enhancements
1. Add UI feedback for unsupported locales or missing language packs.
2. Optimize `mergeSegmentsByLanguage` for performance with large caption datasets.
3. Expand multilingual support to include additional languages if needed.
4. 多語字幕穩定化與長影片最佳化（詳見下方新章節）。

## Maintenance
1. Regularly update entitlements and ensure compatibility with macOS updates.
2. Monitor user feedback for further improvements in video playback and transcription.

---

## 詳細規格：影片續播與 75% 自動標記已看

### 目標
提供使用者「從上次播放位置繼續」的體驗，並避免只開啟影片就立刻被標記為已看。只有實際觀看達到 75% 以上才自動標記為已看，可手動覆寫。

### 資料模型
- `VideoItem` 已新增 `lastPlaybackPosition: Double?`（儲存最後播放秒數）。
  - 編碼/解碼：舊資料沒有此欄位時自動為 `nil`。
  - 影片時長於執行期由 `AVPlayerItem` 取得，不額外持久化。

### 邏輯流程
1. 使用者點擊影片：
   - 建立/指派共享 `AVPlayer`。
   - 若 `lastPlaybackPosition` 存在且 > 5 秒且 < 總長度 * 0.95，當可取得 duration 後自動 seek。
   - 顯示一次性提示：「從上次位置續播 mm:ss」。(已加到 UI 規劃)
2. 播放過程：
   - `addPeriodicTimeObserver` 每 5 秒觸發，更新記憶體中的 `lastPlaybackPosition`。
   - 當前播放進度 `currentTime / duration >= 0.75` 且 `watched == false` 時自動標記 `watched = true` 並立即保存。
3. 手動標記：
   - UI 勾選仍可即時切換，覆寫自動邏輯。
4. 切換影片 / 關閉播放器：
   - 移除 observer。
   - 強制最後一次保存（flush）。

### Debounce 寫入策略（本次新增）
- 目的：避免每 5 秒 I/O 寫檔。
- 規則：
  - 位置更新時只更新記憶資料；啟動一個 debounce（例如 12 秒）。
  - 若期間有新的更新，重設計時器。
  - 標記已看事件 -> 立即保存並取消 pending debounce。
  - 影片切換 / 停止播放 -> 立即 flush 保存。
- 實作：使用可取消 Task；主執行緒上排程。

### UI 提示
- 在成功 seek 後 5 秒內顯示角落浮層：「從上次位置續播 12:34」。
- 超時或未觸發續播（無保存位置 / 太短 / 接近結尾）不顯示。

### 邊界條件
- 無法取得 duration 或 duration==0 -> 不做 75% 判斷，只更新位置。
- 使用者已達 75% 且離開 → 下次仍為已看，不反向回退。
- 使用者手動取消已看 → 再次達 75% 重新標記。
- Very short (< 10s) 影片：仍可記錄位置，但 75% 很快完成屬預期。

### 儲存與一致性
- Debounce 寫入僅延後保存；程式意外結束可能遺失最後一次 < debounce 間隔的進度（可接受）。
- 若要降低風險，可縮短間隔或在進入前景 / 退到背景時觸發 flush（後續可加）。

### 驗收標準 (Acceptance Criteria)
- [ ] 重新開啟應用後，影片自動續播位置正確 (±2s 內)。
- [ ] 觀看 < 75% 不自動標記。
- [ ] 觀看 >= 75% 自動標記並持久化。
- [ ] 手動切換已看狀態優先生效。
- [ ] 切換影片不造成 crash / observer 泄漏。
- [ ] Debounce 寫入不高於平均每 10~15 秒一次（無大量切換）。
- [ ] 顯示續播提示僅在符合條件時出現並自動消失。

### 後續可考慮
- 前景 / 背景轉換時強制 flush。
- 使用 App 生命週期通知再加一層保護。
- 使用小型 SQLite 或 CoreData 儲存避免整包 JSON 重寫（大量影片時）。
- 「從頭播放」按鈕覆寫續播。

---

## 多語字幕後續強化規劃（新增）

### 核心目標
提高長影片與多語（中+英）字幕辨識的成功率、速度、與資源使用效率，並提供更可診斷的錯誤回饋。

### 現況摘要
- 已具備：M4A 轉碼、條件式分段、超長檔案強制分段(≥15m)、120s 部分分析、180s 超時計時、語言合併初版。
- 問題：極長影片偶發 0 結果；分段長度固定（300s）非最佳；缺少 temp 清理與錯誤分類；部分情境整檔仍嘗試導致浪費時間。

### 拆解項目
1. 自適應分段長度 (180~360s) 依 RMS / 語音密度調整。
2. 超長閾值二階策略：>25m 直接跳 segmentation；>90m 使用更短段。
3. 分段並行上限 (2~3) + 任務排程。
4. 單段空結果一次輕量重試（shift +1s）。
5. Temp 檔案生命週期管理（集中追蹤 + 清理統計）。
6. 錯誤分類 enums：timeout / noSpeech / openFail / authorization / unknown。
7. Coverage 指標 <5% 觸發降級策略（縮短段長或重新取樣）。
8. 分段前後靜音裁切與微重疊 (0.3~0.5s)。
9. UI 進度回饋（已完成段數 / 總段數 + 估計剩餘時間）。
10. 語言合併精緻化（詞元覆蓋率、CJK 與 Latin token 權重調整）。
11. 記憶體壓力監測：必要時降低並行度或縮短段長。
12. 雲端模式提示與隱私說明彈層。
13. 最後失敗段 debug 快照（RMS/長度/起訖時間）。
14. 自動清理策略：轉譯完成後刪除 >95% 臨時檔，保留最近 N 個供 debug。

### 里程碑建議
- M1（功能可用）：項目 1,2,5,6 基礎 + 進度回饋初版。
- M2（可靠與效能）：項目 3,4,7,8,11。
- M3（體驗與觀測）：項目 9,12,13,14,10 優化。

### 驗收指標
- 2 小時影片完整字幕時間 < 15 分鐘。
- 首次成功率（非空結果）≥ 95%。
- 平均臨時檔清理率 ≥ 95%。
- Timeout 占比 < 3%。
- 使用者回報空字幕案例下降 80%。

---