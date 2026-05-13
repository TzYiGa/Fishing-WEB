# 歷史版本紀錄表（釣魚地圖 `fishing_map`）

> **說明**  
> - 本表依 **Git 提交歷史**（`git log`）由舊到新整理；**未提交（uncommitted）** 的修改不會出現在下表，請在 commit 後自行補上一列。  
> - **應用版號**：`pubspec.yaml` 目前為 `1.0.0+1`；執行時顯示版號見 `lib/app_version.dart`（可由 `--dart-define=APP_VERSION=...` 注入）。  
> - Git 倉庫內目前**沒有** semver 標籤；下表「版本」欄為便於閱讀的**階段編號**，可與未來正式 tag 對齊。

---

## 總覽表（0 → 現在）

| 階段 / 版本 | 日期 | Commit | 摘要 |
|-------------|------|--------|------|
| **0 — 專案建立前** | — | — | 無版本控管之本地原型（敘述用起點；無 Git 紀錄）。 |
| **0.1 — 初版基線** | 2026-05-10 | `94f689a` | **Initial commit**：Flutter Web 釣魚地圖整包上架—Mapbox Web Canvas、`mapbox_gl_bridge.js`、地圖首頁、釣點 CRUD（Firestore）、分類篩選、CWA 潮位／浮標資料與圖示、Copernicus 海流向量資料與服務、釣點環境／Open‑Meteo 等服務、Auth／訪客流程、`firebase.json`／規則、`StationID.json`、Copernicus 向量匯出腳本與 GitHub Actions、管理員輔助腳本 `set-admin.js` 等。 |
| **0.1.1** | 2026-05-10 | `b2ac062` ~ `c79d132` | 移除誤提交的除錯產物（`flutter_01.log`、截圖、`flutter_02.log`）。 |
| **0.1.2** | 2026-05-10 | `16b6272` | 自版本庫刪除 `lib/firebase_options.dart`（改為本機產生／不進版控）。 |
| **0.1.3** | 2026-05-10 | `3a78da9` | 清理其他 Flutter 除錯產物追蹤。 |
| **0.1.4** | 2026-05-10 | `fd21051` | **Firebase 設定**：停止追蹤實際 `firebase_options`；新增 `lib/firebase_options.dart.example` 範本；`.gitignore` 調整。 |
| **0.1.5** | 2026-05-10 | `401c505`、`bcb544a` | **CI**：Copernicus 向量匯出改走 `copernicusmarine`、忽略 Python cache（兩筆提交訊息相同，可能為重試／重送）。 |
| **0.1.6** | 2026-05-10 | `3f7741c` | **CI**：還原 Copernicus 匯出腳本；Actions 需 CMEMS 相關 secrets。 |
| **0.1.7** | 2026-05-10 | `f31c9b1` | **資料**：更新台灣周邊 Copernicus 海流向量 JSON。 |
| **0.1.8** | 2026-05-10 | `91582b4` | **檢查點**：海流可見性修正前的 rollback 參考點。 |
| **0.2.0** | 2026-05-10 | `e10785a` | **Web / 海流**：地圖項目初始化海流屬性；建立 Mapbox 後與 bridge 同步。 |
| **0.2.1** | 2026-05-10 | `a93602d` | **Web / 海流**：在 `applySameStyleDelta` 中呼叫 `wfEnsureWindyFlow`（同 style 切換時仍能開啟海流）。 |
| **0.3.0** | 2026-05-10 | `450c799` | **除錯／營運**：僅管理員可見的 Web DEBUG 面板；Mapbox bridge 與 Dart 端動作日誌（`web_action_debug_log`、`mapbox_gl_bridge.js` 等）。 |
| **0.3.1** | 2026-05-10 | `bc5f6d0` | **除錯**：提早安裝 JS debug sink；Cursor 規則補充 `fmpDbg`。 |
| **0.3.2** | 2026-05-10 | `6705545` | **Web / 海流**：`map.project` 對應 canvas buffer 像素（HiDPR 下海流疊圖對位）。 |
| **0.3.3** | 2026-05-10 | `9e73bea` | **Web / 海流**：每個 RAF 影格快照 `prev_lng/lat`，可見流線動畫更穩定。 |
| **0.3.4** | 2026-05-10 | `093f40e` | **海流動畫**：以 anim-factor 切片每幀更新；`wf.tick`／advance 除錯。 |
| **0.4.0（目前 HEAD）** | 2026-05-10 | `f3d4beb` | **海流粒子**：粒子數與最小筆劃長度（依 buffer 縮放之 CSS px）。 |

---

## 初版（`94f689a`）功能模組一覽（對照「從零到有」）

以下為 **Initial commit** 已存在的主要能力，後續提交多在此之上疊代：

| 模組 | 說明 |
|------|------|
| 地圖 | `MapHomeScreen`、`FishingMapView`、Mapbox Web Canvas、互動 overlay |
| 釣點 | `FishingSpot`、`SpotRepository`、新增／詳情 sheet、留言與環境快照模型 |
| 資料層 | Firestore 規則、使用者設定 repository（初版較精簡） |
| 氣象／海洋 | CWA 測站載入、Open‑Meteo／環境擷取服務、Copernicus 向量與 polyline 工具 |
| 認證 | `AuthService`、`AuthScreen`、`AuthPopupPanel`、`FirebaseSetupScreen` |
| 建置／佈署 | `firebase.json`、`web/index.html`、`restart_web.ps1`、Copernicus `tool/` 與 CI workflow |

---

## 維護建議

1. **往後每次可釋出版**：在 `pubspec.yaml` 遞增 `version:`，並於本檔新增一列（或改以 Git tag 對應）。  
2. **重大功能**：在 PR／commit 訊息標註 `feat:`、`fix:`，便於自動生成變更摘要。  
3. **未納入 Git 的長期工作**：若你慣用大型本地 diff，建議分批 `git commit`，本表才有連續紀錄可查。

---

*本檔產生時之 HEAD：`f3d4beb`。*
