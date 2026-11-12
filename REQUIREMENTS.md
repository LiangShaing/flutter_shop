# 餐廳線上點餐與門市同步系統需求

## 1. 專案背景與目標

- **服務規模**：單一餐廳門市，每日約 50–100 位來客。
- **核心目標**：讓顧客掃描桌面 QR Code 後以手機瀏覽器點餐，並讓店家即時接收與管理訂單。
- **架構目標**：不自購本地主機，以雲端 Serverless 服務降低初期成本與維運負擔。
- **本專案範圍**：此 repository 以 Flutter 店家端 App 為主。顧客點餐 Web、Supabase 專案與資料庫政策屬於整體系統的相依部分，尚不代表已在本 repository 實作。

## 2. 系統架構

```text
[顧客手機瀏覽器]
  QR Code 點餐網頁
       │ 讀取菜單、送出訂單
       ▼
[Supabase 雲端服務]
  PostgreSQL / Auto REST API / Realtime / Storage
       ▲                         │
       │ 店員點餐、更新狀態       │ 訂單事件推播
       │                         ▼
       └────────────── [Flutter 店家端 App]
                         訂單管理、提示音、離線佇列
```

### 顧客點餐網頁

- **技術選項**：React、Vue、Next.js 或 Flutter Web。
- **託管選項**：Vercel 或 Cloudflare Pages。
- **職責**：讀取可供應的菜單、建立訂單。一般瀏覽不需維持長期 WebSocket 連線。
- 顧客端只可讀取公開菜單並建立訂單，不可讀取或修改其他顧客的訂單。

### 店家端 Flutter App

- **技術**：Flutter、`supabase_flutter`，本地持久化可評估 SQLite、Isar 或 Hive。
- 使用 Supabase Realtime 監聽新訂單與訂單狀態變化；新訂單抵達時更新畫面並播放提示音。
- 支援店員建立現場訂單、查看訂單明細，以及更新訂單狀態。
- 網路中斷時，店員建立的訂單先寫入本機佇列；連線恢復後自動補送並呈現同步結果。
- 離線補送必須具備重試與冪等處理，避免逾時重送造成重複訂單；本機待送資料需在 App 關閉後保留。
- App 需處理 Realtime 斷線、重新訂閱及連線恢復時重新載入資料的情況，避免只依賴即時事件而漏單。

### 雲端後端與資料庫

- **平台**：Supabase。
- **元件**：PostgreSQL、Auto-generated REST API、Realtime、Storage；店家登入使用 Supabase Auth。
- Storage 用於餐點圖片。資料庫以 RLS 與明確的資料庫政策限制各角色的讀寫權限。

## 3. 成本與容量估算

以下為初期規劃估算，不是服務承諾。供應商免費額度、計費條款與地區差異可能調整，正式採用前需重新核對官方方案與實際用量。

| 項目 | 規劃方案 | 規劃用量 | 初期月費估算 |
| :--- | :--- | :--- | :--- |
| 資料庫與 API | Supabase Free | 約 3,000 筆文字訂單，預估資料庫 6–15 MB/月 | $0 USD |
| Realtime | Supabase Free | 1–3 台店家裝置，約 10,000 則訊息/月 | $0 USD |
| 餐點圖片 | Supabase Storage Free | 約 100–300 MB，約 100 道餐點圖片 | $0 USD |
| 點餐網頁代管 | Cloudflare Pages 或 Vercel Free | 每日約 100 人次瀏覽 | $0 USD |
| 網域（選配） | 網域註冊商 | 1 組 `.com` 網域 | 依註冊商與續約價格計費 |

初期目標是將固定月費維持在免費額度內；網域、簡訊、金流、備份、超額用量與付費方案不包含在此估算中。免費服務不等於可用性或資料保留保證，營運前需確認備份與故障復原需求。

## 4. PostgreSQL 資料表草案

以下是初始資料模型，正式建置時需搭配索引、欄位限制、RLS 與政策一併審查。

```sql
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE menu_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    image_url TEXT,
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_number TEXT NOT NULL,
    order_source TEXT NOT NULL,
    status TEXT DEFAULT 'PENDING',
    total_amount DECIMAL(10, 2) NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id UUID REFERENCES menu_items(id),
    item_name TEXT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    options JSONB
);
```

欄位約定：`order_source` 初期使用 `WEB_QR` 或 `POS_APP`；`status` 初期使用 `PENDING`、`PREPARING`、`COMPLETED` 或 `CANCELLED`。訂單明細保留送單當下的品名與單價，避免菜單更新改變歷史訂單內容。

## 5. 權限與資料安全

- 所有公開或使用者可存取的資料表均需啟用 RLS，並以明確政策控制操作；不可將 Supabase `service_role` 金鑰放入 Web 或 Flutter 客戶端。
- 匿名顧客僅能讀取公開且上架的菜單，並只能建立訂單，不可讀取、修改或刪除訂單。
- 店家 App 透過 Supabase Auth 登入專屬帳號，依店家角色讀取訂單並更新允許的欄位。
- 直接允許匿名用戶寫入 `orders` 和 `order_items` 會有偽造價格、無效品項與濫用下單的風險。建議由資料庫函式或 Supabase Edge Function 驗證品項、價格、供應狀態與數量，再以資料庫交易建立主檔和明細；不可信任客戶端傳入的 `total_amount` 或 `unit_price`。
- 上線前需定義防濫用措施、輸入驗證、訂單保留期限與操作稽核需求。

## 6. 離線與同步需求

- 本機佇列至少保存訂單識別碼、建立時間、內容與同步狀態。
- 每筆離線訂單使用穩定的客戶端識別碼，伺服器端以唯一限制或等效機制避免重送重複建立。
- 網路恢復後按建立順序重試；失敗需保留資料並呈現可辨識狀態，不可靜默丟棄。
- 訂單狀態以雲端資料庫為準。App 重新連線或重新啟動時需重新同步，處理重複事件與狀態衝突。
- 需明確區分「尚未送達雲端」與「雲端已接受」的訂單，避免店員誤以為顧客端或廚房已收到未同步訂單。

## 7. 維運與待確認事項

- Supabase Free 專案的閒置暫停規則及恢復方式需依正式採用時的官方文件確認。若門市要求穩定營運，不應只依賴定期查詢維持免費專案活躍；應評估升級方案及備援、備份需求。
- 在選擇 Supabase、Vercel 或 Cloudflare Pages 方案前，核對最新免費額度、計費方式、服務條款、區域與超額處理方式。
- 未來擴展至多門市時，需在菜單、訂單與店家帳號資料增加門市識別及相應 RLS 隔離；不可假設升級方案後完全不需修改資料模型或權限政策。
- 若未來有更嚴格的離線同步需求，再評估 PowerSync 等同步服務及其成本、資料模型限制與導入範圍。

## 8. Flutter 店家端初期交付範圍

1. Supabase 設定與店家登入。
2. 訂單列表、訂單明細與訂單狀態更新。
3. Realtime 新訂單更新與本地提示音。
4. 店員手動建立訂單。
5. 本機離線佇列、重試、冪等補送與同步狀態呈現。
6. 菜單讀取與可售狀態呈現。

顧客 Web、Supabase schema/migrations、RLS policies、Edge Functions、Storage 規則與正式部署需作為整體系統的獨立工作項目規劃；本文件描述目標架構，並不表示這些元件已完成。