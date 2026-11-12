# Flutter 店家點餐 App 重構規格

## 文件狀態

- 版本：Draft 0.2
- 目標專案：`flutter_shop`
- 舊專案來源：`/Users/css_mac_m2/Documents/GitHub/shop_app`
- 配套總體規劃：[REQUIREMENTS.md](REQUIREMENTS.md)
- 本 SPEC 以已檢視的舊專案程式碼與使用者最新決定為基準；未確認的行為標示為待決，不自行補成既有規則。

## 1. 目標與決策

將現有店家代客點餐 App 重構至本 Flutter 專案，保留日常點餐、訂單查詢/修改、列印及菜單使用流程，並新增 Supabase 雲端同步和 SQLite 本機持久化。

| 項目 | 決定 |
| :--- | :--- |
| 雲端 | Supabase PostgreSQL 為跨裝置共享及同步的資料來源 |
| 本機資料庫 | SQLite；新專案不得使用 Realm |
| Flutter SQLite 套件 | 初期採 `sqflite`，schema 以版本 migration 管理 |
| 本機資料 | 菜單、訂單、訂單明細、同步佇列及同步狀態均持久化在 SQLite |
| 雲端更新 | Supabase Realtime 事件更新 SQLite；重連時重新抓取/核對雲端快照 |
| App 登入 | 第一階段不製作登入 UI；真實訂單的正式授權方案仍須在上線前決定 |

### 舊系統現況

- 舊專案使用 Realm `Configuration.local` 儲存菜單與訂單。
- 舊專案的 `SyncDB` mixin 沒有啟用遠端同步程式碼；現況不是 Realm Device Sync 或 Supabase 同步。
- 菜單會在 Realm 為空時由 `assets/data/shopMenuItem.json` 載入。
- 因此 SQLite 與 Supabase 同步是新能力，不能視為從舊專案直接移植而來。

## 2. 範圍

### 第一階段要做

- 使用 SQLite 取代 Realm，保存菜單及訂單資料，App 關閉或重啟後資料仍在。
- 以舊菜單分列方式顯示可供應品項，支援選餐、數量、總額及舊訂單選項。
- 建立、查看、修改、刪除店員代客訂單。
- 訂單依日期範圍、Uber 標記及訂單標註搜尋，並可彙總查詢期間的訂單金額。
- Supabase 菜單或訂單資料更新後，將新增/修改/刪除同步反映到 SQLite。
- 網路中斷時使用 SQLite 內可用菜單及既有訂單；新建或修改的訂單寫入本機同步佇列，恢復連線後重試。
- 顯示雲端連線與本機待同步狀態。
- 保留藍牙熱感機列印流程；列印與存單次序依第 8 節的差異決策處理。

### 第一階段不做

- 顧客 QR 點餐網站、金流、電子發票及多門市管理。
- 新增店家登入 UI。
- 在未確認資料匯出方式前，自動讀取或轉換舊裝置 Realm 檔案。

## 3. 舊系統已確認功能

以下是從 `shop_app` 程式碼觀察到的行為，搬遷時應保留或將差異明確列出：

### 菜單

- 菜單包含 `sid`、`type`、`row`、`name`、`subName`、`price`、`disabled` 及 Mongo ObjectId。
- `row` 為字串分列（目前程式使用 `1`、`2`、`3`），各列依 `sid` 排序；`type` 有 `product`、`mainProduct`、`other` 等值。
- 品項名稱可附帶 `subName`；價格以整數處理；`disabled` 表示不可供應。
- 長按品項可修改 `name`、`subName`、`price`；目前有未清空購物選項時禁止修改的防護。
- Realm 菜單為空時從 bundled JSON 重建；此重置方式不可在同步後不經確認覆蓋雲端菜單。

### 點餐與訂單

- 訂單包含 `takeout`、`serial`、`totalPrice`、`getPay`、`sauerkraut`、`ginger`、`chili`、`orderDate`、`itemList`、`uber`、`mark`。
- 訂單明細保留 `sid`、`type`、`name`、`showName`、`price` 與 `count`；只將已選品項放進新訂單。
- 總價為各品項 `price × count` 加總；金額及單價目前用整數。
- 有內用、外帶及 Uber 點餐選項；記錄實收金額與文字標註。
- 訂單流水號依當日最大流水號加一，起始底值為 10；日期界線目前使用裝置本地日曆日，需在搬遷時確認一致性。
- 訂單詳細資料包含日期、類型、總額、實收金額、酸菜/薑絲/辣度與品項；支援修改及確認後刪除。
- 歷史查詢支援日期區間、Uber 篩選及標註文字部分比對；可計算目前查詢結果的總金額。

### 列印

- 舊 App 使用藍牙熱感機，列印顧客收據與依 `type` 分組的備餐單，包含品項、數量、總額及備註選項。
- 印表機未連線或列印失敗時，店員可選擇略過列印並完成存單。
- 舊程式的備餐單呼叫列印兩次；需確認這是刻意的份數需求，不能在新 App 默默改成一次。

## 4. SQLite 本機資料

新 App 一律使用 SQLite，不引入 Realm。初期至少需要以下本機資料：

- `menu_items`：雲端/舊系統識別碼、`sid`、`type`、`row`、名稱、副名稱、整數價格、供應狀態、遠端更新時間。
- `orders`：UUID、舊 ObjectId、訂單欄位、建立/更新時間、同步狀態。
- `order_items`：關聯訂單、舊品項欄位、送單當下名稱/顯示名稱/單價/數量快照。
- `sync_outbox`：本機待上傳操作、穩定操作 UUID、重試次數、錯誤與建立時間。
- `sync_metadata`：各資料集合最後成功同步時間/版本等資訊。

SQLite 必須啟用 foreign keys；寫入一筆訂單及其所有明細、outbox 操作應在同一個 SQLite transaction 完成。訂單明細名稱與價格是歷史快照，菜單後續更新不可回寫舊訂單的快照。

### 首次啟動與菜單初始化

1. 先載入 SQLite 菜單，讓畫面可立即顯示本機資料。
2. 有網路時向 Supabase 取得最新菜單並交易式更新 SQLite。
3. 若是首次啟動且 SQLite、Supabase 都無菜單，才可用 bundled JSON 作為本機初始菜單；不可把預設 JSON 無條件覆蓋已有雲端資料。
4. 離線首次啟動時可用 bundled JSON 建立暫存菜單，待雲端恢復後依明確規則合併或以雲端版本取代，需標示資料來源。

## 5. Supabase 與同步規則

### 雲端資料表

- `menu_items`：須能映射舊菜單欄位及供應狀態。
- `orders`、`order_items`：保存訂單及明細，遠端 UUID 是新系統識別碼；Mongo ObjectId 以 nullable `legacy_id` 保存。
- 若分類表不是舊菜單實際概念，不得用分類重構取代 `row` 分列，除非另經確認。

現有初始 migration 只把 `orders` 加入 Realtime publication。實作完整菜單及訂單明細同步前，需新增 migration 將 `menu_items`、`order_items`（以及實際使用的分類表）加入 publication，並補足 `updated_at`、冪等寫入鍵與必要 RLS policy；已套用的 migration 不可直接改寫，應新增後續 migration。

### 同步流程

1. App 啟動後先從 SQLite 顯示菜單及訂單快取，不等待網路請求才進入主畫面。
2. 連線後開始接收 Supabase Realtime 變更並抓取完整/分頁快照；初始抓取完成後以 SQLite transaction 套用資料。
3. 收到 `INSERT`/`UPDATE` 時，依遠端 UUID upsert 對應 SQLite row；收到 `DELETE` 時移除或依核定的軟刪除規則標記本機資料。
4. `orders` 與 `order_items` 事件需以遠端 UUID 關聯；遠端訂單和其明細寫入本機時須保持 transaction 一致，畫面不得出現只更新主檔、明細仍舊的中間狀態。
5. Realtime 斷線、App 回到前景或最後同步時間過舊時重新抓取雲端快照，補足漏掉的事件；不能只依賴 WebSocket 事件。
6. 同一事件可能重送；所有套用與重試操作必須可冪等執行。
7. 雲端是共享資料的權威來源。雲端菜單更新套用至 SQLite；離線期間本機建立的訂單先標記 `PENDING_SYNC`，同步成功後標記 `SYNCED`。
8. 雲端菜單價格/供應狀態與本機待送訂單不一致時，不得靜默改動已確認訂單；須保留送單快照並提示需處理的衝突。

## 6. 欄位映射

| 舊 Realm 欄位 | 新 SQLite/Supabase 欄位 | 規則 |
| :--- | :--- | :--- |
| 菜單 `_id` / 訂單 `_id` / 明細 `_id` | `legacy_id` | 保存舊 Mongo ObjectId 字串；新系統另用 UUID 主鍵 |
| 菜單 `sid` | `sid` | 整數識別值；未確認唯一性/關聯前不加 unique 或 foreign key |
| 菜單 `type`、`row` | `item_type`、`menu_row` | 保留原值和分列順序 |
| 菜單 `name`、`subName` | `name`、`display_name` 或副名稱欄位 | 顯示組合方式待 UI 盤點確認，不丟棄副名稱 |
| 菜單 `price` | `price` | 整數，不轉為浮點金額 |
| 菜單 `disabled` | `is_available` | `is_available = !disabled` |
| 訂單 `totalPrice`、`getPay` | `total_price`、`get_pay` | 整數；保留原始值，不重新計算歷史訂單 |
| 訂單 `takeout`、`uber`、`mark` | 同名 snake_case 欄位 | 原值保留 |
| 訂單 `orderDate` | `order_date` | 儲存為 timestamptz；顯示時轉成本地時間並核對舊資料時區 |
| 訂單 `itemList` | `order_items` rows | 一筆明細對應一筆子表資料，保留當下品名、顯示名、價格及數量 |
| 訂單明細 `count` | `quantity` | nullable 舊值需盤點；不可未確認就轉成 0 或 1 |

### 已知資料差異

- 舊點餐 UI 有 0–3 辣度選擇，但 Realm `_Order.chili` 只保存 boolean；列印當下收到辣度數字。歷史資料無法從 boolean 還原辣度級別。新系統若要保存辣度級別，需另加 `chili_level` 並明確標示舊資料不可回復，不能假稱完全相容。
- 舊菜單編輯只修改本機 Realm 的 `name`、`subName`、`price`；新架構需明定菜單編輯要寫入 Supabase、僅本機暫存，或改成只讀雲端，第一階段採雲端成功後同步 SQLite。
- 舊系統資料存於各裝置 Realm；是否搬遷歷史訂單需另訂匯出、轉換、重複資料識別及筆數/金額核對程序。新 App 不得直接依賴 Realm 作為日常資料庫。

## 7. 無登入階段與安全限制

- 第一階段不製作登入 UI；這不代表可以公開真實訂單資料。
- 開發驗證僅能使用獨立測試 Supabase 專案及 `supabase/TESTING.md` 的 `[DEMO]` 匿名讀取政策。
- Supabase publishable key 可放在客戶端，但 `service_role` key 絕不可放入 App。
- 使用真實訂單前，必須先決定店家端授權方式（Supabase Auth 或受信任的伺服器/Edge Function）；在授權方式確定前，不得為了免登入而允許 `anon` 讀取所有 `orders` 或 `order_items`。

## 8. 與舊流程的行為差異及待決

任何重構差異都須記錄「舊行為、新行為、原因、店家核可、驗收案例」。以下項目在完成舊資料/營運確認前不得默默定案：

- 舊流程在列印成功後才寫入 Realm；未連線時店員可選擇略過列印後存單。新系統需先確保 SQLite 存單，再處理列印，否則列印等待或失敗可能遺失訂單；這會改變舊有先後順序，需在 UI 清楚呈現「已存單/列印狀態」。
- 備餐單目前呼叫兩次列印，需確認目標份數。
- `getPay` 的業務含義、Uber/內用/外帶各按鈕實際收款行為需核對；不可自行推定找零或付款狀態。
- 訂單刪除在舊系統是 Realm 實體刪除；雲端是否允許刪除、應改成取消/軟刪除，需確認後新增對應 RLS 與稽核規則。
- 日期範圍以裝置時區、序號每日重置方式及多人裝置同時建立訂單時如何避免重號需確認。現有「讀最大 serial 再加一」在多裝置/雲端競爭下不能保證唯一。
- 訂單中的 `chili` 舊資料只表示是否加辣；如需小/中/大辣，需新版欄位與舊資料相容規則。

## 9. 錯誤與狀態呈現

- 至少區分：本機快取、同步中、已同步、待同步、同步失敗、列印中、列印失敗/略過。
- Supabase 暫時不可用時仍可讀取 SQLite；重試失敗不得刪除 outbox 或本機訂單。
- 菜單更新只部分成功時以 transaction 套用完整資料集或保留前一版本，不顯示半套菜單。
- 同步錯誤須可重試，並保留可診斷錯誤資訊；不得把尚未同步的本機訂單顯示成雲端已接收。

## 10. 驗收條件

1. 新專案不依賴 Realm，重啟 App 後可由 SQLite 還原菜單和訂單。
2. 舊菜單欄位、分列順序、整數價格與停售狀態可正確轉換。
3. 店員可完成舊版核心代客點餐流程，總額及訂單快照符合已核定規則。
4. Supabase 新增或更新菜單/訂單後，SQLite 與畫面收到更新；刪除/停售依核定規則同步。
5. 斷線時可讀本機菜單及訂單；本機待同步訂單重啟後仍存在，連線恢復後不重複上傳。
6. 重複 Realtime 事件、斷線漏事件及 App 回到前景均可透過冪等套用和快照核對恢復一致。
7. 歷史查詢可依日期區間、Uber 及標註篩選，彙總金額符合舊規則。
8. 藍牙列印失敗或未連線不會遺失已存 SQLite 的訂單，且列印狀態可辨識。
9. 開發匿名政策只能讀 `[DEMO]` 假資料；測試結束後能按文件移除。
10. 若執行 Realm 舊資料匯入，匯入筆數、訂單總額、明細數與抽樣欄位均經核對。

## 11. 分階段交付

1. **資料層**：SQLite schema/migrations、JSON 初始菜單、欄位映射與資料庫測試。
2. **離線 UI**：菜單瀏覽、選餐、建立訂單、訂單明細、修改/刪除及歷史查詢全部以 SQLite 運作。
3. **雲端讀取同步**：Supabase 初始快照、菜單/訂單/明細 Realtime、SQLite transaction 套用與重連核對。
4. **雲端寫入與離線佇列**：本機 outbox、冪等重試、同步狀態和錯誤恢復。
5. **周邊功能**：藍牙列印、舊資料匯入及正式店家授權方案。

每一階段都需以已確認的舊流程為驗收基準，並在任何邏輯、欄位格式、必填條件或錯誤處理改變時記錄差異。