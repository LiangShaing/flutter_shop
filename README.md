# Flutter 店家點餐 App

將舊店家代客點餐 App 重構為 Flutter，使用 SQLite 保存本機資料，並逐步加入 Supabase 同步。需求與詳細實作進度見 [SPEC.md](SPEC.md)。

## 目前功能

- 以舊版三欄菜單顯示品名、單價及數量；支援選餐、總額和已選品項調整。
- 可暫選內用／外帶／Uber、酸菜、薑絲、四級辣度及標註；選項尚未存入訂單。
- 可輸入實收金額並依總額顯示找零，僅供目前點餐流程暫存，並不代表已收款。
- 先讀取 SQLite 菜單；有連線時同步目前帳號可見的雲端菜單，顯示同步與 Realtime 狀態。
- 菜單改價或品項不再可見時保留已選價格並提示檢查。
- 已有 SQLite 訂單、明細及 outbox 資料層；既有雲端訂單列表可依 RLS 讀取。

購物籃、實收金額及點餐選項目前僅存在記憶體，重啟後清空；尚無實際收款、存單、訂單上傳、離線訂單查詢或列印功能。舊訂單僅記錄是否加辣，無法還原原本辣度級別。匿名菜單權限僅能讀取可供應且分類啟用的品項，不能將快取視為完整雲端菜單。

## 執行

安裝 Flutter 後執行 `flutter pub get`。未設定 Supabase 時可使用本機快取；首次離線啟動會載入 bundled 預設菜單。

連線到獨立的測試 Supabase 專案時，先依 [測試說明](supabase/TESTING.md) 套用 migration；如需初始化空菜單，可執行 [菜單 SQL](supabase/seed_menu.sql)。啟動時提供專案 URL 與 publishable key：

```bash
flutter run \
	--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
	--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

不可將 `service_role` key 放入 App。真實訂單的正式授權方案尚未確定，不應使用匿名測試政策存取真實訂單。

## 驗證

```bash
flutter analyze
flutter test
```
