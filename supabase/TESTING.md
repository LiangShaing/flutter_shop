# Supabase 即時訂單測試

本文件只供**獨立的測試 Supabase 專案**使用。不要在含有真實顧客訂單的正式專案開啟匿名訂單讀取。

## 菜單同步

執行初始 migration 後，另在 Supabase SQL Editor 執行 `migrations/20261113000000_menu_realtime.sql`，將菜單與分類加入 Realtime publication。App 會先顯示 SQLite 快取，再分頁讀取雲端可見菜單；訂閱、回到前景、手動重試及定期核對會重新抓取快照。離線首次啟動使用 bundled 菜單，並標示為本機預設菜單。

目前匿名 RLS 只允許讀取可供應且分類啟用的菜單。雲端快取因此只代表目前帳號可見的品項，停售或被分類隱藏的品項會從快取移除，不能據此判斷雲端是否刪除；若需店家查看所有停售品項，須另設店家授權與政策。現有 `display_name` 暫存舊菜單的 `subName`，不是完整品名。此功能尚不會上傳菜單、訂單或 outbox。

若 Realtime 顯示 `channelError` 且分類為 `unclassified`，可在 debug 啟動指令中額外加入 `--dart-define=MENU_SYNC_VERBOSE_REALTIME_ERRORS=true`。新增或移除參數後需完整停止並重新啟動 App。詳細錯誤預設關閉，且只在 debug 模式輸出；雖然會遮罩常見憑證與 URL，仍可能包含其他敏感資料，分享 log 前請自行檢查及刪除敏感內容。排查完成後移除該參數。

## 前置條件

1. 已在測試 Supabase 專案執行 `migrations/20261112000000_initial_schema.sql`。
2. `public.orders` 已加入 `supabase_realtime` publication。初始 migration 已執行此設定。
3. Flutter App 使用該測試專案的 URL 與 publishable key 啟動。

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