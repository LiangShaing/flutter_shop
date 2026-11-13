# Flutter 店家點餐 App

將舊店家代客點餐 App 重構為 Flutter，使用 SQLite 保存本機資料，並逐步加入 Supabase 同步。需求與詳細實作進度見 [SPEC.md](SPEC.md)。

**階段目標已調整**：第一階段由單一店家裝置離線掃描顧客點餐 QR Code、結帳、存入 SQLite 並列印；顧客線上直接送單及雲端同步移至第二階段。QR 點餐頁、掃碼與列印尚未實作。

目前新存訂單已改由本機 SQLite 每日計數器分配正式流水號；第一階段不會自動或手動上傳訂單。既有 outbox 與待同步訂單會保留，不因階段切換刪除。顧客 QR、店家掃描及列印尚未實作，因此目前仍不是第一階段完整可正式使用的版本。

## 目前功能

- 以舊版三欄菜單顯示品名、單價及數量；支援選餐、總額和已選品項調整。
- 可選擇內用／外帶／Uber、酸菜、薑絲、四級辣度及標註，並輸入實收金額查看找零。
- 以 SQLite transaction 寫入訂單、品項快照及每日流水號計數；新訂單標示為本機存單，第一階段不會上傳。
- 可查看本機訂單與明細；存單不代表已實際收款或列印。
- 先讀取 SQLite 菜單；有連線時同步目前帳號可見的雲端菜單，顯示同步與 Realtime 狀態。
- 菜單改價或品項不再可見時保留已選價格並提示檢查。
- 已有 SQLite 訂單、明細及 outbox 資料層；既有雲端訂單列表可依 RLS 讀取。
- 已保留供第二階段**已登入且啟用的店家**使用的 outbox 上傳與雲端交易式配號；目前第一階段 App 不會呼叫，尚需在獨立測試專案套用 migration 並完成實際驗證。

未存單的購物籃與選項僅存在記憶體，重啟後清空。新存訂單依台灣時間下單日由 10 起算，計數器與存單同一 SQLite transaction 更新，刪除訂單不會回退號碼。舊階段留下的待同步訂單及 outbox 會保留，但第一階段不會上傳或改號。**目前 App 尚無登入 UI 或建立店家 session 的方式**；真實 Supabase、多連線配號、顧客 QR 端整合、實際收款及列印尚未完成驗證或實作。舊訂單僅記錄是否加辣，無法還原原本辣度級別。匿名菜單權限僅能讀取可供應且分類啟用的品項，不能將快取視為完整雲端菜單。

## 執行

安裝 Flutter 後執行 `flutter pub get`。未設定 Supabase 時可使用本機快取；首次離線啟動會載入 bundled 預設菜單。

連線到獨立的測試 Supabase 專案時，先依 [測試說明](supabase/TESTING.md) 套用 migration；如需初始化空菜單，可執行 [菜單 SQL](supabase/seed_menu.sql)。啟動時提供專案 URL 與 publishable key：

```bash
flutter run \
	--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
	--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

不可將 `service_role` key 放入 App。不應使用匿名測試政策存取真實訂單；店家 session 的取得／復原及正式安全驗證仍須完成後才能正式使用。

## 驗證

```bash
flutter analyze
flutter test
```
