# Flutter 店家點餐 App

將舊店家代客點餐 App 重構為 Flutter，使用 SQLite 保存本機資料，並逐步加入 Supabase 同步。需求與詳細實作進度見 [SPEC.md](SPEC.md)。

## 目前功能

- 以舊版三欄菜單顯示品名、單價及數量；支援選餐、總額和已選品項調整。
- 可選擇內用／外帶／Uber、酸菜、薑絲、四級辣度及標註，並輸入實收金額查看找零。
- 可將訂單、品項快照和待同步操作交易式存入 SQLite，並查看本機訂單與明細；存單不代表已實際收款或上傳。
- 先讀取 SQLite 菜單；有連線時同步目前帳號可見的雲端菜單，顯示同步與 Realtime 狀態。
- 菜單改價或品項不再可見時保留已選價格並提示檢查。
- 已有 SQLite 訂單、明細及 outbox 資料層；既有雲端訂單列表可依 RLS 讀取。
- 已實作供**已登入且啟用的店家**使用的 outbox 上傳與雲端交易式配號；尚需在獨立測試專案套用 migration 並完成實際驗證。

未存單的購物籃與選項僅存在記憶體，重啟後清空。已存本機的訂單會標示「待同步」與暫定流水號；每日以台灣時間下單日從 10 起算，但暫號可能與線上訂單重複。雲端確認後本機顯示正式流水號並保留原暫號。**目前 App 尚無登入 UI 或建立店家 session 的方式**，首次安裝無法自行登入上傳；真實 Supabase、多連線配號、顧客 QR 端整合、實際收款及列印尚未完成驗證或實作。舊訂單僅記錄是否加辣，無法還原原本辣度級別。匿名菜單權限僅能讀取可供應且分類啟用的品項，不能將快取視為完整雲端菜單。

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
