# 暖陽動物之家｜認養配對所

以「嚴謹認養手續」為喻的交友配對網站原型。男生登記為 🐶 狗狗、女生登記為 🐱 貓咪；
想認識誰就提出認養申請，通過三階段審查（書面審查 → 價值觀評估 → 日常觀察）才會互相
解鎖聯絡方式。

- `index.html` — 公開配對站：登入／註冊、佈告欄、我的登記、送出與收到的申請、
  診療室（點數／模擬儲值／主治獸醫 AI 評估）、流程說明。
- `dashboard.html` — 個人後台，依登記身分顯示不同內容：
  - **待認養**（被追求的一方）：收件審查（通過／婉拒／解鎖）、自訂第一階段題目、
    第二階段價值觀題庫（十類 48 題可勾選）、罐頭回覆庫、AI 建議評分（免費、不扣點）。
  - **飼主**（提出申請的一方）：送出的申請進度、私人筆記、回答小抄。
- `supabase-schema.sql` — 資料庫結構與 RLS（Row Level Security）政策。
- `js/config.js` — 你的 Supabase 連線設定（網址＋anon 金鑰＋選用的 AI 代理網址）。
- `js/supabase-client.js` — 共用的登入／資料存取邏輯。
- `supabase/functions/claude/index.ts` — （選用）Claude API 代理，讓「待認養」後台的
  「AI 建議評分」按鈕能安全呼叫 AI，金鑰只存在伺服器端。

## 上線前要做的事

### 1. 建立 Supabase 專案
1. 到 https://supabase.com 免費建立一個新專案。
2. 左側 **SQL Editor** → New query，貼上整份 `supabase-schema.sql` 並執行。
   這會建立 `profiles`、`applications` 兩張表，並開啟 RLS——**沒有登入的人完全看不到任何資料**，
   已登入的人也只能看到／修改自己的登記資料，以及自己牽涉在內的申請。
3. 左側 **Project Settings → API**，把「Project URL」與「anon public」金鑰
   貼進 `js/config.js` 對應的兩個欄位。

### 2. 開啟 Google 登入（你會自己來加的部分）
前端已經接好一顆「使用 Google 登入」按鈕（`supabase.auth.signInWithOAuth({provider:'google'})`），
你只需要：
1. 到 Google Cloud Console 建立 OAuth 2.0 用戶端（網頁應用程式）。
2. Supabase 專案 → **Authentication → Providers → Google**，貼上 Client ID / Secret 並啟用。
3. **Authentication → URL Configuration**，把正式網址（例如
   `https://<你的帳號>.github.io/warmsun-adoption-match/`）加進
   Site URL 與 Redirect URLs。
4. 完成後不用改任何程式碼，按鈕會自動生效。Email／密碼登入在此之前就能正常使用。

### 3. 開啟 GitHub Pages
Repo 設定 → **Settings → Pages** → Source 選「Deploy from a branch」→ 選 `main` 分支、
`/ (root)` 目錄 → Save。幾分鐘後就能用 `https://<你的帳號>.github.io/warmsun-adoption-match/` 開啟。

### 4.（選用）開啟 AI 輔助評估
配對站的「診療室」（消耗診療點數的「主治獸醫評估」）與「待認養」後台的「AI 建議評分」
（免費不扣點）都靠同一個 AI 代理，只需要設定一次：
1. 安裝 [Supabase CLI](https://supabase.com/docs/guides/cli)，登入並連結你的專案：
   `supabase login` → `supabase link --project-ref <你的專案代號>`
2. 部署函式：`supabase functions deploy claude`
3. 到 https://console.anthropic.com 申請一組 API 金鑰，設定成密鑰（不會出現在前端）：
   `supabase secrets set ANTHROPIC_API_KEY=sk-ant-xxxxx`
4. 把函式網址貼進 `js/config.js` 的 `CLAUDE_PROXY_URL`：
   `https://<你的專案代號>.supabase.co/functions/v1/claude`
5. 留空這個設定，兩個 AI 功能的按鈕都會自動顯示為停用狀態，不影響其他功能。

新帳號預設贈送 5 點診療點數（`profiles.credits`）。送出一份認養申請要扣 1 點「掛號費」，
請主治獸醫評估一位申請人要扣 1 點「診療費」；若對方超過 14 天沒處理你的申請，可以在
「我送出的申請」自行退回掛號費。「診療室」裡的儲值方案目前是模擬付款，不會真的扣款——
要串接真的金流（例如綠界、TapPay）需要另外接金流商的後端，目前還沒做。

## 已知限制（原型階段）

- `applications.keeper_note`（飼主的私人筆記）目前只在前端畫面上不顯示給對方看，
  但資料庫的 Row Level Security 是以「整列」為單位，技術上對方仍可能用瀏覽器工具查到這個欄位的值。
  如果筆記內容很敏感，之後應該搬到獨立資料表、只讓筆記本人有讀取權限。
- 沒有忘記密碼／Email 驗證的介面，Supabase 預設行為（例如要求驗證信）會直接生效，
  但畫面上沒有額外提示。
- 沒有檢舉、封鎖或管理員審核機制。
