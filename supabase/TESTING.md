# Supabase 即時訂單測試

本文件只供**獨立的測試 Supabase 專案**使用。不要在含有真實顧客訂單的正式專案開啟匿名訂單讀取。

## 菜單同步

執行初始 migration 後，另在 Supabase SQL Editor 執行 `migrations/20261113000000_menu_realtime.sql`，將菜單與分類加入 Realtime publication。App 會先顯示 SQLite 快取，再分頁讀取雲端可見菜單；訂閱、回到前景、手動重試及定期核對會重新抓取快照。離線首次啟動使用 bundled 菜單，並標示為本機預設菜單。

目前匿名 RLS 只允許讀取可供應且分類啟用的菜單。雲端快取因此只代表目前帳號可見的品項，停售或被分類隱藏的品項會從快取移除，不能據此判斷雲端是否刪除；若需店家查看所有停售品項，須另設店家授權與政策。現有 `display_name` 暫存舊菜單的 `subName`，不是完整品名。菜單同步不會上傳菜單；訂單上傳另有以下店家授權限制。

若 Realtime 顯示 `channelError` 且分類為 `unclassified`，可在 debug 啟動指令中額外加入 `--dart-define=MENU_SYNC_VERBOSE_REALTIME_ERRORS=true`。新增或移除參數後需完整停止並重新啟動 App。詳細錯誤預設關閉，且只在 debug 模式輸出；雖然會遮罩常見憑證與 URL，仍可能包含其他敏感資料，分享 log 前請自行檢查及刪除敏感內容。排查完成後移除該參數。

## 前置條件

1. 已在測試 Supabase 專案執行 `migrations/20261112000000_initial_schema.sql`。
2. `public.orders` 已加入 `supabase_realtime` publication。初始 migration 已執行此設定。
3. Flutter App 使用該測試專案的 URL 與 publishable key 啟動。

## 店家訂單上傳與配號

此功能仍需在獨立測試專案完成實際 Supabase、帳號停用／過期、斷線重送及多連線測試，**不要直接套用到正式專案**。先依序套用初始 schema、菜單 Realtime migration，再執行 `migrations/20261113010000_merchant_order_submission.sql`。此 migration 建立依台灣下單日及流水號的唯一索引；執行前應先備份並檢查既有訂單，若有同日重號，migration 會失敗，不會自動改號：

該 migration 也將訂單總額、實收及明細數量擴充為 PostgreSQL `bigint`。若已有其他消費端，需先確認型別相容；JavaScript 對超過安全整數範圍的數值需另行處理。

```sql
SELECT (order_date AT TIME ZONE 'Asia/Taipei')::date AS business_date,
       serial, count(*) AS duplicate_count
FROM public.orders
GROUP BY 1, 2
HAVING count(*) > 1;
```

在測試專案由管理者建立 Supabase Auth 測試帳號後，將其 UUID 加入 `public.merchant_users` 並確認 `is_active = true`。RPC 只允許 `authenticated` 呼叫，且會再次檢查有效會員；匿名使用者及停用帳號無法送單。內部配號及操作紀錄表不開放給客戶端。不要將 `service_role` key、登入憑證或 token 放入 App、版本控制或 log。

**目前 App 沒有登入 UI，也沒有建立店家 session 的流程**；首次安裝或 session 失效時，訂單會保留在本機並顯示需要登入或授權，不能僅靠 publishable key 上傳。需先另定並實作安全的帳號佈署、登入與復原方式，才能在實際裝置測試上傳。

上傳會使用固定操作 UUID，伺服器在同一 transaction 驗證菜單、配發正式號碼及寫入訂單／明細；重送相同資料回傳原號碼，若雲端訂單的正式號碼被外部程序改動則停止處理。逾時、斷線或授權失敗保留本機 outbox；價格、品名或供應狀態不一致時顯示需處理，不能靜默改價。目前沒有訂單修改／衝突解決 UI，需排除原因後手動重試。`order_write_operations` 保存冪等請求內容，正式環境需先訂定個資與保留政策，且不可在重試期限內隨意刪除紀錄。

顧客 QR 端尚未實作，也尚未接入相同配號機制。現有 SQL 測試 `tests/merchant_order_submission.sql` 使用本機模擬的 `auth.users` 與角色，僅適用隔離測試資料庫，不應直接對真實專案執行；本機相容性測試不能取代真實 Supabase 權限與多連線測試。

可使用 Node.js 與暫存目錄中的 PGlite 重跑本機 SQL 測試，不會連接 Supabase：

```bash
npm install --prefix /tmp/flutter_shop_pgtest --no-package-lock --no-save @electric-sql/pglite@0.5.16
PGLITE_PREFIX=/tmp/flutter_shop_pgtest node supabase/tests/run_local.cjs
```

## 開啟測試讀取並建立假訂單

在 Supabase Dashboard 的 SQL Editor 執行以下 SQL。政策只允許匿名用戶讀取 `mark` 為 `[DEMO]` 的資料；不要把真實訂單標成此值。

```sql
grant select on public.orders to anon;

drop policy if exists "Read demo orders only" on public.orders;
create policy "Read demo orders only"
  on public.orders
  for select
  to anon
  using (mark = '[DEMO]');

insert into public.orders (
  order_source,
  status,
  takeout,
  serial,
  total_price,
  get_pay,
  sauerkraut,
  ginger,
  chili,
  order_date,
  uber,
  mark
)
select
  'LEGACY',
  'PENDING',
  false,
  1,
  120,
  0,
  false,
  false,
  false,
  now(),
  false,
  '[DEMO]'
where not exists (
  select 1
  from public.orders
  where mark = '[DEMO]'
    and serial = 1
);
```

App 使用下列參數啟動，替換成測試專案資料：

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

訂單列表應顯示「內用・單號 1」及 `NT$ 120`。若新增或更新符合 `[DEMO]` 條件的訂單，列表應隨 Realtime 事件更新。

## 測試後清理

測試完成後，在 SQL Editor 執行以下 SQL，刪除假訂單並移除匿名讀取政策及權限：

```sql
delete from public.orders
where mark = '[DEMO]';

drop policy if exists "Read demo orders only" on public.orders;
revoke select on public.orders from anon;
```

清理後，匿名用戶不再能讀取訂單。正式環境應使用已驗證的店家身分與 RLS policy，不應保留此測試政策。