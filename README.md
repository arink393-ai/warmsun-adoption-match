# 暖陽動物之家｜認養配對所

以「嚴謹認養手續」為喻的交友配對網站原型。男生登記為 🐶 狗狗、女生登記為 🐱 貓咪；
想認識誰就提出認養申請，通過三階段審查（書面審查 → 價值觀評估 → 日常觀察）才會互相
解鎖聯絡方式。

- `index.html` — 公開配對站：登入／註冊、佈告欄（含檢舉）、**個人中心**（我的資料、我的收件匣、
  我的申請、我的回覆範本、診療點數）、**管理後台**（只有 `is_admin` 帳號看得到：全站統計、
  檢舉處理、範本主檔管理、照片與驗證照審核台）、隱私權政策、流程說明。
  「我的資料」的自介欄位除了自由文字，還有一組結構化的選填欄位（年收入區間、婚姻狀態、
  是否有孩子、兵役狀況、居住狀況、負債狀況、關係期待、生育規劃、MBTI、興趣／個性／
  生活習慣多選），以及「希望對方的條件」（婚姻要求、年齡範圍、孩子要求、生活習慣要求）；
  佈告欄卡片上會摺疊成一個「詳細資料」區塊顯示給別人看。
- `dashboard.html` — 個人後台，依登記身分顯示不同內容：
  - **待認養**（被追求的一方）：收件審查（通過／婉拒／解鎖）、自訂第一階段題目、
    第二階段價值觀題庫（十類 48 題可勾選）、罐頭回覆庫、AI 建議評分（免費、不扣點）。
  - **飼主**（提出申請的一方）：送出的申請進度、私人筆記、回答小抄。
- `shelter-review-assistant.html` — **私人工具**，只綁定站長本人的會員帳號（`arink393@gmail.com`），
  跟平台的多人資料模型完全分開（不使用 `profiles`／`applications`），資料存在只有本人能存取的
  `owner_kv` 資料表。用來管理小橘的 Dcard 企劃：病例設定、罐頭回覆、FAQ、貼文申請書、
  表單匯入評分、AI 判斷該用哪封罐頭。登入後會在「個人中心 → 我的資料」看到這個工具的連結
  （只有站長本人的帳號登入時才會顯示）。
- `supabase-schema.sql` — 資料庫結構與 RLS（Row Level Security）政策，包含
  `profiles`／`applications`（配對平台）、`reports`（檢舉）、`template_master`（範本主檔）、
  `owner_kv`（私人工具專用，只有本人存取得到）。
- `js/config.js` — 你的 Supabase 連線設定（網址＋anon 金鑰＋選用的 AI 代理網址）。
- `js/supabase-client.js` — 共用的登入／資料存取邏輯（配對平台與私人工具共用同一份）。
- `supabase/functions/claude/index.ts` — （選用）Claude API 代理，讓照片初檢、主治獸醫評估、
  「AI 建議評分」、私人工具的審查草稿產生都能安全呼叫 AI，金鑰只存在伺服器端，
  瀏覽器端一律不會直接呼叫 `api.anthropic.com`。

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

### 5. 大頭照／身分驗證／管理員審核

登記需要上傳大頭照與一張「驗證照」（比指定手勢＋手持代碼紙條，用來確認是本人）。
大頭照存在 Supabase Storage 的公開 bucket，驗證照存在私密 bucket，
**審核通過或退回後系統會立即刪除驗證照**。`supabase-schema.sql` 已經包含建立這兩個
bucket 與對應權限的 SQL，跑過整份腳本就會自動建好，不用另外去 Storage 頁面手動設定。

要能使用「管理後台」（全站統計、檢舉處理、範本主檔管理、照片與驗證照審核台），你要先把
自己的帳號設成管理員（這一步無法從網頁上做，得自己去資料庫改，避免任何人能自封管理員）：
1. 先用你自己的帳號在網站上登入一次（讓 Supabase 的 `auth.users` 裡有這筆帳號）。
2. 到 Supabase **SQL Editor**，執行（記得換成你自己的 email）：
   ```sql
   update public.profiles set is_admin = true
   where id = (select id from auth.users where email = '你的帳號 email');
   ```
3. 重新整理網站，頂端分頁會出現「管理後台」，裡面會顯示全站統計、待處理檢舉、範本主檔編輯，
   以及原本的照片／驗證照審核台。

大頭照的系統初檢一樣透過 Claude 代理（見上一步），沒設定 `CLAUDE_PROXY_URL` 也不會擋住
註冊流程，只是會略過初檢、直接進人工審核。

### 6. 私人工具（`shelter-review-assistant.html`）

這個工具只給站長本人使用，跟平台其他會員的資料完全分開：
1. 打開 `index.html` 裡的 `const OWNER_EMAIL = 'arink393@gmail.com';`（在 `<script>` 區塊裡）
   跟 `shelter-review-assistant.html` 裡同名的常數，確認都是你自己的帳號 email，兩邊要一致。
2. 用這個帳號登入 `index.html` 後，到「個人中心 → 我的資料」最下面會看到
   「小橘的 Dcard 企劃工具（僅本人可見）」連結，點進去就是 `shelter-review-assistant.html`。
3. 直接用同一組帳密登入即可，資料會存進只有這個帳號能讀寫的 `owner_kv` 資料表
   （`supabase-schema.sql` 已經建好對應的表格與 RLS 政策）。用別的帳號登入會被擋在門口，
   不會看到任何內容。
4. 這個工具裡產生審查草稿一樣透過 Claude 代理（見上面第 4 步），沒設定 `CLAUDE_PROXY_URL`
   的話會顯示「尚未設定 AI 代理網址」，但存檔、罐頭回覆、名冊等其他功能不受影響。

### 7. 安全性補強：擋掉自己改自己權限／點數的漏洞

早期版本的 `profiles_update_own` 只檢查「改的是不是自己那一列」，沒檢查「改的是哪一欄」——
任何登入的人在瀏覽器 devtools 執行 `DB.saveMyProfile({is_admin:true, credits:999999})` 就會直接成功。
`supabase-schema.sql` 第 9 節已經補上防護（trigger 擋住 `is_admin`／`credits`／`credit_log`／
`bonus_given` 被非管理員直接改，也擋住自己把 `photo_status`／`verify_status` 設成 `approved`），
並把掛號費、診療費、退款、加點都改成專用的 Postgres 安全函式（`apply_to`、`spend_credits_for`、
`refund_application`、`admin_add_credits`），前端不再能直接改點數欄位。

**如果你的 Supabase 專案是舊版本、已經在跑了**，重新貼一次整份 `supabase-schema.sql` 執行即可
（跟之前每次補欄位一樣，是安全的重複執行，不會動到既有會員資料）。這次也把「診療室」的模擬
儲值按鈕拿掉了（自己給自己加點本身就是同一種漏洞的 UI 版），改成「線上儲值尚未開放，請洽站方
人工加值」，管理員可以到「管理後台 → 手動加點」幫指定會員加點——這是目前唯一合法的加點入口
（送出申請的掛號費、逾期退款、AI 診療費用扣點則都各自走專用安全函式，使用者自己不能繞過）。

真的要接金流（例如綠界 ECPay）時，`admin_add_credits` 的邏輯可以直接被金流回調的 Edge Function
重用（用 service_role 呼叫、訂單編號當 `ref` 防止重複回調），不用整套重寫。

### 8. 病歷卡與物種擴充

佈告欄上的每一份登記會排版成一張「動物病例表」：病例號碼、基本資料、行為觀察、健康與性格
星等（親人程度／活動量／慢熱程度／作息規律／獨立程度）、個性標籤、最喜歡的事、禁忌事項、
認養資格、健康告知、主治獸醫備註。

- **物種從 2 種擴充到 13 種**（貓咪、狗狗、兔子、刺蝟、倉鼠、天竺鼠、鸚鵡、蜜袋鼯、烏龜、
  變色龍、鬥魚、金魚、孔雀魚），而且**性別獨立成一個欄位**，不再是「貓＝女生、狗＝男生」。
  重跑 `supabase-schema.sql` 時會自動幫既有會員補上性別（依舊規則：貓→女生、狗→男生），
  現有資料不會消失。
- **分階段揭露**：生日要對方送出第一階段申請後才看得到；健康告知可以自己選擇「直接公開／
  對方送出第一階段申請後／進入第二階段後」才揭露。
- **進階診斷（3 點）**：收到申請後，可以請主治獸醫讀完對方第一階段的回答，針對講得含糊或
  可能有落差的地方，客製 4～6 題第二階段問題。擬好的題目會寫進這筆申請的
  `a2_questions`，通過第一階段時會直接沿用，不會被你的題庫蓋掉。

### 9. 申請內容改成真的付費解鎖、答題紀錄、送出前的同意關卡

之前「看第一階段詳細回答要付點數」只是說法，答案其實跟其他欄位一起存在 `applications`，
收件方本來就讀得到整列，前端遮住沒有用（打開 devtools 就能看到）。這次把回答搬到獨立的
`application_answers` 表，RLS 規定申請人永遠看得到自己的，收件方要付費解鎖（`unlock_a1`，
1 點）才看得到；發第二階段問卷也要付費（`send_stage2`，2 點）。**這是一次會動到既有資料的
搬遷**：重貼 `supabase-schema.sql` 時，既有申請的答案會自動搬進新表，並且全部標記成「已解鎖」，
不會回頭跟人收錢；同時原本 `applications.keeper_note`（飼主私人筆記）也搬進獨立的
`application_private_notes` 表並修掉了一個已知缺陷——之前收件方技術上讀得到對方的私人筆記，
現在 RLS 保證只有寫的人自己看得到。

- **我的答題紀錄**：送出申請或第二階段回答時，答案會自動存進你自己的 `profiles.answer_bank`。
  下次填寫申請表遇到相似題目，題目下方會展開「你以前答過的」，可以一鍵帶入或附加在後面，
  再依這次的題目調整。比對用題目文字的相似度，不透過 AI（不用額外扣點，速度也快）。
- **申請前的同意關卡**：點「提出認養申請」後，會先看到告知事項（誰看得到你的回答、要付費才
  能調閱、會存進答題紀錄等），勾選同意才會出現題目，同意時間記在這筆申請的 `consent_at`。
- 跟原本一樣，`applications` 也補上了同一種欄位層級的防護——收件方不能自己把 `stage`／
  `a1_unlocked`／`stage2_paid` 改成已解鎖來白嫖，只能透過會扣點、會驗證的安全函式操作。

### 10. 第三階段解鎖改成申請人付費、收件方免費同意

通過三階段審查後，原本雙方都要各自免費按「同意解鎖」才會互相看到日常觀察資訊。現在改成
**申請人要付 3 點**（`unlock_stage3`）才算完成自己這邊的同意，**收件方那邊維持免費**
（`consent_unlock_to`）——兩邊都同意了才會互相看到，維持原本互相同意的精神，只是申請人這邊
多一道付費關卡。申請人一登入，只要有申請進入第三階段但還沒付費解鎖，頂部會出現提醒橫幅，
「個人中心」的「我的申請」分頁也會顯示 🔔 提醒數字（目前沒有 email／推播通知，僅登入後在頁面
提示）。

寫這段時發現 `unlock_from`／`unlock_to` 這兩欄之前也沒有欄位層級防護——因為
`applications` 的更新政策是整列層級，申請人或收件方其實可以直接把「對方」那一欄也設成
`true`，等於幫對方蓋章同意，不需要對方真的按下同意。這次一併把這兩欄鎖進第 9 節那個
guard trigger，只能透過上面兩支安全函式改。

## 已知限制（原型階段）

- 沒有忘記密碼／Email 驗證的介面，Supabase 預設行為（例如要求驗證信）會直接生效，
  但畫面上沒有額外提示。
- 大頭照存在公開 bucket，路徑雖然帶有帳號的隨機 UUID 不容易猜到，但只要知道網址任何人
  （包含未登入者）都能看到，包括審核中或被退回的照片。真的需要更嚴格保護的話，之後可以
  改成私密 bucket＋簽名網址。
- 「刪除我的所有資料」只會刪除 `profiles` 那筆資料與 Storage 檔案，不會刪除 Supabase Auth
  帳號本身（登入帳密仍然存在），如果要徹底刪帳號需要另外呼叫 Supabase 的管理端 API。
- 檢舉目前只會列進管理後台讓你人工判斷、決定要不要移除對方的登記，沒有自動封鎖或停權機制。
