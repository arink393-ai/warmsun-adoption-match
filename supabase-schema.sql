-- ============================================================
--  暖陽動物之家｜認養配對所 — Supabase 資料庫結構 + RLS
--
--  【怎麼執行】
--  1. 到 https://supabase.com 建立一個新專案（免費方案就夠用）
--  2. 左側選單 → SQL Editor → New query
--  3. 把整份貼上 → 按 Run
--  4. 左側選單 → Project Settings → API，把「Project URL」與
--     「anon public」金鑰填進 js/config.js
--
--  【要另外做的事：開啟 Google 登入】
--  左側選單 → Authentication → Providers → Google → 開啟，
--  貼上你自己申請的 Google OAuth Client ID / Secret，
--  並在 Authentication → URL Configuration 把你的網站網址
--  （例如 https://<你的帳號>.github.io/warmsun-adoption-match/）
--  加進 Redirect URLs。前端程式碼已經接好一顆「使用 Google 登入」
--  的按鈕，開通後不用再改任何程式。
-- ============================================================

-- 0) 需要用到的擴充功能（產生 UUID）
create extension if not exists "pgcrypto";

-- ============================================================
-- 1) match_profiles：配對系統專用會員資料
-- 注意：不要與同一 Supabase 專案內其他產品的 public.profiles 共用。
-- ============================================================
create table if not exists public.match_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default '',
  kind        text not null default '' check (kind in ('', 'pet', 'keeper')),
  species     text not null default '',   -- 13 種動物，見 index.html 的 SPECIES 清單
  gender      text not null default 'f',  -- f 女生／m 男生／x 不透露（與物種脫鉤）
  age         text default '',
  area        text default '',
  job         text default '',
  education   text default '',
  height_cm   smallint,
  weight_kg   numeric(5,1),
  show_weight boolean not null default false,
  bio         text default '',
  wants       text default '',
  locked      text default '',       -- 第三階段才會顯示給對方的日常觀察資訊
  q1          jsonb,                 -- 自訂第一階段書面審查題（僅 kind='pet' 使用；空=用預設題）
  q2_bank     jsonb,                 -- 自訂第二階段價值觀題庫勾選（僅 kind='pet' 使用）
  canned      jsonb,                 -- 自訂罐頭回覆庫（僅 kind='pet' 使用）
  credits     int not null default 5,        -- 診療點數（新帳號贈送 5 點）
  credit_log  jsonb not null default '[]'::jsonb, -- 點數異動紀錄
  photo_status text not null default 'none' check (photo_status in ('none','checking','pending','approved','rejected')),
  photo_reason text default '',
  avatar_kind text not null default 'real' check (avatar_kind in ('real','ai')),
  ai_likeness_attested boolean not null default false,
  photo_review_due_at timestamptz,
  verify_status text not null default 'none' check (verify_status in ('none','pending','approved','rejected')),
  verify_reason text default '',
  verify_task jsonb,                   -- {gesture, code}：驗證照要比的手勢與紙條代碼
  verify_deleted_at timestamptz,
  consent     boolean not null default false,
  consent_at  timestamptz,
  bonus_given boolean not null default false,  -- 完成登記＋照片審核通過的獎勵點數是否已發過
  is_admin    boolean not null default false,  -- 審核台權限；只能自己去 Table Editor 手動打勾給信任帳號
  account_status text not null default 'active' check (account_status in ('active','suspended','deleted')),
  posting_locked boolean not null default false,
  moderation_reason text default '',
  moderated_at timestamptz,
  moderated_by uuid references auth.users(id) on delete set null,
  -- 詳細資料（選填，會公開）
  income      text default '',
  marital     text default '',
  has_kids    text default '',
  military    text default '',
  living      text default '',
  debt        text default '',
  relationship_goal text default '',
  kids_plan   text default '',
  mbti        text default '',
  work_hours  text default '',
  interests   jsonb not null default '[]'::jsonb,
  personality jsonb not null default '[]'::jsonb,
  habits      jsonb not null default '[]'::jsonb,
  habits_other text default '',
  -- 希望對方的條件（選填，會公開）
  req_marital text default '',
  req_age_min text default '',
  req_age_max text default '',
  req_kids    text default '',
  req_habits  jsonb not null default '[]'::jsonb,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- 若資料表已存在（舊版本先執行過這份腳本，或當初建表沒有完整跑完），補齊所有欄位。
-- 每一行都獨立、彼此不依賴，就算表本來殘缺不全，這裡也會全部補齊。
alter table public.match_profiles add column if not exists name text not null default '';
alter table public.match_profiles add column if not exists kind text not null default '';
alter table public.match_profiles add column if not exists species text not null default '';
alter table public.match_profiles add column if not exists age text default '';
alter table public.match_profiles add column if not exists area text default '';
alter table public.match_profiles add column if not exists job text default '';
alter table public.match_profiles add column if not exists education text default '';
alter table public.match_profiles add column if not exists height_cm smallint;
alter table public.match_profiles add column if not exists weight_kg numeric(5,1);
alter table public.match_profiles add column if not exists show_weight boolean not null default false;
alter table public.match_profiles add column if not exists bio text default '';
alter table public.match_profiles add column if not exists wants text default '';
alter table public.match_profiles add column if not exists locked text default '';
alter table public.match_profiles add column if not exists q1 jsonb;
alter table public.match_profiles add column if not exists q2_bank jsonb;
alter table public.match_profiles add column if not exists canned jsonb;
alter table public.match_profiles add column if not exists created_at timestamptz default now();
alter table public.match_profiles add column if not exists updated_at timestamptz default now();
alter table public.match_profiles add column if not exists credits int not null default 5;
alter table public.match_profiles add column if not exists credit_log jsonb not null default '[]'::jsonb;
alter table public.match_profiles alter column credits set default 5;
alter table public.match_profiles add column if not exists photo_status text not null default 'none';
alter table public.match_profiles add column if not exists photo_reason text default '';
alter table public.match_profiles add column if not exists avatar_kind text not null default 'real';
alter table public.match_profiles add column if not exists ai_likeness_attested boolean not null default false;
alter table public.match_profiles add column if not exists photo_review_due_at timestamptz;
alter table public.match_profiles add column if not exists verify_status text not null default 'none';
alter table public.match_profiles add column if not exists verify_reason text default '';
alter table public.match_profiles add column if not exists verify_task jsonb;
alter table public.match_profiles add column if not exists verify_deleted_at timestamptz;
alter table public.match_profiles add column if not exists consent boolean not null default false;
alter table public.match_profiles add column if not exists consent_at timestamptz;
alter table public.match_profiles add column if not exists bonus_given boolean not null default false;
alter table public.match_profiles add column if not exists is_admin boolean not null default false;
alter table public.match_profiles add column if not exists account_status text not null default 'active';
alter table public.match_profiles add column if not exists posting_locked boolean not null default false;
alter table public.match_profiles add column if not exists moderation_reason text default '';
alter table public.match_profiles add column if not exists moderated_at timestamptz;
alter table public.match_profiles add column if not exists moderated_by uuid references auth.users(id) on delete set null;

alter table public.match_profiles drop constraint if exists match_profiles_height_cm_check;
alter table public.match_profiles add constraint match_profiles_height_cm_check
  check (height_cm is null or height_cm between 100 and 230);
alter table public.match_profiles drop constraint if exists match_profiles_weight_kg_check;
alter table public.match_profiles add constraint match_profiles_weight_kg_check
  check (weight_kg is null or weight_kg between 25 and 350);
alter table public.match_profiles drop constraint if exists match_profiles_avatar_kind_check;
alter table public.match_profiles add constraint match_profiles_avatar_kind_check
  check (avatar_kind in ('real','ai'));
alter table public.match_profiles drop constraint if exists match_profiles_account_status_check;
alter table public.match_profiles add constraint match_profiles_account_status_check
  check (account_status in ('active','suspended','deleted'));

-- 病歷卡欄位（物種擴充、性別獨立、星等評分、禁忌、健康告知、獸醫備註）
alter table public.match_profiles add column if not exists gender text not null default 'f';
alter table public.match_profiles add column if not exists birth text default '';
alter table public.match_profiles add column if not exists traits text default '';
alter table public.match_profiles add column if not exists likes text default '';
alter table public.match_profiles add column if not exists taboo text default '';
alter table public.match_profiles add column if not exists health text default '';
alter table public.match_profiles add column if not exists health_tags jsonb not null default '[]'::jsonb;
alter table public.match_profiles add column if not exists health_when text not null default 'stage2';
-- 負債狀況跟健康告知一樣，揭露時機完全由本人決定（public／stage1／stage2／never）
alter table public.match_profiles add column if not exists debt_when text not null default 'stage2';
alter table public.match_profiles drop constraint if exists match_profiles_debt_when_check;
alter table public.match_profiles add constraint match_profiles_debt_when_check
  check (debt_when in ('public','stage1','stage2','never'));
alter table public.match_profiles drop constraint if exists match_profiles_health_when_check;
alter table public.match_profiles add constraint match_profiles_health_when_check
  check (health_when in ('public','stage1','stage2','never'));
alter table public.match_profiles add column if not exists vet_note text default '';
alter table public.match_profiles add column if not exists stars jsonb not null default '{}'::jsonb;
-- 我的答題紀錄：申請人送出過的答案，下次遇到相似題目可以一鍵帶入再修改
alter table public.match_profiles add column if not exists answer_bank jsonb not null default '[]'::jsonb;

-- 加碼照片：第一階段（口罩照／側拍照）、第二階段（生活照），登記人各上傳一張，
-- 讓通過該階段審查的申請人可以看到——只是「有沒有上傳」的旗標，實際檔案存在
-- storage 的 stage-photos bucket（私有），能不能讀由 storage policy 依申請進度判斷。
alter table public.match_profiles add column if not exists stage1_photo boolean not null default false;
alter table public.match_profiles add column if not exists stage2_photo boolean not null default false;

-- 一鍵通關：登記人自己選擇要不要開放，開放後申請人可以付點數直接跳到最終解鎖，
-- 免除三個階段的問答與審核。bonus_credits 記錄「哪一筆獎勵點數、什麼時候到期」，
-- 用來在 14 天內沒花完時收回，一併鎖進下面的 guard trigger，不能自己改。
alter table public.match_profiles add column if not exists allow_skip boolean not null default false;
alter table public.match_profiles add column if not exists bonus_credits jsonb not null default '[]'::jsonb;
-- restricted_credits：舊版「快速邀請」曾經發過不得轉讓、只能用在主治獸醫評估／進階診斷的
-- 限定用途獎勵點數，這欄記錄「目前餘額裡有多少是這種限定用途的點數」。快速邀請本身已經
-- 改版成不發獎勵的「優先邀請」（見 send_priority_invite），不會再有新的限定點數發出，
-- 但既有帳號可能還留著舊的沒花完，這裡繼續保留檢查邏輯讓它自然過期收回，不用特別清資料。
alter table public.match_profiles add column if not exists restricted_credits int not null default 0;
alter table public.match_profiles drop constraint if exists match_profiles_restricted_credits_check;
alter table public.match_profiles add constraint match_profiles_restricted_credits_check
  check (restricted_credits >= 0);

-- 物種從「只有貓／狗」放寬成 13 種，性別改用獨立的 gender 欄位表示。
-- 先移除舊的 check 限制，再依現有資料把 gender 補上（貓→女生、狗→男生，符合舊版的隱含規則）。
alter table public.match_profiles drop constraint if exists profiles_species_check;
update public.match_profiles set gender = case when species = 'dog' then 'm' else 'f' end
  where gender is null or gender = '';

-- 詳細資料（選填，會公開）——自介的結構化欄位
alter table public.match_profiles add column if not exists income text default '';
alter table public.match_profiles add column if not exists marital text default '';
alter table public.match_profiles add column if not exists has_kids text default '';
alter table public.match_profiles add column if not exists military text default '';
alter table public.match_profiles add column if not exists living text default '';
alter table public.match_profiles add column if not exists debt text default '';
alter table public.match_profiles add column if not exists relationship_goal text default '';
alter table public.match_profiles add column if not exists kids_plan text default '';
alter table public.match_profiles add column if not exists mbti text default '';
alter table public.match_profiles add column if not exists work_hours text default '';
alter table public.match_profiles add column if not exists interests jsonb not null default '[]'::jsonb;
alter table public.match_profiles add column if not exists personality jsonb not null default '[]'::jsonb;
alter table public.match_profiles add column if not exists habits jsonb not null default '[]'::jsonb;
alter table public.match_profiles add column if not exists habits_other text default '';
-- 希望對方的條件（選填，會公開）
alter table public.match_profiles add column if not exists req_marital text default '';
alter table public.match_profiles add column if not exists req_age_min text default '';
alter table public.match_profiles add column if not exists req_age_max text default '';
alter table public.match_profiles add column if not exists req_kids text default '';
alter table public.match_profiles add column if not exists req_habits jsonb not null default '[]'::jsonb;

-- 一週工作時數：規則引擎（第 13 節「主治醫師初診」）讀的是這個數值欄，
-- 原本的 work_hours 自由文字欄留著當顯示用。這兩個欄位必須在
-- get_visible_match_profiles() 之前就存在，因為 SQL 函式在建立當下就會驗證本體。
alter table public.match_profiles add column if not exists weekly_work_hours smallint;
alter table public.match_profiles drop constraint if exists match_profiles_weekly_work_hours_check;
alter table public.match_profiles add constraint match_profiles_weekly_work_hours_check
  check (weekly_work_hours is null or (weekly_work_hours >= 0 and weekly_work_hours <= 200));

-- Dealbreaker 嚴重度：每個題組一個 none / discussable / non_negotiable。
-- 預設 {} 代表「沒有任何不可妥協條件」，不會憑空產生紅燈。
alter table public.match_profiles add column if not exists dealbreakers jsonb not null default '{}'::jsonb;

-- ── 第 17 節的四個新題組（欄位提前到這裡宣告，理由同上）──────────
-- 17.1 欄位 ----------------------------------------------------
-- ① 生活節奏（第 1 層：跟生活習慣同一層）
alter table public.match_profiles add column if not exists chronotype          text default '';
alter table public.match_profiles add column if not exists contact_frequency   text default '';
alter table public.match_profiles add column if not exists daily_together_need text default '';
alter table public.match_profiles add column if not exists alone_time_need     text default '';
alter table public.match_profiles add column if not exists conflict_style      text default '';

-- ② 家庭與居住（第 2 層：跟居住狀況同一層）
alter table public.match_profiles add column if not exists relocation             text default '';
alter table public.match_profiles add column if not exists long_distance_ok       text default '';
alter table public.match_profiles add column if not exists cohabit_with_parents   text default '';
alter table public.match_profiles add column if not exists family_visit_freq      text default '';
alter table public.match_profiles add column if not exists parents_in_decisions   text default '';

-- ③ 關係結構（marriage_intent 第 1 層、relationship_structure 第 2 層）
alter table public.match_profiles add column if not exists marriage_intent        text default '';
alter table public.match_profiles add column if not exists relationship_structure text default '';

-- ④ 財務（第 2 層）與寵物（第 0 層：這是認養比喻的站，寵物本來就該公開）
alter table public.match_profiles add column if not exists finance_style   text default '';
alter table public.match_profiles add column if not exists has_pets        text default '';
alter table public.match_profiles add column if not exists pet_acceptance  text default '';

-- 「希望對方」的條件（跟 req_* 一樣是公開的，那是你自己的徵求條件）
alter table public.match_profiles add column if not exists req_living             text default '';
alter table public.match_profiles add column if not exists req_family_involvement text default '';
alter table public.match_profiles add column if not exists req_partner_debt       text default '';

-- ── 第 20 節：第二階段結構化問診的五個新欄位（都是第 2 層）──────
alter table public.match_profiles add column if not exists partner_alone_time_acceptance text default '';
alter table public.match_profiles add column if not exists housework_model               text default '';
alter table public.match_profiles add column if not exists cleanliness_conflict_style    text default '';
alter table public.match_profiles add column if not exists conflict_pause_preference     text default '';
alter table public.match_profiles add column if not exists conflict_return_commitment    text default '';

-- 第 23 節：八個生活場景剩下的三個題組。欄位與選項的唯一來源是
-- data/relationship-topics.json，`node tools/gen-topics.mjs --check` 會盯著它們一致。
alter table public.match_profiles add column if not exists housework_fairness            text default '';
alter table public.match_profiles add column if not exists home_social_frequency         text default '';
alter table public.match_profiles add column if not exists home_guest_boundary           text default '';
alter table public.match_profiles add column if not exists religion_importance           text default '';
alter table public.match_profiles add column if not exists religion_partner_expectation  text default '';
alter table public.match_profiles add column if not exists religion_child_plan           text default '';
alter table public.match_profiles add column if not exists ex_contact_acceptance         text default '';
alter table public.match_profiles add column if not exists opposite_friend_boundary      text default '';
-- 複選題：存陣列。規則比的是兩份清單差多少，不是勾得多或少。
alter table public.match_profiles add column if not exists relationship_boundary_actions jsonb not null default '[]'::jsonb;

-- 一次性搬移舊版暖陽欄位。只複製兩張表共有的欄位，避免碰到同專案其他產品新增的欄位。
do $$
declare v_cols text;
begin
  if to_regclass('public.profiles') is not null then
    select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position)
      into v_cols
      from information_schema.columns c
      join information_schema.columns old_c
        on old_c.table_schema = 'public' and old_c.table_name = 'profiles'
       and old_c.column_name = c.column_name
     where c.table_schema = 'public' and c.table_name = 'match_profiles'
       and c.is_generated = 'NEVER';
    if coalesce(v_cols, '') <> '' then
      execute format('insert into public.match_profiles (%s) select %s from public.profiles on conflict (id) do nothing', v_cols, v_cols);
    end if;
  end if;
end $$;

alter table public.match_profiles enable row level security;

-- 用 security definer 函式檢查是否為管理員，避免 profiles 的 RLS policy 直接查詢自己造成遞迴
create or replace function public.match_is_admin(uid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.match_profiles where id = uid), false);
$$;

drop policy if exists "profiles_select_authenticated" on public.match_profiles;
drop policy if exists "profiles_select_visible"       on public.match_profiles;
drop policy if exists "profiles_insert_own"           on public.match_profiles;
drop policy if exists "profiles_update_own"           on public.match_profiles;
drop policy if exists "profiles_update_admin"         on public.match_profiles;
drop policy if exists "profiles_delete_own"           on public.match_profiles;

-- 原始會員列只開放本人與管理員；公開卡片一律走遮罩欄位的 RPC。
create policy "profiles_select_visible"
  on public.match_profiles for select
  to authenticated
  using (auth.uid() = id or public.match_is_admin(auth.uid()));

-- 只能新增自己的那一筆
create policy "profiles_insert_own"
  on public.match_profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- 修改自己的那一筆
create policy "profiles_update_own"
  on public.match_profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- 管理員可以修改任何一筆（審核通過/退回、發放獎勵點數）
create policy "profiles_update_admin"
  on public.match_profiles for update
  to authenticated
  using (public.match_is_admin(auth.uid()))
  with check (public.match_is_admin(auth.uid()));

create policy "profiles_delete_own"
  on public.match_profiles for delete
  to authenticated
  using (auth.uid() = id);

-- 管理員可以移除任何一筆登記（例如檢舉查證屬實後下架）
drop policy if exists "profiles_delete_admin" on public.match_profiles;
create policy "profiles_delete_admin"
  on public.match_profiles for delete
  to authenticated
  using (public.match_is_admin(auth.uid()));

-- ============================================================
-- 2) applications：認養申請（一位申請人對一位登記對象只有一筆）
-- ============================================================
create table if not exists public.applications (
  id           uuid primary key default gen_random_uuid(),
  from_user    uuid not null references auth.users(id) on delete cascade,
  to_user      uuid not null references auth.users(id) on delete cascade,
  stage        int  not null default 1,      -- 1 書面審查 / 2 價值觀評估 / 3 日常觀察
  status       text not null default 'open' check (status in ('open','rejected')),
  -- 注意：第一／二階段的回答不放在這裡，而是放在 application_answers（見第 10 節）。
  a2_questions jsonb,                        -- 這次實際出的第二階段題目（由 pet 從題庫挑選）
  a1_unlocked  boolean not null default true, -- 申請人已經付掛號費了，第一階段完整回答一律免費給收件方看，
                                              -- 這欄留著只是沿用舊架構、不必大改 RLS；不再收「調閱費」
  stage2_paid  boolean not null default false, -- 收件方是否已付費發出第二階段問卷
  consent_at   timestamptz,                  -- 申請人送出這份申請時同意隱私權政策的時間
  unlock_from  boolean not null default false,
  unlock_to    boolean not null default false,
  note         text,                         -- 被申請方寫給申請人看的話（例如婉拒理由）
  vet          text,                         -- 主治獸醫（AI）評估結果，快取起來避免重複收費
  vet_at       timestamptz,
  paid         int not null default 0,       -- 送出申請時付的掛號費點數
  refunded     boolean not null default false, -- 掛號費是否已退回申請人
  created_at   timestamptz default now(),
  updated_at   timestamptz default now(),
  unique (from_user, to_user),
  check (from_user <> to_user)
);

-- 若資料表已存在（或當初建表沒有完整跑完），補齊所有欄位
alter table public.applications add column if not exists from_user uuid;
alter table public.applications add column if not exists to_user uuid;
alter table public.applications add column if not exists stage int not null default 1;
alter table public.applications add column if not exists status text not null default 'open';
alter table public.applications add column if not exists a2_questions jsonb;
alter table public.applications add column if not exists a1_unlocked boolean not null default true;
alter table public.applications alter column a1_unlocked set default true;
-- 拿掉「調閱費」：申請人已經付了掛號費，第一階段完整回答一律免費開放給收件方看，
-- 既有申請也一併補開放，不會回頭跟人收錢也不用讓舊申請卡住。
update public.applications set a1_unlocked = true where not a1_unlocked;
alter table public.applications add column if not exists stage2_paid boolean not null default false;
alter table public.applications add column if not exists consent_at timestamptz;
alter table public.applications add column if not exists unlock_from boolean not null default false;
alter table public.applications add column if not exists unlock_to boolean not null default false;
alter table public.applications add column if not exists note text;
alter table public.applications add column if not exists created_at timestamptz default now();
alter table public.applications add column if not exists updated_at timestamptz default now();
alter table public.applications add column if not exists vet text;
alter table public.applications add column if not exists vet_at timestamptz;
alter table public.applications add column if not exists paid int not null default 0;
alter table public.applications add column if not exists refunded boolean not null default false;
-- （vet_scores 曾經在這裡建立，已於第 22 節整欄移除，不要再加回來）
alter table public.applications add column if not exists vet_stage int;
-- 一鍵通關／快速邀請（舊機制，已停用）留下的欄位：不再由任何函式寫入，純粹保留舊資料，
-- 避免砍欄位動到既有申請紀錄。新機制見下面的 priority_invite／priority_note。
alter table public.applications add column if not exists skipped boolean not null default false;
alter table public.applications add column if not exists fast_invite_from boolean not null default false;
alter table public.applications add column if not exists fast_invite_to boolean not null default false;
-- 優先邀請（取代快速邀請）：不會跳過任何審查階段，純粹在收件匣多一個「優先考慮」標記
-- 跟一封最多 300 字的邀請信，讓收件人自己決定要不要提早看。
alter table public.applications add column if not exists priority_invite boolean not null default false;
alter table public.applications add column if not exists priority_note text not null default '';

alter table public.applications enable row level security;

drop policy if exists "applications_select_participant" on public.applications;
drop policy if exists "applications_insert_as_from"      on public.applications;
drop policy if exists "applications_update_participant"  on public.applications;

-- 只有申請人本人或被申請的對象看得到這筆申請
create policy "applications_select_participant"
  on public.applications for select
  to authenticated
  using (auth.uid() = from_user or auth.uid() = to_user);

-- 建立申請只能走 apply_to() 完成扣點交易；一般角色不得直接 insert。
-- 更新只開放給收件方寫婉拒、AI 評估與題目；申請人的作答一律走安全函式。
create policy "applications_update_participant"
  on public.applications for update
  to authenticated
  using (auth.uid() = to_user)
  with check (auth.uid() = to_user);

-- 管理員移除違規登記時，一併清掉相關申請
drop policy if exists "applications_delete_admin" on public.applications;
create policy "applications_delete_admin"
  on public.applications for delete
  to authenticated
  using (public.match_is_admin(auth.uid()));

create index if not exists applications_to_user_updated_idx on public.applications(to_user, updated_at desc);
create index if not exists applications_from_user_updated_idx on public.applications(from_user, updated_at desc);

-- 年齡在佈告欄只給區間，通過第一階段後才顯示精確歲數。
-- age 欄位是自由文字（可能是「28」「28 歲」「二十八」），抓得到數字就分桶，抓不到就原樣回傳。
create or replace function public.age_bucket(p_age text)
returns text language sql immutable set search_path = '' as $$
  select case
    when nullif(substring(coalesce(p_age,'') from '[0-9]+'), '') is null then nullif(p_age, '')
    when (substring(p_age from '[0-9]+'))::int < 25 then '25 歲以下'
    when (substring(p_age from '[0-9]+'))::int < 30 then '25～29 歲'
    when (substring(p_age from '[0-9]+'))::int < 35 then '30～34 歲'
    when (substring(p_age from '[0-9]+'))::int < 40 then '35～39 歲'
    when (substring(p_age from '[0-9]+'))::int < 45 then '40～44 歲'
    when (substring(p_age from '[0-9]+'))::int < 50 then '45～49 歲'
    else '50 歲以上'
  end
$$;

-- ============================================================
-- 2a-2) 安全中心：使用者層級的封鎖（跟下面 match_blocks 的「關閉單一對話」不同，
--       這裡是「我完全不想再看到這個人，也不想被他看到」）
-- ============================================================
create table if not exists public.match_user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  reason     text not null default '',
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint match_user_blocks_not_self check (blocker_id <> blocked_id)
);
create index if not exists match_user_blocks_blocked_idx on public.match_user_blocks(blocked_id);
alter table public.match_user_blocks enable row level security;

-- 只看得到、也只能刪自己封鎖的名單；被封鎖的人查不到誰封鎖了他（避免報復）
drop policy if exists "user_blocks_select_own" on public.match_user_blocks;
create policy "user_blocks_select_own" on public.match_user_blocks for select to authenticated
  using (blocker_id = auth.uid());
drop policy if exists "user_blocks_delete_own" on public.match_user_blocks;
create policy "user_blocks_delete_own" on public.match_user_blocks for delete to authenticated
  using (blocker_id = auth.uid());
-- insert 一律走下面的 block_user()，才能同時關掉既有對話

create or replace function public.block_user(p_target uuid, p_reason text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_target is null or p_target = auth.uid() then raise exception '不能封鎖自己'; end if;
  insert into public.match_user_blocks(blocker_id, blocked_id, reason)
    values (auth.uid(), p_target, left(coalesce(p_reason,''), 500))
    on conflict (blocker_id, blocked_id) do update set reason = excluded.reason;
  -- 封鎖之後，雙方之間所有還開著的對話一併關閉，對方不會再收到新訊息
  insert into public.match_blocks(application_id, blocker_id, reason)
    select a.id, auth.uid(), '已封鎖對方'
      from public.applications a
     where (a.from_user = auth.uid() and a.to_user = p_target)
        or (a.to_user = auth.uid() and a.from_user = p_target)
    on conflict do nothing;
end $$;
revoke all on function public.block_user(uuid, text) from public, anon;
grant execute on function public.block_user(uuid, text) to authenticated;

create or replace function public.unblock_user(p_target uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.match_user_blocks where blocker_id = auth.uid() and blocked_id = p_target;
$$;
revoke all on function public.unblock_user(uuid) from public, anon;
grant execute on function public.unblock_user(uuid) to authenticated;

-- 是否有任一方向的封鎖（單向封鎖就雙向都看不到，避免「被封鎖的人還能一直看對方」）
create or replace function public.match_is_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.match_user_blocks
     where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  )
$$;
revoke all on function public.match_is_blocked(uuid, uuid) from public, anon;
grant execute on function public.match_is_blocked(uuid, uuid) to authenticated;

-- 對外一律走遮罩函式，四層漸進式揭露：
--   第 0 層（佈告欄，還沒有申請關係）：暱稱、物種性別、年齡「區間」、地區、職業、
--                                    興趣、個性、關係期待、個性標籤、喜歡的事、禁忌、星等
--   第 1 層（對方送出第一階段申請後）：精確年齡、身高、體重（本人另外決定公不公開）、
--                                    學歷、婚姻、有無孩子、兵役、生活習慣
--   第 2 層（進入第二階段後）：年收入區間、居住狀況、生育規劃、一週工作時數
--   第 3 層（雙方都同意解鎖後）：生日、日常觀察資訊（社群帳號等）
--   另外「健康告知」與「負債狀況」的揭露時機完全由本人自己選（public／stage1／stage2／never）
create or replace function public.get_visible_match_profiles(p_profile_id uuid default null)
returns setof jsonb
language sql security definer stable set search_path = '' as $$
  select
    (to_jsonb(p) - array[
      'credits','credit_log','is_admin','q1','q2_bank','canned','answer_bank',
      'bonus_credits','verify_task','verify_reason','verify_deleted_at',
      'moderation_reason','moderated_at','moderated_by','posting_locked','account_status',
      'restricted_credits',
      -- 以下全部改由下面的 jsonb_build_object 依階段決定要不要給
      'age','birth','health','health_tags','locked','weight_kg','show_weight',
      'height_cm','education','marital','has_kids','military','habits','habits_other',
      'income','living','kids_plan','work_hours','weekly_work_hours','debt','debt_when',
      -- 第 17 節的四個新題組。黑名單制，漏掉一個就是一次洩漏。
      'chronotype','contact_frequency','daily_together_need','alone_time_need','conflict_style',
      'relocation','long_distance_ok','cohabit_with_parents','family_visit_freq',
      'parents_in_decisions','marriage_intent','relationship_structure','finance_style',
      'partner_alone_time_acceptance','housework_model','cleanliness_conflict_style',
      'conflict_pause_preference','conflict_return_commitment',
      -- 第 23 節：居家社交／宗教界線／前任與異性界線。
      -- 宗教與感情史屬於敏感資訊，一律只到第 2 層，而且永遠不做為佈告欄的篩選條件。
      'housework_fairness','home_social_frequency','home_guest_boundary',
      'religion_importance','religion_partner_expectation','religion_child_plan',
      'ex_contact_acceptance','opposite_friend_boundary','relationship_boundary_actions',
      -- Dealbreaker 嚴重度整個不外流：只給「有幾項」。細項是很強的識別資訊，
      -- 而且初診本來就在伺服器端讀得到，前端沒有任何理由需要拿到值。
      'dealbreakers'
    ]::text[])
    || jsonb_build_object(
      -- 第 0 層：年齡只給區間
      'age', case when rel.stage >= 1 then p.age else public.age_bucket(p.age) end,
      'age_is_bucket', (rel.stage is null or rel.stage < 1),
      -- 第 1 層
      'height_cm',   case when rel.stage >= 1 then p.height_cm else null end,
      'weight_kg',   case when rel.stage >= 1 and p.show_weight then p.weight_kg else null end,
      'show_weight', case when rel.stage >= 1 then p.show_weight else false end,
      'education',   case when rel.stage >= 1 then p.education else null end,
      'marital',     case when rel.stage >= 1 then p.marital else null end,
      'has_kids',    case when rel.stage >= 1 then p.has_kids else null end,
      'military',    case when rel.stage >= 1 then p.military else null end,
      'habits',      case when rel.stage >= 1 then p.habits else '[]'::jsonb end,
      'habits_other',case when rel.stage >= 1 then p.habits_other else null end,
      -- ① 生活節奏：跟生活習慣同一層
      'chronotype',          case when rel.stage >= 1 then p.chronotype else null end,
      'contact_frequency',   case when rel.stage >= 1 then p.contact_frequency else null end,
      'daily_together_need', case when rel.stage >= 1 then p.daily_together_need else null end,
      'alone_time_need',     case when rel.stage >= 1 then p.alone_time_need else null end,
      'conflict_style',      case when rel.stage >= 1 then p.conflict_style else null end,
      -- ③ 結婚意願：跟婚姻狀態同一層
      'marriage_intent',     case when rel.stage >= 1 then p.marriage_intent else null end,
      -- 第 2 層
      'income',      case when rel.stage >= 2 then p.income else null end,
      'living',      case when rel.stage >= 2 then p.living else null end,
      'kids_plan',   case when rel.stage >= 2 then p.kids_plan else null end,
      'work_hours',  case when rel.stage >= 2 then p.work_hours else null end,
      -- 規則引擎用的數值欄跟顯示用的文字欄是同一件事，遮罩層級也必須一樣，
      -- 否則第 0 層就能從 weekly_work_hours 讀到第 2 層才該開放的工時。
      'weekly_work_hours', case when rel.stage >= 2 then p.weekly_work_hours else null end,
      -- ② 家庭與居住：跟居住狀況同一層
      'relocation',             case when rel.stage >= 2 then p.relocation else null end,
      'long_distance_ok',       case when rel.stage >= 2 then p.long_distance_ok else null end,
      'cohabit_with_parents',   case when rel.stage >= 2 then p.cohabit_with_parents else null end,
      'family_visit_freq',      case when rel.stage >= 2 then p.family_visit_freq else null end,
      'parents_in_decisions',   case when rel.stage >= 2 then p.parents_in_decisions else null end,
      -- ③ 關係結構與 ④ 財務模式：都是第 2 層
      'relationship_structure', case when rel.stage >= 2 then p.relationship_structure else null end,
      'finance_style',          case when rel.stage >= 2 then p.finance_style else null end,
      -- 第二階段結構化問診的五題：本來就是第二階段才會問到的
      'partner_alone_time_acceptance', case when rel.stage >= 2 then p.partner_alone_time_acceptance else null end,
      'housework_model',            case when rel.stage >= 2 then p.housework_model else null end,
      'cleanliness_conflict_style', case when rel.stage >= 2 then p.cleanliness_conflict_style else null end,
      'conflict_pause_preference',  case when rel.stage >= 2 then p.conflict_pause_preference else null end,
      'conflict_return_commitment', case when rel.stage >= 2 then p.conflict_return_commitment else null end
    )
    /* jsonb_build_object 最多只吃 100 個參數（50 組 key/value），第 23 節的九個欄位
       正好把上面那一組頂爆。所以拆成第二組再串起來——兩組沒有重複的 key，
       語意跟寫在同一組裡完全一樣。 */
    || jsonb_build_object(
      -- 第 23 節的三個題組：一樣是第二階段才會問到的。
      -- 宗教與感情史敏感度更高，但揭露層級跟其他第二階段資料一致就夠了——
      -- 再往後推會變成「初診看得到、當事人卻要更晚才知道對方怎麼想」。
      'housework_fairness',           case when rel.stage >= 2 then p.housework_fairness else null end,
      'home_social_frequency',        case when rel.stage >= 2 then p.home_social_frequency else null end,
      'home_guest_boundary',          case when rel.stage >= 2 then p.home_guest_boundary else null end,
      'religion_importance',          case when rel.stage >= 2 then p.religion_importance else null end,
      'religion_partner_expectation', case when rel.stage >= 2 then p.religion_partner_expectation else null end,
      'religion_child_plan',          case when rel.stage >= 2 then p.religion_child_plan else null end,
      'ex_contact_acceptance',        case when rel.stage >= 2 then p.ex_contact_acceptance else null end,
      'opposite_friend_boundary',     case when rel.stage >= 2 then p.opposite_friend_boundary else null end,
      'relationship_boundary_actions',
        case when rel.stage >= 2 then p.relationship_boundary_actions else '[]'::jsonb end,
      'dealbreaker_count', (select count(*) from jsonb_each_text(coalesce(p.dealbreakers,'{}'::jsonb)) d
                             where d.value = 'non_negotiable'),
      -- 第 3 層：要雙方都同意解鎖
      'birth',  case when rel.stage >= 3 and rel.unlock_from and rel.unlock_to then p.birth else null end,
      'locked', case when rel.stage >= 3 and rel.unlock_from and rel.unlock_to then p.locked else null end,
      -- 本人自選揭露時機
      'health', case
        when p.health_when = 'public'
          or (p.health_when = 'stage1' and rel.stage >= 1)
          or (p.health_when = 'stage2' and rel.stage >= 2) then p.health else null end,
      'health_tags', case
        when p.health_when = 'public'
          or (p.health_when = 'stage1' and rel.stage >= 1)
          or (p.health_when = 'stage2' and rel.stage >= 2) then p.health_tags else '[]'::jsonb end,
      'debt', case
        when p.debt_when = 'public'
          or (p.debt_when = 'stage1' and rel.stage >= 1)
          or (p.debt_when = 'stage2' and rel.stage >= 2) then p.debt else null end,
      -- 讓畫面知道「現在是第幾層」，好顯示「🔒 通過第一階段後可見」這類提示
      'rel_stage', coalesce(rel.stage, 0),
      'rel_unlocked', coalesce(rel.stage >= 3 and rel.unlock_from and rel.unlock_to, false)
    )
  from public.match_profiles p
  left join lateral (
    select a.stage, a.unlock_from, a.unlock_to
      from public.applications a
     where ((a.from_user = auth.uid() and a.to_user = p.id)
         or (a.to_user = auth.uid() and a.from_user = p.id))
     order by a.stage desc, a.updated_at desc limit 1
  ) rel on true
  where auth.uid() is not null
    and p.photo_status = 'approved' and p.verify_status = 'approved'
    and p.name <> '' and p.kind <> '' and p.species <> ''
    and p.account_status = 'active'
    and (p_profile_id is null or p.id = p_profile_id)
    and p.id <> auth.uid()
    -- 安全中心：任一方封鎖了對方，雙方就都不會再出現在彼此的佈告欄上
    and not exists (
      select 1 from public.match_user_blocks ub
       where (ub.blocker_id = auth.uid() and ub.blocked_id = p.id)
          or (ub.blocker_id = p.id and ub.blocked_id = auth.uid())
    );
$$;
revoke all on function public.get_visible_match_profiles(uuid) from public, anon;
grant execute on function public.get_visible_match_profiles(uuid) to authenticated;
revoke all on function public.age_bucket(text) from public, anon;
grant execute on function public.age_bucket(text) to authenticated;

-- ============================================================
-- 2b) 第二階段對話：只能由安全函式送出，內含封鎖與速率限制
-- ============================================================
create table if not exists public.match_blocks (
  application_id uuid not null references public.applications(id) on delete cascade,
  blocker_id uuid not null references auth.users(id) on delete cascade,
  reason text default '',
  created_at timestamptz not null default now(),
  primary key (application_id, blocker_id)
);
create table if not exists public.match_messages (
  id bigint generated always as identity primary key,
  application_id uuid not null references public.applications(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'message' check (kind in ('message','question')),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists match_messages_app_created_idx on public.match_messages(application_id, created_at);
create index if not exists match_messages_sender_created_idx on public.match_messages(sender_id, created_at desc);
create index if not exists match_blocks_blocker_idx on public.match_blocks(blocker_id);
do $$ begin
  alter publication supabase_realtime add table public.match_messages;
exception when duplicate_object then null;
end $$;
alter table public.match_blocks enable row level security;
alter table public.match_messages enable row level security;

drop policy if exists "match_blocks_participant_read" on public.match_blocks;
create policy "match_blocks_participant_read" on public.match_blocks for select to authenticated
  using (exists (select 1 from public.applications a where a.id = application_id
    and auth.uid() in (a.from_user, a.to_user)));
drop policy if exists "match_messages_participant_read" on public.match_messages;
create policy "match_messages_participant_read" on public.match_messages for select to authenticated
  using (exists (select 1 from public.applications a where a.id = application_id
    and a.stage >= 2 and auth.uid() in (a.from_user, a.to_user)));

create or replace function public.send_match_message(p_app_id uuid, p_body text, p_kind text default 'message')
returns public.match_messages
language plpgsql security definer set search_path = '' as $$
declare v_app public.applications; v_profile public.match_profiles; v_msg public.match_messages;
begin
  select * into v_app from public.applications where id = p_app_id;
  if v_app is null or auth.uid() not in (v_app.from_user, v_app.to_user) then raise exception '無權使用這個對話'; end if;
  if v_app.stage < 2 or v_app.status <> 'open' then raise exception '第二階段後且申請進行中才能對話'; end if;
  if exists (select 1 from public.match_blocks where application_id = p_app_id) then raise exception '這段對話已被關閉'; end if;
  if public.match_is_blocked(v_app.from_user, v_app.to_user) then raise exception '這段對話已被關閉'; end if;
  select * into v_profile from public.match_profiles where id = auth.uid();
  if v_profile.account_status <> 'active' or v_profile.posting_locked then raise exception '你的發言權限目前受限'; end if;
  if p_kind not in ('message','question') then raise exception '不支援的訊息類型'; end if;
  if char_length(btrim(coalesce(p_body,''))) not between 1 and 2000 then raise exception '訊息需為 1 到 2000 字'; end if;
  if (select count(*) from public.match_messages where sender_id = auth.uid() and created_at > now() - interval '1 minute') >= 10
    then raise exception '傳送太頻繁，請稍後再試'; end if;
  insert into public.match_messages(application_id, sender_id, kind, body)
    values (p_app_id, auth.uid(), p_kind, btrim(p_body)) returning * into v_msg;
  return v_msg;
end $$;
revoke all on function public.send_match_message(uuid,text,text) from public, anon;
grant execute on function public.send_match_message(uuid,text,text) to authenticated;

create or replace function public.close_match_chat(p_app_id uuid, p_reason text default '')
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.applications where id = p_app_id and auth.uid() in (from_user,to_user))
    then raise exception '無權關閉這個對話'; end if;
  insert into public.match_blocks(application_id, blocker_id, reason)
    values (p_app_id, auth.uid(), left(coalesce(p_reason,''),500)) on conflict do nothing;
end $$;
revoke all on function public.close_match_chat(uuid,text) from public, anon;
grant execute on function public.close_match_chat(uuid,text) to authenticated;

-- ============================================================
-- 3) updated_at 自動更新
-- ============================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_match_profiles_touch on public.match_profiles;
create trigger trg_match_profiles_touch before update on public.match_profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_applications_touch on public.applications;
create trigger trg_applications_touch before update on public.applications
  for each row execute function public.touch_updated_at();

-- ============================================================
-- 4) 新帳號註冊時，自動建立一筆空白 profiles
-- ============================================================
create or replace function public.handle_new_match_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.match_profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_match_auth_user_created on auth.users;
create trigger on_match_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_match_user();

-- ============================================================
-- 5) Storage：大頭照（公開）與驗證照（私密，審核完即刪）
-- ============================================================
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
  values ('verify', 'verify', false)
  on conflict (id) do nothing;

-- 檔案路徑統一用 {user_id}/avatar.jpg、{user_id}/verify.jpg
drop policy if exists "avatars_public_read"   on storage.objects;
drop policy if exists "avatars_owner_insert"  on storage.objects;
drop policy if exists "avatars_owner_update"  on storage.objects;
drop policy if exists "avatars_owner_delete"  on storage.objects;
drop policy if exists "verify_owner_all"      on storage.objects;
drop policy if exists "verify_admin_read"     on storage.objects;
drop policy if exists "verify_admin_delete"   on storage.objects;

-- 大頭照：所有人都能讀（bucket 本身設公開），但只有本人能上傳/改/刪自己的檔案
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatars_owner_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- 驗證照：只有本人（上傳/讀取/刪除）與管理員（讀取＋審核後刪除）能存取，其他人完全看不到
create policy "verify_owner_all"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'verify' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'verify' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "verify_admin_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'verify' and public.match_is_admin(auth.uid()));

create policy "verify_admin_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'verify' and public.match_is_admin(auth.uid()));

-- 加碼照片（stage-photos）：私密 bucket，路徑統一用 {user_id}/stage1.jpg、{user_id}/stage2.jpg。
-- 本人／管理員隨時看得到；其他人只有在「自己送給這個人的申請」進度夠了才看得到——
-- 第一階段照片要進到第二階段（stage >= 2）才看得到，第二階段照片要進到第三階段（stage >= 3）。
insert into storage.buckets (id, name, public)
  values ('stage-photos', 'stage-photos', false)
  on conflict (id) do nothing;

drop policy if exists "stage_photos_owner_all"   on storage.objects;
drop policy if exists "stage_photos_admin_read"  on storage.objects;
drop policy if exists "stage_photos_unlock_read" on storage.objects;

create policy "stage_photos_owner_all"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'stage-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'stage-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "stage_photos_admin_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'stage-photos' and public.match_is_admin(auth.uid()));

create policy "stage_photos_unlock_read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'stage-photos'
    and exists (
      select 1 from public.applications a
      where a.to_user = (storage.foldername(name))[1]::uuid
        and a.from_user = auth.uid()
        and (
          (name like '%/stage1%' and a.stage >= 2)
          or (name like '%/stage2%' and a.stage >= 3)
        )
    )
  );

-- ============================================================
-- 6) reports：檢舉（任何人都能送出，只有管理員看得到／能處理）
-- ============================================================
create table if not exists public.reports (
  id         uuid primary key default gen_random_uuid(),
  target_id  uuid references public.match_profiles(id) on delete cascade,
  by_id      uuid references public.match_profiles(id) on delete set null,
  why        text not null,
  done       boolean not null default false,
  created_at timestamptz default now()
);
alter table public.reports drop constraint if exists reports_target_id_fkey;
alter table public.reports drop constraint if exists reports_by_id_fkey;
alter table public.reports add constraint reports_target_id_fkey foreign key (target_id) references public.match_profiles(id) on delete cascade;
alter table public.reports add constraint reports_by_id_fkey foreign key (by_id) references public.match_profiles(id) on delete set null;

create table if not exists public.match_moderation_actions (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  target_id uuid,
  action text not null check (action in ('posting_lock','posting_unlock','suspend','restore','delete')),
  reason text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists match_moderation_actor_idx on public.match_moderation_actions(actor_id);
create index if not exists match_profiles_moderated_by_idx on public.match_profiles(moderated_by);
create index if not exists reports_target_idx on public.reports(target_id);
create index if not exists reports_by_idx on public.reports(by_id);
alter table public.match_moderation_actions enable row level security;
drop policy if exists "moderation_actions_admin_read" on public.match_moderation_actions;
create policy "moderation_actions_admin_read" on public.match_moderation_actions for select to authenticated
  using (public.match_is_admin(auth.uid()));

create table if not exists public.match_ai_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists match_ai_requests_user_created_idx on public.match_ai_requests(user_id, created_at desc);
alter table public.match_ai_requests enable row level security;

alter table public.reports enable row level security;

-- 同一個人對同一個目標，在還沒處理完之前不能重複檢舉（防止洗版把真正的檢舉埋掉）
create unique index if not exists reports_one_open_per_pair
  on public.reports(by_id, target_id) where not done;

drop policy if exists "reports_insert_own"    on public.reports;
drop policy if exists "reports_select_admin"  on public.reports;
drop policy if exists "reports_update_admin"  on public.reports;

create policy "reports_insert_own"
  on public.reports for insert
  to authenticated
  with check (by_id = auth.uid());

create policy "reports_select_admin"
  on public.reports for select
  to authenticated
  using (public.match_is_admin(auth.uid()));

create policy "reports_update_admin"
  on public.reports for update
  to authenticated
  using (public.match_is_admin(auth.uid()))
  with check (public.match_is_admin(auth.uid()));

-- ============================================================
-- 7) template_master：新會員預設的罐頭回覆庫（只有管理員能改）
--    每個會員自己改過的內容存在 profiles.canned，只覆蓋自己的那份，
--    不會動到這裡的主檔；主檔只影響「還原預設」與全新註冊的會員。
-- ============================================================
create table if not exists public.template_master (
  id   text primary key,
  name text not null,
  text text not null
);

alter table public.template_master enable row level security;

drop policy if exists "template_master_select_all" on public.template_master;
drop policy if exists "template_master_write_admin" on public.template_master;

create policy "template_master_select_all"
  on public.template_master for select
  to authenticated
  using (true);

create policy "template_master_write_admin"
  on public.template_master for all
  to authenticated
  using (public.match_is_admin(auth.uid()))
  with check (public.match_is_admin(auth.uid()));

insert into public.template_master (id, name, text) values
('pass1', '① 通過第一階段',
'謝謝你願意完整填寫申請😊
看得出你有認真想過，目前沒有發現明顯的條件衝突，想邀請你進入第二階段。
第二階段沒有標準答案，只是想多了解你面對真實問題時會怎麼想、怎麼做。'),
('supp', '② 請對方補充',
'謝謝你的申請😊
有幾個地方我還不太確定，方便再多說一點嗎？
（列出想問的部分）
不用急著回，慢慢想再告訴我就好。'),
('pass2', '③ 通過第二階段',
'謝謝你花時間回答這些問題😊
你的答案不需要完美，但我感受到你願意思考共同生活這件事。
如果你也還想繼續認識，我們可以進到第三階段，慢慢看看彼此的日常。'),
('hold', '④ 想再觀察一陣子',
'謝謝你的回覆😊
我目前想再多一點時間認識，暫時先維持在這個階段，不急著往下走。
這不是負面的意思，只是希望雙方都不要因為一時熱情而太快推進。'),
('no', '⑤ 婉拒',
'謝謝你願意花時間提出申請，也謝謝你這麼完整地介紹自己😊
想了想，我還是決定先不繼續往下了。
不是你不好，只是在一些對彼此都重要的事情上，方向不太一樣。
祝你早日遇到真正合拍的人🌼'),
('stop', '⑥ 中途喊停',
'謝謝你這段時間的認識😊
我想在這裡先停下來，這個決定與你的好壞無關。
希望你之後一切順利🌼')
on conflict (id) do nothing;

-- profiles.canned 現在給「所有會員」當作自己的罐頭回覆覆蓋值使用
-- （原本註解寫僅 kind='pet' 使用，現在放寬給所有人）
comment on column public.match_profiles.canned is '自訂罐頭回覆庫覆蓋值（所有會員都可使用，對照 template_master 的主檔）';

-- ============================================================
-- 8) owner_kv：私人工具（暖陽動物之家回覆助手）用的個人儲存空間
--
--    講精確一點：下面的 RLS 是 auth.uid() = owner_id，也就是**每個登入的會員都可以
--    讀寫自己的那一份，但讀不到別人的**。這裡沒有、也不該有一份「只有某個 email
--    能用」的白名單——email 白名單屬於前端閘門（js/config.js 的 OWNER_EMAIL），
--    負責決定誰進得去那個頁面。
--
--    兩層合起來才是「只有站長能用那個工具」：
--      前端閘門決定誰進得去，這裡的 RLS 決定誰讀得到站長的資料。
--    就算有人繞過前端直接呼叫 ownerKvSet()，他也只會寫進他自己的那一份。
-- ============================================================
create table if not exists public.owner_kv (
  owner_id   uuid not null references auth.users(id) on delete cascade,
  k          text not null,
  v          text not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, k)
);

alter table public.owner_kv enable row level security;

drop policy if exists "owner_kv_self_all" on public.owner_kv;

create policy "owner_kv_self_all"
  on public.owner_kv for all
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop trigger if exists trg_owner_kv_touch on public.owner_kv;
create trigger trg_owner_kv_touch before update on public.owner_kv
  for each row execute function public.touch_updated_at();

-- ============================================================
-- 9) 安全性補強：擋掉「自己改自己權限／點數」的漏洞
--
--    之前 profiles_update_own 只檢查「改的是不是自己那一列」，
--    沒有檢查「改的是哪一欄」——任何登入的人在瀏覽器 devtools 執行
--      DB.saveMyProfile({is_admin:true, credits:999999, photo_status:'approved'})
--    這種寫法就會直接成功，因為 RLS 從欄位層級來看完全放行。
--
--    這裡用一個 trigger 擋住：is_admin／credits／credit_log／bonus_given
--    這幾欄，非管理員一律強制還原成舊值；photo_status／verify_status
--    不能被自己改成 'approved'（但換照片後系統自動幫你設成 checking/
--    pending/rejected 的既有流程完全不受影響，那是你自己的帳號、自己
--    的操作，不是「核准」）。
--
--    真正需要改動點數的地方（掛號費、診療費、退回掛號費）一律改用下面
--    的安全函式，函式內部用 set_config 開一個「後門旗標」讓 trigger
--    放行，前端／devtools 呼叫不到這個旗標，摸不到後門。
-- ============================================================

create or replace function public.guard_profile_privileged()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- 只管「透過 API 用 authenticated 身分打進來」的請求；
  -- 你自己在 Supabase 後台 SQL Editor／Table Editor 用 postgres/service_role 身分
  -- 直接編輯資料列不受影響（那已經是需要登入你自己 Supabase 帳號才碰得到的層級）。
  if auth.role() = 'authenticated'
     and coalesce(current_setting('app.bypass_profile_guard', true), '') <> 'on'
     and not public.match_is_admin(auth.uid()) then
    new.is_admin    := old.is_admin;
    new.credits     := old.credits;
    new.credit_log  := old.credit_log;
    new.bonus_given := old.bonus_given;
    new.verify_deleted_at := old.verify_deleted_at;
    new.bonus_credits := old.bonus_credits;
    new.restricted_credits := old.restricted_credits;
    new.account_status := old.account_status;
    new.posting_locked := old.posting_locked;
    new.moderation_reason := old.moderation_reason;
    new.moderated_at := old.moderated_at;
    new.moderated_by := old.moderated_by;
    if new.photo_status = 'approved' and old.photo_status is distinct from 'approved' then
      new.photo_status := old.photo_status; new.photo_reason := old.photo_reason;
    end if;
    if new.verify_status = 'approved' and old.verify_status is distinct from 'approved' then
      new.verify_status := old.verify_status; new.verify_reason := old.verify_reason;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_profile_privileged on public.match_profiles;
create trigger trg_guard_profile_privileged before update on public.match_profiles
  for each row execute function public.guard_profile_privileged();

-- 小工具：在 credit_log 最前面加一筆紀錄，並裁到最多 50 筆
create or replace function public.credit_log_prepend(old_log jsonb, entry_obj jsonb, cap int default 50)
returns jsonb language sql immutable set search_path = '' as $$
  select coalesce(
    (select jsonb_agg(elem)
     from (
       select elem
       from jsonb_array_elements(jsonb_build_array(entry_obj) || coalesce(old_log, '[]'::jsonb)) with ordinality as t(elem, ord)
       order by ord limit cap
     ) s),
    jsonb_build_array(entry_obj)
  )
$$;

-- 扣點：申請人自己呼叫，扣什麼、扣多少一律由伺服器這張表決定，
-- 不接受前端傳金額（跟前端顯示的 VET_COST 常數只是給 UI 看，實際收費以這裡為準，
-- 之後要調價記得兩邊一起改）。之後要加新的扣點項目，在 case 裡加一行就好。
drop function if exists public.spend_credits_for(text, text);
create or replace function public.spend_credits_for(p_action text, p_detail text default null)
returns public.match_profiles
language plpgsql security definer set search_path = public as $$
declare v_cost int; v_label text; v_bal int; v_restricted int; v_allow_restricted boolean; v_row public.match_profiles;
begin
  perform public.settle_bonus_credits(auth.uid());
  if not exists (select 1 from public.match_profiles where id = auth.uid()
    and account_status = 'active' and not posting_locked and name <> '') then
    raise exception '請先完成基本資料，或確認帳號發言權限';
  end if;
  case p_action
    when 'vet_review'  then v_cost := 1; v_label := '診療　主治獸醫評估';           v_allow_restricted := true;
    when 'deep_review' then v_cost := 3; v_label := '進階診斷　客製第二階段問題';    v_allow_restricted := true;
    when 'vet_note'    then v_cost := 1; v_label := '診療　主治獸醫備註生成';        v_allow_restricted := false;
    else raise exception '未知的扣點項目：%', p_action;
  end case;

  select credits, coalesce(restricted_credits, 0) into v_bal, v_restricted
    from public.match_profiles where id = auth.uid() for update;
  if v_bal is null then raise exception '找不到你的帳號資料'; end if;
  if v_allow_restricted then
    if v_bal < v_cost then raise exception '點數不足'; end if;
  else
    if (v_bal - v_restricted) < v_cost then
      raise exception '點數不足（有一部分點數是快速邀請的限定用途獎勵，只能用在主治獸醫評估與進階診斷）';
    end if;
  end if;

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.match_profiles set
    credits = credits - v_cost,
    restricted_credits = case when v_allow_restricted
      then greatest(0, coalesce(restricted_credits, 0) - v_cost) else restricted_credits end,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', v_label || coalesce('　' || p_detail, ''), 'd', -v_cost))
  where id = auth.uid()
  returning * into v_row;
  perform set_config('app.bypass_profile_guard', '', true);
  return v_row;
end $$;

-- 舊版的兩參數 apply_to(uuid, jsonb) 曾經在更早的版本清掉過（改寫成殭屍函式的說明，
-- 讓下面的 drop 去清），後來一次大改版又把完整函式本體帶了回來——雖然它插入
-- applications(...,a1,...) 引用的 a1 欄位早就搬到 application_answers 去了，
-- 執行到一半就會報錯，且缺少下面 3 參數版本才有的重複申請檢查、對象是否被停權檢查，
-- 嚴格說仍是一支「一叫就炸、且防護比較弱」的殭屍函式。這次直接不建立它，
-- 下面那個 drop 兼顧「這個檔案沒建過」與「舊資料庫可能還留著」兩種情況。

-- 退回逾期未處理的掛號費：伺服器自己重新檢查一次天數／歸屬／是否已退過，
-- 不相信前端傳來的任何數字，前端只能傳「是哪一筆申請」。
drop function if exists public.refund_application(uuid);
create or replace function public.refund_application(p_app_id uuid)
returns public.match_profiles
language plpgsql security definer set search_path = public as $$
declare v_app public.applications; v_row public.match_profiles;
begin
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.from_user <> auth.uid() then raise exception '這不是你送出的申請'; end if;
  if v_app.refunded then raise exception '已經退過了'; end if;
  if v_app.status <> 'open' or v_app.stage <> 1 then raise exception '目前階段無法退款'; end if;
  if coalesce(v_app.paid, 0) <= 0 then raise exception '這筆申請沒有付款紀錄'; end if;
  if now() - v_app.created_at <= interval '14 days' then raise exception '還沒超過 14 天，暫時無法退款'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set refunded = true where id = p_app_id;
  perform set_config('app.bypass_app_guard', '', true);

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.match_profiles set
    credits = credits + v_app.paid,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '退回掛號費（對方逾期未處理）', 'd', v_app.paid))
  where id = auth.uid()
  returning * into v_row;
  perform set_config('app.bypass_profile_guard', '', true);

  return v_row;
end $$;

-- 管理員手動加點（人工儲值、活動贈點）；也給未來的金流回調重用——
-- 回調是用 service_role 金鑰打進來的，沒有使用者 JWT，所以除了「呼叫者是管理員」，
-- 也放行「呼叫者是 service_role」這個後端專用身分。ref 給訂單編號用，同一筆 ref
-- 重複呼叫不會重複加點（金流商常會重送回調，這裡先把防呆做好）。
drop function if exists public.admin_add_credits(uuid, int, text, text);
create or replace function public.admin_add_credits(target uuid, amount int, reason text, ref text default null)
returns public.match_profiles
language plpgsql security definer set search_path = public as $$
declare v_row public.match_profiles;
begin
  if not (public.match_is_admin(auth.uid()) or auth.role() = 'service_role') then
    raise exception '只有管理員可以使用';
  end if;
  if amount = 0 then raise exception '金額不能是 0'; end if;

  if ref is not null and exists (
    select 1 from public.match_profiles, jsonb_array_elements(coalesce(credit_log, '[]'::jsonb)) elem
    where id = target and elem->>'ref' = ref
  ) then
    select * into v_row from public.match_profiles where id = target;
    return v_row;   -- 同一筆訂單重複呼叫，直接回傳目前狀態，不重複加點
  end if;

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.match_profiles set
    credits = credits + amount,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', reason, 'd', amount, 'ref', ref))
  where id = target
  returning * into v_row;
  perform set_config('app.bypass_profile_guard', '', true);

  if v_row is null then raise exception '找不到這個帳號'; end if;
  return v_row;
end $$;

-- ============================================================
-- 10) 申請內容分離：付費解鎖的第一階段回答、以及申請人的私人筆記
--
--     收件方要付點數才能看第一階段的詳細回答。如果答案還放在 applications 這張表，
--     收件方本來就有讀取整列的權限，前端遮住也沒用（打開 devtools 就讀得到），
--     付費牆等於是假的。所以答案搬到獨立資料表，由 RLS 控管：
--       ・申請人：永遠看得到自己寫的
--       ・收件方：只有 a1_unlocked = true（已付費）之後才看得到
--     申請人的私人筆記 keeper_note 也一併搬走，改成只有本人看得到（原本收件方
--     其實查得到那個欄位，這是之前 README 就記載的已知缺陷，這次一併修掉）。
-- ============================================================

create table if not exists public.application_answers (
  application_id uuid primary key references public.applications(id) on delete cascade,
  a1         jsonb,
  a2         jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.application_private_notes (
  application_id uuid primary key references public.applications(id) on delete cascade,
  owner_id   uuid not null references auth.users(id) on delete cascade,
  note       text,
  updated_at timestamptz not null default now()
);
create index if not exists application_private_notes_owner_idx on public.application_private_notes(owner_id);

-- 一次性搬遷：把舊欄位的內容複製到新表，然後把舊欄位刪掉。
-- 舊欄位不刪的話，收件方還是讀得到，付費牆就漏了。
-- 既有的申請一律標記成「已解鎖」，不會回頭跟人收錢。
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'applications' and column_name = 'a1') then
    insert into public.application_answers (application_id, a1, a2)
      select id, a1, a2 from public.applications where a1 is not null or a2 is not null
      on conflict (application_id) do nothing;
    update public.applications set a1_unlocked = true where a1 is not null;
    alter table public.applications drop column a1;
    alter table public.applications drop column a2;
  end if;

  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'applications' and column_name = 'keeper_note') then
    insert into public.application_private_notes (application_id, owner_id, note)
      select id, from_user, keeper_note from public.applications where keeper_note is not null
      on conflict (application_id) do nothing;
    alter table public.applications drop column keeper_note;
  end if;
end $$;

alter table public.application_answers       enable row level security;
alter table public.application_private_notes enable row level security;

drop policy if exists "answers_select_allowed"  on public.application_answers;
drop policy if exists "answers_update_owner"    on public.application_answers;
drop policy if exists "notes_all_owner"         on public.application_private_notes;

-- 申請人永遠看得到自己的答案；收件方要付費解鎖後才看得到
create policy "answers_select_allowed"
  on public.application_answers for select
  to authenticated
  using (exists (
    select 1 from public.applications a
    where a.id = application_id
      and (a.from_user = auth.uid()
        or (a.to_user = auth.uid() and a.a1_unlocked))
  ));

-- 回答只能透過 apply_to()/submit_stage2() 寫入，避免事後直接改第一階段答案。

-- 私人筆記：只有寫的人看得到、改得動
create policy "notes_all_owner"
  on public.application_private_notes for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop trigger if exists trg_answers_touch on public.application_answers;
create trigger trg_answers_touch before update on public.application_answers
  for each row execute function public.touch_updated_at();
drop trigger if exists trg_notes_touch on public.application_private_notes;
create trigger trg_notes_touch before update on public.application_private_notes
  for each row execute function public.touch_updated_at();

-- ── 申請單也要擋住「自己改自己的付費狀態」 ──
--    applications 的 RLS 只檢查「是不是這筆申請的當事人」，沒有檢查改的是哪一欄。
--    收件方可以直接送 update applications set a1_unlocked = true 就白嫖解鎖，
--    或者把 stage 從 1 改成 2 跳過第二階段的出題費。跟 profiles 一樣用 trigger 擋住，
--    這幾欄只能由下面那些會扣點的安全函式來改。
--
--    unlock_from／unlock_to 也一起擋：這兩欄原本雙方都能直接 update（applications
--    的 update 政策是整列層級，不分欄位），代表申請人或收件方其實可以直接把「對方」
--    那一欄也設成 true，等於幫對方蓋章同意，不需要對方真的按下同意。這次順便修掉。
create or replace function public.guard_application_privileged()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.role() = 'authenticated'
     and coalesce(current_setting('app.bypass_app_guard', true), '') <> 'on'
     and not public.match_is_admin(auth.uid()) then
    new.from_user   := old.from_user;
    new.to_user     := old.to_user;
    new.stage       := old.stage;
    new.a1_unlocked := old.a1_unlocked;
    new.stage2_paid := old.stage2_paid;
    new.paid        := old.paid;
    new.refunded    := old.refunded;
    new.consent_at  := old.consent_at;
    new.unlock_from := old.unlock_from;
    new.unlock_to   := old.unlock_to;
    new.skipped     := old.skipped;
    new.fast_invite_from := old.fast_invite_from;
    new.fast_invite_to := old.fast_invite_to;
    new.priority_invite := old.priority_invite;
    new.priority_note := old.priority_note;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_application on public.applications;
create trigger trg_guard_application before update on public.applications
  for each row execute function public.guard_application_privileged();

-- ── 我的答題紀錄：把送出的答案存進申請人自己的 profiles.answer_bank ──
-- 以「題目文字」去重（同一題只留最新的答案），最多保留 100 筆。
create or replace function public.answer_bank_merge(old_bank jsonb, entries jsonb, cap int default 100)
returns jsonb language sql immutable set search_path = '' as $$
  with all_rows as (
    -- 新答案排在前面（ord 小），舊的接在後面，這樣同一題會保留最新的那筆
    select elem, ord from jsonb_array_elements(coalesce(entries, '[]'::jsonb)) with ordinality as t(elem, ord)
    union all
    select elem, ord + 1000000 from jsonb_array_elements(coalesce(old_bank, '[]'::jsonb)) with ordinality as t(elem, ord)
  ), dedup as (
    select distinct on (btrim(elem->>'q')) elem, ord
    from all_rows
    where btrim(coalesce(elem->>'q', '')) <> ''
    order by btrim(elem->>'q'), ord
  ), capped as (
    select elem, ord from dedup order by ord limit cap
  )
  select coalesce((select jsonb_agg(elem order by ord) from capped), '[]'::jsonb)
$$;

-- 提出申請（取代第 9 節的舊版 apply_to）：
-- 扣掛號費＋建立申請＋寫入受保護的答案表＋記錄隱私權同意＋存進答題紀錄，全部同一個交易。
drop function if exists public.apply_to(uuid, jsonb);
-- 新的點數哲學：免費的是「建立關係」，收費的是「效率與 AI」。掛號費從此不再是每一筆
-- 都收，改成每 7 天內前 3 筆免費，超過的部分才收 1 點——多數人正常使用完全不用花錢，
-- 收費只在真的想大量灌申請時才會碰到。
create or replace function public.apply_to(p_to uuid, p_answers jsonb, p_questions jsonb default '[]'::jsonb)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_free_quota constant int := 3;   -- 每 7 天內免費申請次數
  v_extra_cost constant int := 1;   -- 超過免費次數之後，每筆額外收費
  v_cost int := 0;
  v_recent_count int; v_bal int; v_app public.applications; v_entries jsonb;
begin
  perform public.settle_bonus_credits(auth.uid());
  if not exists (select 1 from public.match_profiles where id = auth.uid()
    and account_status = 'active' and not posting_locked and name <> '') then
    raise exception '請先完成基本資料，或確認帳號發言權限';
  end if;
  if p_to = auth.uid() then raise exception '不能對自己提出申請'; end if;
  if public.match_is_blocked(auth.uid(), p_to) then raise exception '無法對這個帳號提出申請'; end if;
  if not exists (
    select 1 from public.match_profiles
    where id = p_to and photo_status = 'approved' and verify_status = 'approved'
  ) then
    raise exception '對方尚未通過審核，暫時無法申請';
  end if;
  -- 只有 UI 隱藏了「已經申請過」的按鈕，直接呼叫這支函式沒有這層防護，
  -- 會讓人可以繞過畫面對同一個人重複灌爆申請——這裡補上伺服器端檢查。
  if exists (
    select 1 from public.applications where from_user = auth.uid() and to_user = p_to
  ) then
    raise exception '已經申請過了';
  end if;

  select count(*) into v_recent_count from public.applications
    where from_user = auth.uid() and created_at > now() - interval '7 days';
  if v_recent_count >= v_free_quota then
    v_cost := v_extra_cost;
    select credits - coalesce(restricted_credits, 0) into v_bal
      from public.match_profiles where id = auth.uid() for update;
    if v_bal is null or v_bal < v_cost then
      raise exception '本週 % 次免費申請已經用完，多送一筆需要 % 點，且點數不足（一鍵通關的限定用途獎勵點數不能用來付這筆費用）', v_free_quota, v_cost;
    end if;
  else
    perform 1 from public.match_profiles where id = auth.uid() for update;
  end if;

  insert into public.applications(from_user, to_user, stage, status, paid, consent_at)
  values (auth.uid(), p_to, 1, 'open', v_cost, now())
  returning * into v_app;

  insert into public.application_answers(application_id, a1)
  values (v_app.id, p_answers);

  -- 存進申請人自己的答題紀錄
  select jsonb_agg(jsonb_build_object(
           'q', p_questions->>(i-1), 'a', p_answers->>(i-1), 'at', now()))
    into v_entries
    from generate_series(1, jsonb_array_length(coalesce(p_questions,'[]'::jsonb))) i
    where coalesce(p_answers->>(i-1), '') <> '';

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.match_profiles set
    credits = credits - v_cost,
    answer_bank = public.answer_bank_merge(answer_bank, coalesce(v_entries,'[]'::jsonb)),
    credit_log = case when v_cost > 0 then public.credit_log_prepend(credit_log, jsonb_build_object(
        'at', now(), 't', '掛號　超過本週免費次數，向 ' || (select name from public.match_profiles where id = p_to) || ' 提出申請', 'd', -v_cost))
      else credit_log end
  where id = auth.uid();
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;

-- 收件方付費解鎖第一階段詳細回答
create or replace function public.unlock_a1(p_app_id uuid)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_cost constant int := 1;
  v_app public.applications; v_bal int;
begin
  perform public.settle_bonus_credits(auth.uid());
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.to_user <> auth.uid() then raise exception '這不是你收到的申請'; end if;
  if v_app.a1_unlocked then return v_app; end if;   -- 已解鎖就不再收費

  select credits into v_bal from public.match_profiles where id = auth.uid() for update;
  if v_bal is null or v_bal < v_cost then raise exception '點數不足'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set a1_unlocked = true where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.match_profiles set
    credits = credits - v_cost,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '調閱　第一階段詳細回答', 'd', -v_cost))
  where id = auth.uid();
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;

-- 收件方付費發出第二階段問卷（同時把申請推進到第二階段）
create or replace function public.send_stage2(p_app_id uuid, p_questions jsonb)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_cost constant int := 2;
  v_app public.applications; v_bal int;
begin
  perform public.settle_bonus_credits(auth.uid());
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.to_user <> auth.uid() then raise exception '這不是你收到的申請'; end if;
  if v_app.status <> 'open' then raise exception '這筆申請已經結束了'; end if;
  if v_app.stage <> 1 then raise exception '這筆申請不在第一階段'; end if;
  if not v_app.a1_unlocked then raise exception '請先解鎖並讀過第一階段回答'; end if;
  if jsonb_array_length(coalesce(p_questions,'[]'::jsonb)) = 0 then raise exception '至少要出一題'; end if;

  if not v_app.stage2_paid then
    select credits - coalesce(restricted_credits, 0) into v_bal
      from public.match_profiles where id = auth.uid() for update;
    if v_bal is null or v_bal < v_cost then
      raise exception '點數不足（一鍵通關的限定用途獎勵點數不能用來付出題費）';
    end if;
    perform set_config('app.bypass_profile_guard', 'on', true);
    update public.match_profiles set
      credits = credits - v_cost,
      credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '出題　發出第二階段問卷', 'd', -v_cost))
    where id = auth.uid();
    perform set_config('app.bypass_profile_guard', '', true);
  end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications
    set stage = 2, a2_questions = p_questions, stage2_paid = true
    where id = p_app_id
    returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);
  return v_app;
end $$;

-- 通過第二階段、進入第三階段（不收費，但一樣要由伺服器驗證，
-- 因為 stage 這一欄已經被 trigger 鎖住，前端改不動）
create or replace function public.advance_stage3(p_app_id uuid)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare v_app public.applications; v_has_a2 boolean;
begin
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.to_user <> auth.uid() then raise exception '這不是你收到的申請'; end if;
  if v_app.status <> 'open' then raise exception '這筆申請已經結束了'; end if;
  if v_app.stage <> 2 then raise exception '這筆申請不在第二階段'; end if;
  select a2 is not null into v_has_a2 from public.application_answers where application_id = p_app_id;
  if not coalesce(v_has_a2, false) then raise exception '對方還沒送出第二階段回答'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set stage = 3 where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);
  return v_app;
end $$;

-- 第三階段：申請人付 3 點解鎖對方的日常觀察資訊。
-- 收件方那邊仍然要自己免費按「同意解鎖」（見下面 consent_unlock_to），
-- 兩邊都解鎖了才會互相看到——維持原本互相同意的精神，只是申請人這邊多一道付費關卡。
-- 解鎖聯絡方式改成免費（新的點數哲學：免費的是「建立關係」，收費的是「效率與 AI」）。
-- 函式名稱保留 unlock_stage3，前端呼叫的地方不用跟著改。
-- 交換聯絡方式是整個流程裡風險最高的一步，所以兩邊的解鎖函式都要求先確認過安全提醒
-- （p_safety_ack）。畫面上會跳出安全中心的檢查清單，勾完才會帶 true 進來——
-- 舊的單參數版本要明確 drop 掉，不然會留下一支可以繞過確認的覆載。
drop function if exists public.unlock_stage3(uuid);
create or replace function public.unlock_stage3(p_app_id uuid, p_safety_ack boolean default false)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare v_app public.applications;
begin
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.from_user <> auth.uid() then raise exception '這不是你送出的申請'; end if;
  if v_app.stage <> 3 then raise exception '這筆申請還沒進入第三階段'; end if;
  if v_app.unlock_from then return v_app; end if;
  if public.match_is_blocked(v_app.from_user, v_app.to_user) then raise exception '這段聯繫已經結束'; end if;
  if not coalesce(p_safety_ack, false) then raise exception '請先閱讀並確認安全提醒'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set unlock_from = true where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);

  return v_app;
end $$;

-- 收件方同意解鎖（免費，維持原本設計）
drop function if exists public.consent_unlock_to(uuid);
create or replace function public.consent_unlock_to(p_app_id uuid, p_safety_ack boolean default false)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare v_app public.applications;
begin
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.to_user <> auth.uid() then raise exception '這不是你收到的申請'; end if;
  if v_app.stage <> 3 then raise exception '這筆申請還沒進入第三階段'; end if;
  if v_app.unlock_to then return v_app; end if;
  if public.match_is_blocked(v_app.from_user, v_app.to_user) then raise exception '這段聯繫已經結束'; end if;
  if not coalesce(p_safety_ack, false) then raise exception '請先閱讀並確認安全提醒'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set unlock_to = true where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);
  return v_app;
end $$;

-- 把逾期未花完的一鍵通關獎勵點數收回。因為沒有排程工作，改成「有需要就順手結算」：
-- 在會動到點數的安全函式最前面呼叫一次，前端登入後也會呼叫一次，盡量不要讓人
-- 忘記用掉的點數一直掛在帳上。同一筆獎勵可能還沒到期，就繼續留著。
create or replace function public.settle_bonus_credits(p_uid uuid default auth.uid())
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_bank jsonb; v_entry jsonb; v_keep jsonb := '[]'::jsonb;
  v_credits int; v_remaining int; v_deduct int; v_total_deduct int := 0;
  v_restricted int; v_restricted_remaining int; v_restricted_deduct int; v_total_restricted_deduct int := 0;
begin
  if p_uid is null then return; end if;
  if p_uid <> auth.uid() and auth.role() <> 'service_role' and not public.match_is_admin(auth.uid()) then
    raise exception '無權結算其他帳號';
  end if;
  select bonus_credits, credits, coalesce(restricted_credits, 0) into v_bank, v_credits, v_restricted
    from public.match_profiles where id = p_uid for update;
  if v_bank is null or jsonb_array_length(v_bank) = 0 then return; end if;

  v_remaining := coalesce(v_credits, 0);
  v_restricted_remaining := v_restricted;
  for v_entry in select * from jsonb_array_elements(v_bank) loop
    if (v_entry->>'expires_at')::timestamptz <= now() then
      v_deduct := least(v_remaining, (v_entry->>'amount')::int);
      v_remaining := v_remaining - v_deduct;
      v_total_deduct := v_total_deduct + v_deduct;
      -- 這筆獎勵到期了，不管花掉了多少，剩下追蹤的「限定用途餘額」也要跟著清掉，
      -- 不然 restricted_credits 之後會比實際點數還多，把使用者一般點數也一起卡住。
      v_restricted_deduct := least(v_restricted_remaining, (v_entry->>'amount')::int);
      v_restricted_remaining := v_restricted_remaining - v_restricted_deduct;
      v_total_restricted_deduct := v_total_restricted_deduct + v_restricted_deduct;
    else
      v_keep := v_keep || jsonb_build_array(v_entry);
    end if;
  end loop;

  if jsonb_array_length(v_keep) < jsonb_array_length(v_bank) then
    perform set_config('app.bypass_profile_guard', 'on', true);
    update public.match_profiles set
      bonus_credits = v_keep,
      credits = credits - v_total_deduct,
      restricted_credits = greatest(0, coalesce(restricted_credits, 0) - v_total_restricted_deduct),
      credit_log = case when v_total_deduct > 0
        then public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '一鍵通關獎勵點數逾期收回', 'd', -v_total_deduct))
        else credit_log end
    where id = p_uid;
    perform set_config('app.bypass_profile_guard', '', true);
  end if;
end $$;

-- 舊版單方「一鍵通關」停用：不能再由一方付款替另一方表示同意。
create or replace function public.skip_to_unlock(p_app_id uuid)
returns public.applications
language plpgsql security definer set search_path = public as $$
begin
  raise exception '一鍵通關已停用，請改用雙方同意的快速邀請';
end $$;

-- 舊版「快速邀請」（付點數直接跳過三階段審查）已經整個停用：課金插隊跟「慎重不是門檻，
-- 而是尊重」的品牌精神直接衝突，而且點數進到對方帳號，觀感上太接近「花錢買關注」。
-- 改成「優先邀請」：不能跳過任何審查階段，純粹是申請人付點數讓自己的申請在對方收件匣裡
-- 多一個「優先考慮」標記，附上一封最多 300 字的邀請信，對方看不看、要不要提早處理仍然
-- 由對方決定；點數留在平台，不會轉給任何一方。
drop function if exists public.request_fast_track(uuid);
drop function if exists public.accept_fast_track(uuid);

create or replace function public.send_priority_invite(p_app_id uuid, p_note text default '')
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_cost constant int := 3;
  v_app public.applications; v_bal int;
begin
  perform public.settle_bonus_credits(auth.uid());
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null or v_app.from_user <> auth.uid() then raise exception '這不是你送出的申請'; end if;
  if v_app.status <> 'open' or v_app.stage >= 3 then raise exception '目前階段不能送優先邀請'; end if;
  if v_app.priority_invite then raise exception '已經送過優先邀請了'; end if;

  select credits - coalesce(restricted_credits, 0) into v_bal
    from public.match_profiles where id = auth.uid() for update;
  if v_bal is null or v_bal < v_cost then
    raise exception '點數不足（一鍵通關的限定用途獎勵點數不能用來付這筆費用）';
  end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set
    priority_invite = true, priority_note = left(coalesce(p_note, ''), 300)
  where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.match_profiles set
    credits = credits - v_cost,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '優先邀請　讓申請在對方收件匣被優先考慮', 'd', -v_cost))
  where id = auth.uid();
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;
revoke all on function public.send_priority_invite(uuid, text) from public, anon;
grant execute on function public.send_priority_invite(uuid, text) to authenticated;

-- 申請人送出第二階段回答（一併存進答題紀錄）
create or replace function public.submit_stage2(p_app_id uuid, p_answers jsonb, p_questions jsonb default '[]'::jsonb)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare v_app public.applications; v_entries jsonb;
begin
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.from_user <> auth.uid() then raise exception '這不是你送出的申請'; end if;
  if v_app.stage <> 2 or v_app.status <> 'open' then raise exception '目前階段無法作答'; end if;

  update public.application_answers set a2 = p_answers where application_id = p_app_id;
  if not found then
    insert into public.application_answers(application_id, a2) values (p_app_id, p_answers);
  end if;

  select jsonb_agg(jsonb_build_object(
           'q', p_questions->>(i-1), 'a', p_answers->>(i-1), 'at', now()))
    into v_entries
    from generate_series(1, jsonb_array_length(coalesce(p_questions,'[]'::jsonb))) i
    where coalesce(p_answers->>(i-1), '') <> '';

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.match_profiles
    set answer_bank = public.answer_bank_merge(answer_bank, coalesce(v_entries,'[]'::jsonb))
    where id = auth.uid();
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;

-- ============================================================
-- 10.5) 修正舊資料庫殘留、缺少 on delete cascade／set null 的外鍵
--    這幾張表在很早期的版本可能是先建立、後來才補上 on delete 規則；
--    CREATE TABLE IF NOT EXISTS 不會回頭修正已經存在的資料表與外鍵約束，
--    導致管理後台呼叫 admin.auth.admin.deleteUser() 刪帳號時，被殘留的
--    外鍵擋下、回一句「Database error deleting user」。這裡逐一檢查、
--    必要時重建這幾個外鍵，只動這個專案自己的表，不會動到其他產品
--    共用同一個 Supabase 專案時可能存在的其他資料表（例如 public.profiles）。
-- ============================================================
do $$
declare
  spec record;
  con record;
begin
  for spec in
    select * from (values
      ('match_profiles', 'id', 'cascade'),
      ('match_profiles', 'moderated_by', 'set null'),
      ('applications', 'from_user', 'cascade'),
      ('applications', 'to_user', 'cascade'),
      ('match_blocks', 'blocker_id', 'cascade'),
      ('match_messages', 'sender_id', 'cascade'),
      ('match_moderation_actions', 'actor_id', 'set null'),
      ('match_ai_requests', 'user_id', 'cascade'),
      ('owner_kv', 'owner_id', 'cascade'),
      ('application_private_notes', 'owner_id', 'cascade')
    ) as t(tbl, col, want)
  loop
    if to_regclass('public.' || spec.tbl) is null then continue; end if;
    for con in
      select c.conname, c.confdeltype
      from pg_constraint c
      where c.conrelid = ('public.' || spec.tbl)::regclass
        and c.contype = 'f'
        and c.confrelid = 'auth.users'::regclass
        and array_length(c.conkey, 1) = 1
        and (select attname from pg_attribute
             where attrelid = c.conrelid and attnum = c.conkey[1]) = spec.col
    loop
      if (spec.want = 'cascade' and con.confdeltype <> 'c')
         or (spec.want = 'set null' and con.confdeltype <> 'n') then
        execute format('alter table public.%I drop constraint %I', spec.tbl, con.conname);
        execute format('alter table public.%I add constraint %I foreign key (%I) references auth.users(id) on delete %s',
          spec.tbl, con.conname, spec.col, spec.want);
      end if;
    end loop;
  end loop;
end $$;

-- ============================================================
-- 10.6) 通知鈴鐺：管理員審核結果、新訊息
--    以前退回審核只會把原因寫進 photo_reason／verify_reason，畫面上
--    只有使用者自己點進「我的資料」才看得到；而且一旦重新上傳照片，
--    這兩個欄位會立刻被清成空字串準備進入下一輪審核，原本的退回原因
--    就這樣不見了，等於「被退審了都不知道，原因也看不到」。這裡改成
--    用 trigger 在審核結果／發言限制「變動的當下」就存一筆通知，
--    跟 photo_reason 之後會不會被覆蓋無關，右上角小鈴鐺會提醒使用者。
-- ============================================================
create table if not exists public.match_notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null default 'admin' check (kind in ('admin','message')),
  title      text not null,
  body       text not null default '',
  link_app_id uuid references public.applications(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists match_notifications_user_created_idx
  on public.match_notifications(user_id, created_at desc);
create index if not exists match_notifications_unread_idx
  on public.match_notifications(user_id) where read_at is null;
alter table public.match_notifications enable row level security;

drop policy if exists "match_notifications_select_own" on public.match_notifications;
create policy "match_notifications_select_own" on public.match_notifications
  for select to authenticated using (user_id = auth.uid());
-- 故意不開放 authenticated 直接 insert/update：只能透過下面的 security definer
-- trigger／函式寫入，前端沒辦法幫自己捏造一則「管理員訊息」或偷看已讀狀態以外的東西。

create or replace function public.notify_profile_review_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.photo_status is distinct from old.photo_status and new.photo_status in ('approved','rejected') then
    insert into public.match_notifications(user_id, kind, title, body) values (
      new.id, 'admin',
      case when new.photo_status = 'approved' then '大頭照審核通過' else '大頭照審核未通過' end,
      case when new.photo_status = 'approved' then '你的大頭照已經通過審核。'
           else coalesce(nullif(new.photo_reason, ''), '請重新上傳照片。') end
    );
  end if;
  if new.verify_status is distinct from old.verify_status and new.verify_status in ('approved','rejected') then
    insert into public.match_notifications(user_id, kind, title, body) values (
      new.id, 'admin',
      case when new.verify_status = 'approved' then '身分驗證通過' else '身分驗證未通過' end,
      case when new.verify_status = 'approved' then '你的身分驗證已經通過審核。'
           else coalesce(nullif(new.verify_reason, ''), '請重新上傳驗證照。') end
    );
  end if;
  if new.account_status = 'suspended' and old.account_status is distinct from 'suspended' then
    insert into public.match_notifications(user_id, kind, title, body) values (
      new.id, 'admin', '帳號已被停用登入', coalesce(nullif(new.moderation_reason, ''), '如有疑問請聯絡站方。')
    );
  elsif old.account_status = 'suspended' and new.account_status = 'active' then
    insert into public.match_notifications(user_id, kind, title, body) values (
      new.id, 'admin', '帳號已恢復', '你的帳號已經恢復，可以重新登入使用。'
    );
  end if;
  if new.posting_locked and not old.posting_locked then
    insert into public.match_notifications(user_id, kind, title, body) values (
      new.id, 'admin', '發言權限已被限制', coalesce(nullif(new.moderation_reason, ''), '如有疑問請聯絡站方。')
    );
  elsif old.posting_locked and not new.posting_locked then
    insert into public.match_notifications(user_id, kind, title, body) values (
      new.id, 'admin', '發言限制已解除', '你可以重新使用送出申請、對話與 AI 功能。'
    );
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_profile_review_change on public.match_profiles;
create trigger trg_notify_profile_review_change after update on public.match_profiles
  for each row execute function public.notify_profile_review_change();

create or replace function public.notify_new_match_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_app public.applications; v_recipient uuid; v_sender_name text;
begin
  select * into v_app from public.applications where id = new.application_id;
  if v_app is null then return new; end if;
  v_recipient := case when v_app.from_user = new.sender_id then v_app.to_user else v_app.from_user end;
  select name into v_sender_name from public.match_profiles where id = new.sender_id;
  insert into public.match_notifications(user_id, kind, title, body, link_app_id) values (
    v_recipient, 'message', coalesce(nullif(v_sender_name, ''), '對方') || ' 傳了新訊息給你',
    left(new.body, 80), new.application_id
  );
  return new;
end $$;

drop trigger if exists trg_notify_new_match_message on public.match_messages;
create trigger trg_notify_new_match_message after insert on public.match_messages
  for each row execute function public.notify_new_match_message();

create or replace function public.mark_notifications_read(p_ids bigint[])
returns void language sql security definer set search_path = public as $$
  update public.match_notifications set read_at = now()
    where user_id = auth.uid() and id = any(p_ids) and read_at is null;
$$;
revoke all on function public.mark_notifications_read(bigint[]) from public, anon;
grant execute on function public.mark_notifications_read(bigint[]) to authenticated;

create or replace function public.mark_all_notifications_read()
returns void language sql security definer set search_path = public as $$
  update public.match_notifications set read_at = now()
    where user_id = auth.uid() and read_at is null;
$$;
revoke all on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.mark_all_notifications_read() to authenticated;

-- ============================================================
-- 11) 把自己設成管理員（審核台權限）
--    這行不會自動執行——執行完上面全部之後，自己先用這個帳號登入一次，
--    再回到 SQL Editor，把 <你的帳號 email> 換成自己的 email，單獨執行這一段：
--
--    update public.match_profiles set is_admin = true
--    where id = (select id from auth.users where email = '<你的帳號 email>');
-- ============================================================

-- ============================================================
-- 12) 最小權限：移除 Supabase 新表可能繼承的寬鬆預設 grants
-- ============================================================
revoke all on table public.match_profiles, public.applications, public.application_answers,
  public.application_private_notes, public.match_messages, public.match_blocks,
  public.reports, public.match_moderation_actions, public.match_ai_requests,
  public.match_notifications, public.match_user_blocks from anon;
revoke truncate, references, trigger on table public.match_profiles, public.applications,
  public.application_answers, public.application_private_notes, public.match_messages,
  public.match_blocks, public.reports, public.match_moderation_actions, public.match_ai_requests,
  public.match_notifications, public.match_user_blocks from authenticated;
revoke insert, update, delete on table public.match_notifications from authenticated;
-- 封鎖名單只能自己看與自己解除；新增一律走 block_user()，才會一併關掉既有對話
revoke insert, update on table public.match_user_blocks from authenticated;
grant select, delete on table public.match_user_blocks to authenticated;
grant select, insert, update, delete on table public.match_profiles to authenticated;
grant select, update, delete on table public.applications to authenticated;
grant select on table public.application_answers to authenticated;
grant select, insert, update, delete on table public.application_private_notes to authenticated;
grant select on table public.match_messages, public.match_blocks to authenticated;
grant insert, select, update on table public.reports to authenticated;
grant select on table public.match_moderation_actions to authenticated;
grant select on table public.match_notifications to authenticated;

drop policy if exists "match_ai_requests_no_client_access" on public.match_ai_requests;
create policy "match_ai_requests_no_client_access" on public.match_ai_requests for all
  to anon, authenticated using (false) with check (false);

revoke all on function public.handle_new_match_user() from public, anon, authenticated;
grant execute on function public.handle_new_match_user() to postgres, service_role;

revoke all on function public.match_is_admin(uuid), public.spend_credits_for(text,text),
  public.apply_to(uuid,jsonb,jsonb), public.refund_application(uuid),
  public.admin_add_credits(uuid,int,text,text), public.unlock_a1(uuid),
  public.send_stage2(uuid,jsonb), public.advance_stage3(uuid), public.unlock_stage3(uuid,boolean),
  public.consent_unlock_to(uuid,boolean), public.settle_bonus_credits(uuid), public.skip_to_unlock(uuid),
  public.submit_stage2(uuid,jsonb,jsonb) from public, anon;
grant execute on function public.match_is_admin(uuid), public.spend_credits_for(text,text),
  public.apply_to(uuid,jsonb,jsonb), public.refund_application(uuid),
  public.admin_add_credits(uuid,int,text,text), public.unlock_a1(uuid),
  public.send_stage2(uuid,jsonb), public.advance_stage3(uuid), public.unlock_stage3(uuid,boolean),
  public.consent_unlock_to(uuid,boolean), public.settle_bonus_credits(uuid), public.skip_to_unlock(uuid),
  public.submit_stage2(uuid,jsonb,jsonb) to authenticated;

-- ============================================================
-- 13) 主治醫師初診：規則引擎（免費、0 API 成本）
--
--     規格見 docs/screening-crm-spec.md。這一節實作規格的第 1、2 步：
--       ・weekly_work_hours 數值欄位（一個欄位解決 R001–R005 五條規則）
--       ・screening_rules / screening_results 兩張表
--       ・條件式直譯器（screening_ref / screening_eval）
--       ・run_screening() / get_screening_for()
--       ・R047–R054 禁止規則，而且是「會擋下寫入」的那種，不是註解裡的約定
--
--     稱謂約定（整節通用）：
--       applicant = 被評估的那個人（佈告欄上你正在看的人／CRM 裡的申請人）
--       recipient = 看報告的人（你自己／CRM 裡的收件人）
-- ============================================================

-- 13.1 一週工作時數改成數值 -----------------------------------
-- 原本的 work_hours 是自由文字（「例：45 小時」），規則沒辦法可靠解析
-- 「約 40-50」「看情況」這種輸入。保留 work_hours 當顯示用，另外存一個數值欄。
-- 欄位本身宣告在第 1 節（見「一週工作時數」）——get_visible_match_profiles()
-- 在那之後就會引用它，而 SQL 函式建立當下就會驗證函式本體，欄位必須先存在。

-- 從舊的自由文字欄回填：只取第一個數字，而且只在看起來合理（1–168）時才寫進去。
-- 冪等：只補 weekly_work_hours 還是 null 的列。
update public.match_profiles
   set weekly_work_hours = sub.n
  from (
    select id, nullif(regexp_replace(coalesce(work_hours,''), '[^0-9].*$', ''), '')::int as n
      from public.match_profiles
     where weekly_work_hours is null and coalesce(work_hours,'') ~ '^[^0-9]*[0-9]'
  ) sub
 where public.match_profiles.id = sub.id
   and sub.n between 1 and 168;

-- 13.2 Dealbreaker 嚴重度 --------------------------------------
-- 規格第 1.4 節：沒有這個維度，所有 🔴 都做不出來。欄位先開，表單 UI 之後才做，
-- 預設 {} 代表「沒有任何不可妥協條件」，不會憑空產生紅燈。
-- 欄位本身同樣宣告在第 1 節。

-- 13.3 規則表 --------------------------------------------------
create table if not exists public.screening_rules (
  code         text primary key,
  topic        text not null default '',
  category     text not null default '',
  outcome      text not null
                 check (outcome in ('green','yellow','red','unknown','safety','never')),
  priority     smallint not null default 50,
  min_stage    smallint not null default 1,
  min_stage_ref text,                       -- 揭露層級跟著某個欄位走（R055 用）
  audience     text not null default 'member' check (audience in ('member','admin')),
  cond         jsonb not null default '{}'::jsonb,
  escalate     jsonb,
  requires     text[] not null default '{}',
  reason_code  text,
  title        text not null default '',
  body         text not null default '',
  ask          jsonb not null default '[]'::jsonb,
  enabled      boolean not null default true,
  updated_at   timestamptz not null default now()
);
alter table public.screening_rules add column if not exists min_stage_ref text;
alter table public.screening_rules add column if not exists escalate jsonb;
alter table public.screening_rules add column if not exists reason_code text;

create table if not exists public.screening_results (
  id          bigserial primary key,
  app_id      uuid references public.applications(id) on delete cascade,
  from_user   uuid not null references auth.users(id) on delete cascade,
  to_user     uuid not null references auth.users(id) on delete cascade,
  audience    text not null default 'member' check (audience in ('member','admin')),
  ran_at      timestamptz not null default clock_timestamp(),
  rules_ver   text not null default 'v1',
  inputs_seen smallint not null default 0,
  green       smallint not null default 0,
  yellow      smallint not null default 0,
  red         smallint not null default 0,
  unknown     smallint not null default 0,
  safety      smallint not null default 0,
  findings    jsonb not null default '[]'::jsonb,
  unique (from_user, to_user, audience)
);

-- 13.4 禁止規則（R047–R054）----------------------------------
-- 「MBTI 不產生黃燈」寫在註解裡，遲早有人忘記。這裡把它變成會擋下寫入的檢查：
-- 禁止清單本身就是 outcome='never' 的那幾條規則，所以新增一條禁止規則就會自動生效。
create or replace function public.screening_forbidden_fields()
returns text[] language sql stable set search_path = public, pg_temp as $$
  select coalesce(array_agg(distinct f), '{}'::text[])
    from public.screening_rules r,
         lateral jsonb_array_elements_text(coalesce(r.cond->'prohibits', '[]'::jsonb)) f
   where r.outcome = 'never' and r.enabled;
$$;

create or replace function public.screening_rule_unsafe_reason(
  p_cond jsonb, p_escalate jsonb, p_requires text[]
) returns text language plpgsql stable set search_path = public, pg_temp as $$
declare s text; fields text[]; pat text;
begin
  s := coalesce(p_cond::text,'') || coalesce(p_escalate::text,'') ||
       coalesce(array_to_string(p_requires, ','), '');
  fields := public.screening_forbidden_fields();
  if array_length(fields, 1) is not null then
    pat := '\.(' || array_to_string(fields, '|') || ')\y';
    if s ~ pat then
      return '引用了不得產生燈號的欄位（' || array_to_string(fields, '、') || '）';
    end if;
  end if;
  -- R052：年齡差本身不得產生燈號。只檢查「同時引用雙方年齡」，
  -- 因為「本人年齡 vs 對方公開的年齡條件」是使用者自己設的 Dealbreaker，允許。
  if s like '%applicant.age_num%' and s like '%recipient.age_num%' then
    return '把雙方年齡直接相比（R052：年齡差本身不得產生燈號）';
  end if;
  return null;
end $$;

create or replace function public.screening_rules_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare why text;
begin
  if new.outcome <> 'never' and new.enabled then
    why := public.screening_rule_unsafe_reason(new.cond, new.escalate, new.requires);
    if why is not null then
      raise exception '初診規則 % 違反禁止規則：%', new.code, why;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists screening_rules_guard on public.screening_rules;
create trigger screening_rules_guard before insert or update on public.screening_rules
  for each row execute function public.screening_rules_guard();

-- run_screening() 每次執行前也再掃一次整張表——萬一有人把 trigger 停掉，
-- 引擎寧可整個不跑，也不要跑出一份用學歷或收入評分的報告。
create or replace function public.screening_assert_safe() returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare bad_code text; bad_why text;
begin
  select r.code, public.screening_rule_unsafe_reason(r.cond, r.escalate, r.requires)
    into bad_code, bad_why
    from public.screening_rules r
   where r.enabled and r.outcome <> 'never'
     and public.screening_rule_unsafe_reason(r.cond, r.escalate, r.requires) is not null
   limit 1;
  if bad_code is not null then
    raise exception '初診規則庫含有違反禁止規則的條目（% ：%），拒絕執行初診。', bad_code, bad_why;
  end if;
end $$;

-- 13.5 受評估對象：只暴露規則可以讀的欄位 ---------------------
-- 這是禁止規則的第二道防線。學歷、收入、身高、體重、MBTI、健康告知內容
-- 根本不會出現在這個 jsonb 裡，就算有人寫了引用它們的規則也只會拿到 null。
create or replace function public.screening_subject(p_uid uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'kind',              nullif(p.kind, ''),
    'age_num',           nullif(regexp_replace(coalesce(p.age,''), '[^0-9].*$', ''), '')::int,
    'weekly_work_hours', p.weekly_work_hours,
    'kids_plan',         nullif(p.kids_plan, ''),
    'has_kids',          nullif(p.has_kids, ''),
    'marital',           nullif(p.marital, ''),
    'living',            nullif(p.living, ''),
    'debt',              nullif(p.debt, ''),
    'debt_when',         nullif(p.debt_when, ''),
    'relationship_goal', nullif(p.relationship_goal, ''),
    'req_kids',          nullif(p.req_kids, ''),
    'req_marital',       nullif(p.req_marital, ''),
    'req_age_min',       nullif(regexp_replace(coalesce(p.req_age_min,''), '[^0-9].*$', ''), '')::int,
    'req_age_max',       nullif(regexp_replace(coalesce(p.req_age_max,''), '[^0-9].*$', ''), '')::int,
    -- 健康告知：只給「有沒有」與「本人選的揭露時機」，永遠不給內容（R053/R054）
    'has_health_note',   (coalesce(p.health,'') <> ''
                          or jsonb_array_length(coalesce(p.health_tags,'[]'::jsonb)) > 0),
    'health_when',       nullif(p.health_when, ''),
    'stars_indep',       nullif(p.stars->>'indep','')::int,
    -- 第 17 節的四個新題組。這裡是白名單：沒列進來的欄位規則引擎就讀不到，
    -- 所以學歷、收入、身高、體重、MBTI、健康告知內容永遠不會出現在這裡。
    'chronotype',             nullif(p.chronotype, ''),
    'contact_frequency',      nullif(p.contact_frequency, ''),
    'daily_together_need',    nullif(p.daily_together_need, ''),
    'alone_time_need',        nullif(p.alone_time_need, ''),
    'conflict_style',         nullif(p.conflict_style, ''),
    'relocation',             nullif(p.relocation, ''),
    'long_distance_ok',       nullif(p.long_distance_ok, ''),
    'cohabit_with_parents',   nullif(p.cohabit_with_parents, ''),
    'family_visit_freq',      nullif(p.family_visit_freq, ''),
    'parents_in_decisions',   nullif(p.parents_in_decisions, ''),
    'marriage_intent',        nullif(p.marriage_intent, ''),
    'relationship_structure', nullif(p.relationship_structure, ''),
    'finance_style',          nullif(p.finance_style, ''),
    'has_pets',               nullif(p.has_pets, ''),
    'pet_acceptance',         nullif(p.pet_acceptance, ''),
    'req_living',             nullif(p.req_living, ''),
    'req_family_involvement', nullif(p.req_family_involvement, ''),
    'req_partner_debt',       nullif(p.req_partner_debt, ''),
    'partner_alone_time_acceptance', nullif(p.partner_alone_time_acceptance, ''),
    'housework_model',               nullif(p.housework_model, ''),
    'cleanliness_conflict_style',    nullif(p.cleanliness_conflict_style, ''),
    'conflict_pause_preference',     nullif(p.conflict_pause_preference, ''),
    'conflict_return_commitment',    nullif(p.conflict_return_commitment, ''),
    'area',                   nullif(p.area, ''),
    'dealbreakers',      coalesce(p.dealbreakers, '{}'::jsonb)
  )
  /* 一樣是 jsonb_build_object 100 個參數的上限，拆成第二組串起來。
     第 23 節：居家社交／家務公平／宗教界線／前任與異性界線。
     白名單漏一個的後果跟遮罩黑名單漏一個相反，但一樣安靜——
     規則讀到的永遠是 null，那條規則從此不會命中，畫面上完全看不出來。
     tests/pgtest-topics.sql 會逐欄確認這裡讀得到。 */
  || jsonb_build_object(
    'housework_fairness',            nullif(p.housework_fairness, ''),
    'home_social_frequency',         nullif(p.home_social_frequency, ''),
    'home_guest_boundary',           nullif(p.home_guest_boundary, ''),
    'religion_importance',           nullif(p.religion_importance, ''),
    'religion_partner_expectation',  nullif(p.religion_partner_expectation, ''),
    'religion_child_plan',           nullif(p.religion_child_plan, ''),
    'ex_contact_acceptance',         nullif(p.ex_contact_acceptance, ''),
    'opposite_friend_boundary',      nullif(p.opposite_friend_boundary, ''),
    -- 空陣列當作「還沒填」，不是「一項都不需要討論」——
    -- 兩者在 R044C 裡是完全不同的意思。
    'relationship_boundary_actions',
      case when jsonb_array_length(coalesce(p.relationship_boundary_actions,'[]'::jsonb)) = 0
           then null else p.relationship_boundary_actions end
  )
  from public.match_profiles p where p.id = p_uid;
$$;

-- 13.6 條件式直譯器 -------------------------------------------
create or replace function public.screening_ref(
  p_ref text, p_a jsonb, p_b jsonb, p_ans jsonb
) returns jsonb language plpgsql immutable set search_path = public, pg_temp as $$
declare parts text[]; cur jsonb; i int;
begin
  if p_ref is null or p_ref = '' then return null; end if;
  parts := string_to_array(p_ref, '.');
  if    parts[1] = 'applicant' then cur := p_a;
  elsif parts[1] = 'recipient' then cur := p_b;
  elsif parts[1] = 'answers'   then cur := p_ans;
  else  return null; end if;
  for i in 2 .. coalesce(array_length(parts, 1), 1) loop
    if cur is null then return null; end if;
    cur := cur -> parts[i];
  end loop;
  if cur is null or cur = 'null'::jsonb then return null; end if;
  return cur;
end $$;

create or replace function public.screening_eval(
  p_cond jsonb, p_a jsonb, p_b jsonb, p_ans jsonb
) returns boolean language plpgsql immutable set search_path = public, pg_temp as $$
declare item jsonb; v jsonb; w jsonb; op text; val jsonb; num numeric;
begin
  if p_cond is null or p_cond = '{}'::jsonb then return true; end if;

  if p_cond ? 'all' then
    for item in select * from jsonb_array_elements(p_cond->'all') loop
      if not public.screening_eval(item, p_a, p_b, p_ans) then return false; end if;
    end loop;
    return true;
  end if;
  if p_cond ? 'any' then
    for item in select * from jsonb_array_elements(p_cond->'any') loop
      if public.screening_eval(item, p_a, p_b, p_ans) then return true; end if;
    end loop;
    return false;
  end if;
  if p_cond ? 'not' then
    return not public.screening_eval(p_cond->'not', p_a, p_b, p_ans);
  end if;
  if not (p_cond ? 'field') then return false; end if;

  v   := public.screening_ref(p_cond->>'field', p_a, p_b, p_ans);
  op  := coalesce(p_cond->>'op', 'eq');
  -- value 是字面值；value_ref 則是「跟另一個欄位比」（例如年齡對上對方公開的年齡條件）。
  -- 參照不到就當作不成立，不會因為對方沒設條件就亂亮燈。
  if p_cond ? 'value_ref' then
    val := public.screening_ref(p_cond->>'value_ref', p_a, p_b, p_ans);
    if val is null then return false; end if;
  else
    val := p_cond->'value';
  end if;

  if op = 'is_null'  then return v is null; end if;
  if op = 'not_null' then return v is not null; end if;
  -- 除了 is_null 之外，沒有值一律當作「不成立」，
  -- 不會把「沒填」誤讀成「填了否定的值」。
  if v is null then return false; end if;

  if op = 'eq'  then return v = val; end if;
  if op = 'ne'  then return v <> val; end if;
  if op = 'in'  then
    return exists (select 1 from jsonb_array_elements(coalesce(val,'[]'::jsonb)) e where e = v);
  end if;
  if op = 'not_in' then
    return not exists (select 1 from jsonb_array_elements(coalesce(val,'[]'::jsonb)) e where e = v);
  end if;
  if op = 'contains' then
    if jsonb_typeof(v) <> 'array' then return false; end if;
    if jsonb_typeof(val) = 'array' then return v @> val; end if;
    return v @> jsonb_build_array(val);
  end if;
  if op in ('same','differs') then
    w := public.screening_ref(p_cond->>'value', p_a, p_b, p_ans);
    if w is null then return false; end if;
    if op = 'same' then return v = w; else return v <> w; end if;
  end if;
  -- 兩份清單的「對稱差集」有幾項。複選的界線題用這個：
  -- 比的是兩個人對「哪些行為需要先講一聲」的認知差多少，
  -- 不是誰勾得多——勾得多不代表比較保守，勾得少也不代表比較隨便。
  -- value 是另一個 ref（跟 same/differs 一樣），n 是門檻。
  if op = 'diff_count_gte' then
    w := public.screening_ref(p_cond->>'value', p_a, p_b, p_ans);
    if w is null then return false; end if;
    if jsonb_typeof(v) <> 'array' or jsonb_typeof(w) <> 'array' then return false; end if;
    -- 兩邊都空白代表兩個人都還沒想過，不是「完全一致」，交給 requires 之外的規則處理
    if jsonb_array_length(v) = 0 and jsonb_array_length(w) = 0 then return false; end if;
    return (
      select count(*) from (
        (select e from jsonb_array_elements(v) e
          except select e from jsonb_array_elements(w) e)
        union all
        (select e from jsonb_array_elements(w) e
          except select e from jsonb_array_elements(v) e)
      ) d
    ) >= coalesce((p_cond->>'n')::int, 1);
  end if;

  -- 數值比較
  if jsonb_typeof(v) not in ('number','string') then return false; end if;
  begin
    num := (v #>> '{}')::numeric;
  exception when others then
    return false;
  end;
  if op = 'between' then
    return num >= (val->>0)::numeric and num <= (val->>1)::numeric;
  end if;
  if op = 'gt'  then return num >  (val #>> '{}')::numeric; end if;
  if op = 'gte' then return num >= (val #>> '{}')::numeric; end if;
  if op = 'lt'  then return num <  (val #>> '{}')::numeric; end if;
  if op = 'lte' then return num <= (val #>> '{}')::numeric; end if;
  return false;
end $$;

-- 把「揭露層級跟著欄位走」的設定換算成階段（R055：本人自選的說明時機）
create or replace function public.screening_min_stage(
  p_rule public.screening_rules, p_a jsonb, p_b jsonb
) returns int language plpgsql immutable set search_path = public, pg_temp as $$
declare v jsonb; s text;
begin
  if p_rule.min_stage_ref is null then return p_rule.min_stage; end if;
  v := public.screening_ref(p_rule.min_stage_ref, p_a, p_b, '{}'::jsonb);
  if v is null then return 99; end if;
  s := v #>> '{}';
  if s = 'public' then return 0; end if;
  if s = 'stage1' then return 1; end if;
  if s = 'stage2' then return 2; end if;
  return 99;   -- never：永遠不顯示
end $$;

-- 燈號的嚴重度順序：紅 > 黃 > 白 > 綠。數字小的比較嚴重。
create or replace function public.screening_severity(p_outcome text)
returns int language sql immutable as $$
  select case p_outcome
    when 'safety'  then 0
    when 'red'     then 1
    when 'yellow'  then 2
    when 'unknown' then 3
    else 4 end;
$$;

-- 13.7 執行初診 ------------------------------------------------
create or replace function public.run_screening(
  p_from uuid, p_to uuid, p_app uuid default null, p_audience text default 'member'
) returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare
  a jsonb; b jsonb; r public.screening_rules%rowtype;
  ref text; miss boolean; outc text; ms int;
  findings jsonb := '[]'::jsonb; hits jsonb := '[]'::jsonb;
  unknown_topics text[] := '{}'; miss_topics text[] := '{}';
  n_green int := 0; n_yellow int := 0; n_red int := 0; n_safety int := 0;
  seen int := 0; rid bigint;
begin
  perform public.screening_assert_safe();
  a := public.screening_subject(p_from);
  b := public.screening_subject(p_to);
  if a is null or b is null then
    raise exception '找不到病歷卡，無法初診';
  end if;

  -- 「目前取得 N 項有效資料」：兩邊加起來有填的欄位數（不含 kind 與 dealbreakers）
  select count(*) into seen from (
    select key, value from jsonb_each(a)
    union all
    select key, value from jsonb_each(b)
  ) t where t.value is not null and t.value <> 'null'::jsonb
      and t.key not in ('kind','dealbreakers');

  for r in
    select * from public.screening_rules
     where enabled and outcome <> 'never' and audience = p_audience
     order by priority, code
  loop
    -- requires 缺任何一個欄位就整條跳過，並把這個題組記為「資料不足」
    miss := false;
    foreach ref in array r.requires loop
      if public.screening_ref(ref, a, b, '{}'::jsonb) is null then miss := true; exit; end if;
    end loop;
    if miss then
      if not (r.topic = any(miss_topics)) then miss_topics := miss_topics || r.topic; end if;
      continue;
    end if;

    if not public.screening_eval(r.cond, a, b, '{}'::jsonb) then continue; end if;

    outc := r.outcome;
    -- 「🟡／🔴 依重要性設定」：對方把這個題組標成不可妥協才升級成紅燈
    if outc = 'yellow' and r.escalate is not null
       and public.screening_eval(r.escalate, a, b, '{}'::jsonb) then
      outc := 'red';
    end if;

    ms := public.screening_min_stage(r, a, b);
    hits := hits || jsonb_build_array(jsonb_build_object(
      'code', r.code, 'topic', r.topic, 'category', r.category, 'outcome', outc,
      'min_stage', ms, 'priority', r.priority, 'reason_code', r.reason_code,
      'title', r.title, 'body', r.body, 'ask', r.ask
    ));
  end loop;

  -- 一個題組只留一條：先取最嚴重的那一層，同樣嚴重時留 priority 最小的
  -- （數字小＝比較具體的那一條，例如第二階段的結構化規則會蓋過簡易版）。
  -- 例：關係期待同時命中 R007（🔴）與 R006（🟡），或 S2-01 與 R031 同時命中時，
  -- 一起顯示等於把同一件事講兩次，也會讓「🟡 N 項」失去意義。
  select coalesce(jsonb_agg(h order by (h->>'priority')::int, h->>'code'), '[]'::jsonb)
    into findings
    from (
      select distinct on (k->>'topic') k as h
        from jsonb_array_elements(hits) k
       order by k->>'topic',
                public.screening_severity(k->>'outcome'),
                (k->>'priority')::int,
                k->>'code'
    ) t;

  select
    count(*) filter (where f->>'outcome' = 'green'),
    count(*) filter (where f->>'outcome' = 'yellow'),
    count(*) filter (where f->>'outcome' = 'red'),
    count(*) filter (where f->>'outcome' = 'safety')
    into n_green, n_yellow, n_red, n_safety
    from jsonb_array_elements(findings) f;

  -- ⚪ 是以「題組」計數，不是以規則計數：
  -- 一個題組有東西沒填，就算一項資料不足，不管底下有幾條規則跳過。
  -- 但如果那個題組最後有別的燈亮著，就不算資料不足了。
  select array(
    select distinct t from (
      select f->>'topic' as t from jsonb_array_elements(findings) f where f->>'outcome' = 'unknown'
      union
      select m from unnest(miss_topics) m
       where not exists (select 1 from jsonb_array_elements(findings) f
                          where f->>'topic' = m and f->>'outcome' <> 'unknown')
    ) u where t is not null
  ) into unknown_topics;

  -- 有申請關係時，初診也留一筆時間軸（CRM 上會看到「主治醫師初診：2 黃燈」）。
  -- plpgsql 的函式本體是執行當下才解析，所以這裡可以呼叫第 14 節才定義的函式。
  if p_app is not null then
    perform public.log_application_event(p_app, 'screened', null,
      jsonb_build_object('green', n_green, 'yellow', n_yellow, 'red', n_red), 'recipient');
  end if;

  insert into public.screening_results
    (app_id, from_user, to_user, audience, ran_at, inputs_seen,
     green, yellow, red, unknown, safety, findings)
  values
    (p_app, p_from, p_to, p_audience, clock_timestamp(), seen,
     n_green, n_yellow, n_red, coalesce(array_length(unknown_topics,1),0), n_safety, findings)
  on conflict (from_user, to_user, audience) do update
    set app_id = excluded.app_id, ran_at = excluded.ran_at, inputs_seen = excluded.inputs_seen,
        green = excluded.green, yellow = excluded.yellow, red = excluded.red,
        unknown = excluded.unknown, safety = excluded.safety, findings = excluded.findings
  returning id into rid;
  return rid;
end $$;

-- 13.8 給會員看的初診結果 --------------------------------------
-- 數量永遠看得到；細節只給 min_stage <= 目前揭露層級的那些。
-- 這樣佈告欄（第 0 層）看得到「🔴 1 項」，但不會知道那一項是生育規劃——
-- 第 0 層連精確年齡都看不到，初診不能變成繞過遮罩的後門。
create or replace function public.get_screening_for(p_other uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  me uuid := auth.uid(); rel int := 0; res public.screening_results%rowtype;
  newest timestamptz; shown jsonb := '[]'::jsonb; item jsonb; hidden int := 0;
  rel_app uuid;
begin
  if me is null then raise exception '請先登入'; end if;
  if p_other = me then raise exception '不能對自己做初診'; end if;
  if not exists (select 1 from public.get_visible_match_profiles(p_other)) then
    raise exception '找不到這個人';
  end if;

  select coalesce(max(a.stage), 0) into rel
    from public.applications a
   where (a.from_user = me and a.to_user = p_other)
      or (a.to_user = me and a.from_user = p_other);

  select a.id into rel_app from public.applications a
   where a.from_user = p_other and a.to_user = me
   order by a.updated_at desc limit 1;

  select greatest(max(p.updated_at), max(r.updated_at)) into newest
    from public.match_profiles p, public.screening_rules r
   where p.id in (me, p_other);

  select * into res from public.screening_results s
   where s.from_user = p_other and s.to_user = me and s.audience = 'member'
     and s.ran_at >= newest;
  if not found then
    perform public.run_screening(p_other, me, rel_app);
    select * into res from public.screening_results s
     where s.from_user = p_other and s.to_user = me and s.audience = 'member';
  end if;

  for item in select * from jsonb_array_elements(res.findings) loop
    if coalesce((item->>'min_stage')::int, 99) <= rel then
      shown := shown || jsonb_build_array(item);
    else
      hidden := hidden + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'stage', rel, 'inputs_seen', res.inputs_seen,
    'green', res.green, 'yellow', res.yellow, 'red', res.red, 'unknown', res.unknown,
    'findings', shown, 'hidden', hidden, 'ran_at', res.ran_at
  );
end $$;

-- 13.9 權限 ----------------------------------------------------
-- 規則表所有人都讀得到（文案要顯示在畫面上），只有管理員能改。
alter table public.screening_rules  enable row level security;
alter table public.screening_results enable row level security;

drop policy if exists "screening_rules_select_all" on public.screening_rules;
create policy "screening_rules_select_all" on public.screening_rules for select
  to authenticated using (true);
drop policy if exists "screening_rules_write_admin" on public.screening_rules;
create policy "screening_rules_write_admin" on public.screening_rules for all
  to authenticated using (public.match_is_admin(auth.uid())) with check (public.match_is_admin(auth.uid()));

-- 結果表一律不開放給前端直接查，只能走 get_screening_for()——
-- 直接查得到就等於可以繞過 min_stage 的分層。
drop policy if exists "screening_results_no_client_access" on public.screening_results;
create policy "screening_results_no_client_access" on public.screening_results for all
  to anon, authenticated using (false) with check (false);

-- 規則庫的文案要顯示在畫面上，所以開放 select（RLS 已經限制只有管理員能寫）。
-- screening_results 刻意「不」開放：直接查得到就等於可以繞過 min_stage 的分層，
-- 唯一的讀取路徑是 get_screening_for()。
grant select on table public.screening_rules to authenticated;

revoke all on function public.run_screening(uuid,uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.run_screening(uuid,uuid,uuid,text) to postgres, service_role;
revoke all on function public.get_screening_for(uuid) from public, anon;
grant execute on function public.get_screening_for(uuid) to authenticated;
revoke all on function public.screening_subject(uuid) from public, anon, authenticated;
grant execute on function public.screening_subject(uuid) to postgres, service_role;

-- 13.10 規則庫 V1 種子資料 -------------------------------------
-- 先塞禁止規則，因為 screening_rules_guard 會拿它們去檢查後面的規則。
insert into public.screening_rules (code, topic, category, outcome, priority, cond, title, body) values
  ('R047','mbti',      'prohibition','never',99,'{"prohibits":["mbti"]}'::jsonb,
   'MBTI 不產生黃燈','人格分類不是風險指標，也不該拿來評估兩個人合不合適。'),
  ('R048','height',    'prohibition','never',99,'{"prohibits":["height_cm"]}'::jsonb,
   '身高差異不產生黃燈',''),
  ('R049','weight',    'prohibition','never',99,'{"prohibits":["weight_kg"]}'::jsonb,
   '體重／BMI 不產生黃燈',''),
  ('R050','education', 'prohibition','never',99,'{"prohibits":["education"]}'::jsonb,
   '學歷差距不產生黃燈',''),
  ('R051','income',    'prohibition','never',99,'{"prohibits":["income"]}'::jsonb,
   '收入高低本身不產生黃燈','否則系統會變成階級評分。'),
  ('R052','age',       'prohibition','never',99,'{"prohibits":[],"prohibits_pair":["applicant.age_num","recipient.age_num"]}'::jsonb,
   '年齡差本身不產生黃燈','只有超出使用者本人設定的年齡條件才處理。'),
  ('R053','health',    'prohibition','never',99,'{"prohibits":["health","health_tags"]}'::jsonb,
   '疾病不得自動亮黃燈','氣喘、糖尿病、精神疾病、身心障礙、慢性疾病等一律不得自動產生燈號。'),
  ('R054','health',    'prohibition','never',99,'{"prohibits":["health","health_tags"]}'::jsonb,
   '健康資料不得降低匹配度','')
on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, cond = excluded.cond,
  title = excluded.title, body = excluded.body;

-- A. 工時（R001–R005）：一個 weekly_work_hours 欄位換五條規則
insert into public.screening_rules
  (code, topic, category, outcome, priority, min_stage, cond, requires, reason_code, title, body, ask) values
  ('R001','work_hours','workload','unknown',60,2,
   '{"field":"applicant.weekly_work_hours","op":"is_null"}'::jsonb, '{}',
   'R_WORK_HOURS_UNKNOWN','尚未提供工作時間',
   '目前無法評估對方平日可以安排的生活與相處時間。','[]'::jsonb),

  ('R002','work_hours','workload','yellow',30,2,
   '{"field":"applicant.weekly_work_hours","op":"between","value":[60,79]}'::jsonb,
   '{applicant.weekly_work_hours}',
   'R_WORK_HOURS_HIGH','工作時間較長',
   '平日可安排的相處與休息時間可能較有限。',
   '["工作較忙的時期，你通常怎麼安排自己的休息與伴侶相處時間？"]'::jsonb),

  ('R003','work_hours','workload','yellow',25,2,
   '{"field":"applicant.weekly_work_hours","op":"between","value":[80,99]}'::jsonb,
   '{applicant.weekly_work_hours}',
   'R_WORK_HOURS_VERY_HIGH','工作負荷偏高',
   '建議進一步了解這是長期的工作型態，還是階段性的忙碌。',
   '["這樣的工作時數是長期常態，還是最近特別忙？"]'::jsonb),

  ('R004','work_hours','workload','yellow',10,2,
   '{"field":"applicant.weekly_work_hours","op":"between","value":[100,168]}'::jsonb,
   '{applicant.weekly_work_hours}',
   'R_WORK_HOURS_EXTREME','填寫的工作時間非常高',
   '建議先確認這個數字是否包含待命、通勤、研究或準備時間，或者只是特殊期間。',
   '["這個工作時數是平時常態，還是近期特殊狀況？","裡面有包含待命或通勤的時間嗎？"]'::jsonb),

  ('R005','work_hours','data_quality','unknown',15,2,
   '{"field":"applicant.weekly_work_hours","op":"gt","value":168}'::jsonb,
   '{applicant.weekly_work_hours}',
   'R_WORK_HOURS_INVALID','工作時數資料可能有誤',
   '一週總時數超過 168 小時（一週的總時數上限），請確認資料是否填寫正確。','[]'::jsonb),

-- D. 生育規劃（R010、R011）
  ('R010','kids_plan','life_plan','yellow',20,2,
   '{"any":[
      {"all":[{"field":"applicant.kids_plan","op":"eq","value":"想要小孩"},
              {"field":"recipient.kids_plan","op":"eq","value":"不確定，需要再溝通"}]},
      {"all":[{"field":"applicant.kids_plan","op":"eq","value":"不確定，需要再溝通"},
              {"field":"recipient.kids_plan","op":"eq","value":"想要小孩"}]}
    ]}'::jsonb,
   '{applicant.kids_plan,recipient.kids_plan}',
   'R_KIDS_PLAN_UNSURE','一方想要小孩，另一方還不確定',
   '這不代表不適合，但值得在關係深入之前先聊過。',
   '["你目前對生小孩這件事，最在意或最猶豫的是什麼？"]'::jsonb),

  ('R011','kids_plan','life_plan','yellow',20,2,
   '{"any":[
      {"all":[{"field":"applicant.kids_plan","op":"in","value":["不想要小孩","已有小孩，不打算再生"]},
              {"field":"recipient.kids_plan","op":"eq","value":"不確定，需要再溝通"}]},
      {"all":[{"field":"applicant.kids_plan","op":"eq","value":"不確定，需要再溝通"},
              {"field":"recipient.kids_plan","op":"in","value":["不想要小孩","已有小孩，不打算再生"]}]}
    ]}'::jsonb,
   '{applicant.kids_plan,recipient.kids_plan}',
   'R_KIDS_PLAN_UNSURE','一方不打算生小孩，另一方還不確定',
   '這不代表不適合，但值得在關係深入之前先聊過。',
   '["如果最後決定不生小孩，你會希望兩個人的生活長什麼樣子？"]'::jsonb),

-- E. 已有孩子（R013、R014）——目前唯一一條完整可做的 🔴
  ('R013','has_kids','family','unknown',40,1,
   '{"all":[{"field":"applicant.has_kids","op":"in","value":["有，同住","有，未同住"]},
            {"field":"recipient.req_kids","op":"is_null"}]}'::jsonb,
   '{applicant.has_kids}',
   'R_KIDS_ACCEPT_UNKNOWN','對方已有孩子，你還沒填孩子條件',
   '建議先確認自己對「伴侶已有孩子」的接受程度，再決定要不要往下走。','[]'::jsonb),

  ('R014','has_kids','family','red',5,1,
   '{"all":[{"field":"applicant.has_kids","op":"in","value":["有，同住","有，未同住"]},
            {"field":"recipient.req_kids","op":"eq","value":"需沒有小孩"}]}'::jsonb,
   '{applicant.has_kids,recipient.req_kids}',
   'H_CHILD_EXISTING','對方已有孩子，但你設定的條件是「需沒有小孩」',
   '這是你自己設定的條件，系統只是把它指出來。如果你的想法改變了，可以到「我的登記」修改。','[]'::jsonb),

-- 年齡：R052 允許的唯一一種用法——本人是否符合對方「公開」的年齡條件。
-- 這裡刻意只做這個方向：對方的年齡條件本來就公開，你自己的年齡你也知道，所以不洩漏任何東西。
  ('R052A','age_pref','preference','yellow',35,0,
   '{"any":[{"field":"recipient.age_num","op":"lt","value":0},
            {"field":"recipient.age_num","op":"gt","value":0}]}'::jsonb,
   '{recipient.age_num}',
   'R_AGE_OUT_OF_RANGE','你不在對方公開的年齡條件內',
   '對方在登記表上寫了希望的年齡範圍，而你目前不在裡面。這不影響你提出邀請，只是先讓你知道。','[]'::jsonb),

-- U. 健康資料（R055）：只說「有一項本人想在適當階段說明的事」，永遠不說是什麼。
--    min_stage_ref 讓它跟著本人自選的揭露時機走——在那之前連「有這件事」都不會透露。
  ('R055','health_note','self_disclosure','unknown',50,2,
   '{"all":[{"field":"applicant.has_health_note","op":"eq","value":true},
            {"field":"applicant.health_when","op":"in","value":["public","stage1","stage2"]}]}'::jsonb,
   '{applicant.has_health_note,applicant.health_when}',
   'R_SELF_DISCLOSURE','有一項本人希望在適當階段主動說明的重要生活資訊',
   '這是對方自己選擇要說明的，不是系統判定的問題。請等他說，不需要追問。','[]'::jsonb),

-- 🟢 條目：讓報告不會只剩黃燈與問號
  ('G001','kids_plan','life_plan','green',70,2,
   '{"all":[{"field":"applicant.kids_plan","op":"same","value":"recipient.kids_plan"},
            {"field":"applicant.kids_plan","op":"not_in","value":["其他","不確定，需要再溝通"]}]}'::jsonb,
   '{applicant.kids_plan,recipient.kids_plan}',
   null,'生育規劃一致','兩邊在這件事上的答案相同。','[]'::jsonb),

  ('G002','has_kids','family','green',70,1,
   '{"any":[
      {"all":[{"field":"recipient.req_kids","op":"eq","value":"需沒有小孩"},
              {"field":"applicant.has_kids","op":"eq","value":"沒有"}]},
      {"all":[{"field":"recipient.req_kids","op":"eq","value":"可接受已有小孩"},
              {"field":"applicant.has_kids","op":"in","value":["有，同住","有，未同住"]}]}
    ]}'::jsonb,
   '{applicant.has_kids,recipient.req_kids}',
   null,'孩子的條件相符','對方的狀況符合你設定的孩子條件。','[]'::jsonb)
on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, min_stage = excluded.min_stage, cond = excluded.cond,
  requires = excluded.requires, reason_code = excluded.reason_code,
  title = excluded.title, body = excluded.body, ask = excluded.ask;

-- R052A 的條件式沒辦法在 insert 裡直接引用另一個欄位當界線，這裡補成正確的比較。
update public.screening_rules set cond = '{"any":[
    {"field":"recipient.age_num","op":"lt","value_ref":"applicant.req_age_min"},
    {"field":"recipient.age_num","op":"gt","value_ref":"applicant.req_age_max"}
  ]}'::jsonb where code = 'R052A';

-- R055 的揭露時機跟著本人自選的 health_when 走
update public.screening_rules set min_stage_ref = 'applicant.health_when' where code = 'R055';

-- ============================================================
-- 14) 申請者 CRM：病例時間軸與看板欄位
--
--     規格見 docs/screening-crm-spec.md 第 4 節，這一節實作第 3 步。
--
--     跟規格的一處出入：規格說「由既有的 RPC 在成功之後寫入」，實作改成
--     **資料庫 trigger**。原因是婉拒根本不走 RPC——它是前端直接對
--     applications 下 update（RLS 只開放給收件方）。靠 RPC 補寫會漏掉
--     整條婉拒路徑，而婉拒正是漏斗上最需要記錄的一步。trigger 也擋得住
--     「有人繞過前端直接改資料」的情況，稽核價值才成立。
-- ============================================================

-- 14.1 applications 補四個欄位 --------------------------------
alter table public.applications add column if not exists opened_at        timestamptz;
alter table public.applications add column if not exists last_activity_at timestamptz;
alter table public.applications add column if not exists closed_reason    text;
alter table public.applications add column if not exists crm_tags         jsonb not null default '[]'::jsonb;

-- 既有資料先用 updated_at 當作最後活動時間，逾期統計才不會一開始全部歸零
update public.applications
   set last_activity_at = coalesce(updated_at, created_at)
 where last_activity_at is null;

-- opened_at 與 closed_reason 交給函式與 trigger 寫，前端不能自己填：
-- 前者是「志工什麼時候真的打開這封申請」，後者是漏斗統計的依據，
-- 讓收件方隨手填會直接汙染資料。crm_tags 是收件方自己貼的標籤，不受限。
create or replace function public.guard_application_privileged()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.role() = 'authenticated'
     and coalesce(current_setting('app.bypass_app_guard', true), '') <> 'on'
     and not public.match_is_admin(auth.uid()) then
    new.from_user   := old.from_user;
    new.to_user     := old.to_user;
    new.stage       := old.stage;
    new.a1_unlocked := old.a1_unlocked;
    new.stage2_paid := old.stage2_paid;
    new.paid        := old.paid;
    new.refunded    := old.refunded;
    new.consent_at  := old.consent_at;
    new.unlock_from := old.unlock_from;
    new.unlock_to   := old.unlock_to;
    new.skipped     := old.skipped;
    new.fast_invite_from := old.fast_invite_from;
    new.fast_invite_to := old.fast_invite_to;
    new.priority_invite := old.priority_invite;
    new.priority_note := old.priority_note;
    new.opened_at     := old.opened_at;
    new.closed_reason := old.closed_reason;
  end if;
  return new;
end $$;

-- 14.2 病例時間軸 ---------------------------------------------
create table if not exists public.application_events (
  id         bigserial primary key,
  app_id     uuid not null references public.applications(id) on delete cascade,
  at         timestamptz not null default clock_timestamp(),
  actor      uuid references auth.users(id) on delete set null,   -- null = 系統
  kind       text not null,
  -- both      ：雙方都看得到（申請進度）
  -- recipient ：只有收件方（志工筆記、初診結果）
  -- admin     ：只有管理員（安全事件；被記錄的人不會知道）
  visibility text not null default 'both' check (visibility in ('both','recipient','admin')),
  detail     jsonb not null default '{}'::jsonb
);
create index if not exists application_events_app_at on public.application_events(app_id, at);

-- 唯一的寫入路徑。前端沒有 insert 權限，時間軸才有稽核價值。
create or replace function public.log_application_event(
  p_app uuid, p_kind text, p_actor uuid default null,
  p_detail jsonb default '{}'::jsonb, p_visibility text default 'both'
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_app is null then return; end if;
  insert into public.application_events(app_id, kind, actor, detail, visibility)
  values (p_app, p_kind, p_actor, coalesce(p_detail, '{}'::jsonb), p_visibility);
end $$;

-- 14.3 自動記錄 -----------------------------------------------
-- BEFORE：維護 last_activity_at 與 closed_reason。
-- 名字刻意排在 trg_guard_application 後面（trigger 依名稱順序執行），
-- 這樣 guard 先把前端亂填的 closed_reason revert 掉，再由這裡填上正確的值。
create or replace function public.applications_crm_before()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  -- INSERT 也要設：新申請如果 last_activity_at 是 null，
  -- 「逾期未處理」的查詢（last_activity_at < now() - 7 天）永遠不會命中它——
  -- 結果就是最該被看到的那種申請（送出後三週沒人理）反而不會出現在逾期格。
  new.last_activity_at := clock_timestamp();
  if TG_OP = 'INSERT' then return new; end if;
  if new.status = 'rejected' and old.status <> 'rejected' and new.closed_reason is null then
    -- 只存申請人本來就看得到的資訊（他知道自己走到第幾階段、也知道被婉拒了），
    -- 所以這一欄不需要另外遮。封鎖與安全事件「絕對不可以」寫進這裡——
    -- 那會讓被封鎖的人推論出是誰封鎖了他。那些一律走 visibility='admin' 的事件。
    new.closed_reason := case
      when auth.uid() = new.from_user then 'withdrawn_by_applicant'
      else 'declined_stage' || old.stage::text end;
  end if;
  return new;
end $$;
drop trigger if exists trg_z_applications_crm on public.applications;
create trigger trg_z_applications_crm before insert or update on public.applications
  for each row execute function public.applications_crm_before();

-- AFTER：把狀態變化轉成時間軸事件。用 trigger 而不是在九支 RPC 裡各寫一行，
-- 是因為婉拒走的是前端直接 update，RPC 補寫會整條漏掉。
create or replace function public.applications_crm_after()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare who uuid := auth.uid();
begin
  if TG_OP = 'INSERT' then
    perform public.log_application_event(new.id, 'applied', new.from_user,
      jsonb_build_object('paid', new.paid));
    return new;
  end if;

  if new.opened_at is not null and old.opened_at is null then
    perform public.log_application_event(new.id, 'opened', new.to_user);
  end if;
  if new.stage2_paid and not old.stage2_paid then
    perform public.log_application_event(new.id, 'sent_q2', new.to_user,
      jsonb_build_object('questions', jsonb_array_length(coalesce(new.a2_questions, '[]'::jsonb))));
  end if;
  if new.stage is distinct from old.stage then
    perform public.log_application_event(new.id, 'advanced_' || new.stage::text, who,
      jsonb_build_object('from', old.stage, 'to', new.stage));
  end if;
  if new.priority_invite and not old.priority_invite then
    perform public.log_application_event(new.id, 'priority_invite', new.from_user);
  end if;
  if new.unlock_from and not old.unlock_from then
    perform public.log_application_event(new.id, 'unlocked_from', new.from_user);
  end if;
  if new.unlock_to and not old.unlock_to then
    perform public.log_application_event(new.id, 'unlocked_to', new.to_user);
  end if;
  if (new.unlock_from and new.unlock_to) and not (old.unlock_from and old.unlock_to) then
    perform public.log_application_event(new.id, 'exchanged', null);
  end if;
  if new.refunded and not old.refunded then
    perform public.log_application_event(new.id, 'refunded', new.from_user,
      jsonb_build_object('credits', new.paid));
  end if;
  if new.status = 'rejected' and old.status <> 'rejected' then
    perform public.log_application_event(new.id, 'declined', who,
      jsonb_build_object('stage', old.stage, 'reason', new.closed_reason));
  end if;
  if new.vet_at is distinct from old.vet_at and new.vet_at is not null then
    perform public.log_application_event(new.id, 'ai_review', new.to_user, '{}'::jsonb, 'recipient');
  end if;
  return new;
end $$;
drop trigger if exists trg_z_applications_events on public.applications;
create trigger trg_z_applications_events after insert or update on public.applications
  for each row execute function public.applications_crm_after();

-- 作答：第一階段在建立申請時一起寫入，第二階段是後來補上的
create or replace function public.application_answers_crm_after()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if TG_OP = 'INSERT' then
    if new.a1 is not null then
      perform public.log_application_event(new.application_id, 'answered_1', null,
        jsonb_build_object('count', jsonb_array_length(coalesce(new.a1, '[]'::jsonb))));
    end if;
    return new;
  end if;
  if new.a2 is not null and old.a2 is null then
    perform public.log_application_event(new.application_id, 'answered_2', null,
      jsonb_build_object('count', jsonb_array_length(coalesce(new.a2, '[]'::jsonb))));
  end if;
  return new;
end $$;
drop trigger if exists trg_z_answers_events on public.application_answers;
create trigger trg_z_answers_events after insert or update on public.application_answers
  for each row execute function public.application_answers_crm_after();

-- 對話：訊息本身不進時間軸（會洗版），但要更新最後活動時間，
-- 免得雙方聊得正熱烈卻被算成「逾期未處理」。
create or replace function public.match_messages_touch_activity()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.applications
     set last_activity_at = clock_timestamp()
   where id = new.application_id;
  return new;
end $$;
drop trigger if exists trg_z_messages_activity on public.match_messages;
create trigger trg_z_messages_activity after insert on public.match_messages
  for each row execute function public.match_messages_touch_activity();

-- 14.4 收件方按下「打開」------------------------------------
-- 「新申請」與「第一階段待審」的差別就在這一欄：志工看過了沒。
-- 收一個陣列而不是單筆：收件匣一次會顯示很多封，一封打一次 RPC 在
-- 「124 封申請一個志工」的情境下就是 124 次往返。
create or replace function public.mark_applications_opened(p_app_ids uuid[])
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid(); n int;
begin
  if me is null then raise exception '請先登入'; end if;
  if p_app_ids is null or cardinality(p_app_ids) = 0 then return 0; end if;
  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications
     set opened_at = clock_timestamp()
   where id = any(p_app_ids) and to_user = me and opened_at is null;
  get diagnostics n = row_count;
  perform set_config('app.bypass_app_guard', '', true);
  return n;
end $$;

-- 14.5 權限 ---------------------------------------------------
alter table public.application_events enable row level security;

drop policy if exists "application_events_select" on public.application_events;
create policy "application_events_select" on public.application_events for select
  to authenticated using (
    public.match_is_admin(auth.uid())
    or exists (
      select 1 from public.applications a
       where a.id = application_events.app_id
         and (
           (application_events.visibility = 'both'
             and (a.from_user = auth.uid() or a.to_user = auth.uid()))
           or (application_events.visibility = 'recipient' and a.to_user = auth.uid())
         )
    )
  );

-- 沒有 insert／update／delete policy：時間軸只能由 SECURITY DEFINER 的
-- trigger 寫入，前端連補一筆假事件都做不到。
drop policy if exists "application_events_no_client_write" on public.application_events;
create policy "application_events_no_client_write" on public.application_events for insert
  to anon, authenticated with check (false);

-- RLS 只決定「哪些列」，GRANT 才決定「這個角色能不能碰這張表」。兩個都要給，
-- 少了 GRANT 會直接 permission denied，連自己的那幾列都讀不到。
grant select on table public.application_events to authenticated;

revoke all on function public.log_application_event(uuid,text,uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.log_application_event(uuid,text,uuid,jsonb,text) to postgres, service_role;
revoke all on function public.mark_applications_opened(uuid[]) from public, anon;
grant execute on function public.mark_applications_opened(uuid[]) to authenticated;

-- ============================================================
-- 15) 申請者 CRM：認養看板與《認養申請病例》
--
--     規格見 docs/screening-crm-spec.md 第 4 節與 Ⅴ，這一節實作第 4 步。
--
--     設計重點：整個看板只打「一次」RPC。
--     每位申請人的初診燈號存在 screening_results，而那張表是刻意不開放給
--     前端直接查的（直接查得到就等於繞過 min_stage 分層），所以如果讓前端
--     一封一封去問，124 封申請就是 124 次往返。get_crm_board() 一次把
--     整個收件匣連同燈號、未讀數、逾期天數全部算好帶回來，
--     九個分格與五個快篩則是前端拿這份資料自己算——那些純粹是分類，
--     不需要再問伺服器。
-- ============================================================

-- 15.1 罐頭回覆接上理由碼 --------------------------------------
-- 「黃燈 → reason_code → 推薦罐頭」是一個 array 交集查詢，不用 AI。
alter table public.template_master add column if not exists reason_codes text[] not null default '{}';
alter table public.template_master add column if not exists stage smallint;

insert into public.template_master (id, name, text, reason_codes, stage) values
  ('FOLLOWUP_WORK_HOURS', '工作與陪伴時間補件',
   E'謝謝你花時間填寫申請。我看到你填的工作時數比較長，想先了解一下：\n\n'
   '這是長期的工作型態，還是最近特別忙？裡面有包含待命或通勤的時間嗎？\n\n'
   '問這個不是要評價你的工作，只是想知道我們之後可以怎麼安排相處的時間。',
   array['R_WORK_HOURS_HIGH','R_WORK_HOURS_VERY_HIGH','R_WORK_HOURS_EXTREME'], 1),

  ('FOLLOWUP_WORK_HOURS_CHECK', '工作時數資料確認',
   E'謝謝你的申請。你填的一週工作時數看起來可能是筆誤（超過一週的總時數），\n'
   '方便的話再確認一下數字嗎？我想正確理解你的生活步調。',
   array['R_WORK_HOURS_INVALID'], 1),

  ('FOLLOWUP_KIDS', '孩子條件確認',
   E'謝謝你的申請。我還沒有在自己的登記表上填「孩子條件」這一欄，\n'
   '所以想先誠實說明我目前的想法，也想聽聽你的。',
   array['R_KIDS_ACCEPT_UNKNOWN'], 1),

  ('DECLINE_CORE_DIFF', '核心條件差異婉拒',
   E'謝謝你願意花時間寫這份申請，我很認真讀過了。\n\n'
   '我在登記表上寫的條件跟你目前的狀況有一項對不上，那是我沒有辦法改變想法的部分，\n'
   '所以這次就先到這裡。這不是你的問題，只是我們要的東西不一樣。\n\n'
   '祝你早點遇到合適的人。',
   array['H_CHILD_EXISTING'], 1),

  ('FOLLOWUP_SELF_DISCLOSURE', '對方想主動說明的事',
   E'謝謝你的申請。我看到你有一項希望在適當階段主動說明的事——\n'
   '你想什麼時候說都可以，我不會追問。',
   array['R_SELF_DISCLOSURE'], 2)
on conflict (id) do update set
  name = excluded.name, text = excluded.text,
  reason_codes = excluded.reason_codes, stage = excluded.stage;

-- 15.2 認養看板：一次把整個收件匣算好 --------------------------
create or replace function public.get_crm_board()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid(); rows jsonb;
begin
  if me is null then raise exception '請先登入'; end if;

  select coalesce(jsonb_agg(r order by r->>'last_activity_at' desc), '[]'::jsonb) into rows
  from (
    select jsonb_build_object(
      'app_id',        a.id,
      'from_user',     a.from_user,
      'name',          coalesce(nullif(p.name, ''), '（已取消登記）'),
      'species',       p.species,
      'kind',          p.kind,
      'area',          p.area,
      'stage',         a.stage,
      'status',        a.status,
      'opened_at',     a.opened_at,
      'created_at',    a.created_at,
      'last_activity_at', coalesce(a.last_activity_at, a.updated_at, a.created_at),
      'days_open',     greatest(0, extract(day from now() - a.created_at)::int),
      'idle_days',     greatest(0, extract(day from
                         now() - coalesce(a.last_activity_at, a.updated_at, a.created_at))::int),
      'priority_invite', a.priority_invite,
      'stage2_paid',   a.stage2_paid,
      'unlock_from',   a.unlock_from,
      'unlock_to',     a.unlock_to,
      'closed_reason', a.closed_reason,
      'crm_tags',      coalesce(a.crm_tags, '[]'::jsonb),
      'has_a1',        (ans.a1 is not null),
      'has_a2',        (ans.a2 is not null),
      'has_vet',       (a.vet is not null),
      'unread',        coalesce(nt.n, 0),
      -- 初診燈號：screening_results 前端查不到，所以在這裡一起帶回去。
      -- 這是「數量」，不是細節——細節仍然只能透過 get_screening_for() 拿，
      -- 而且依 min_stage 分層。
      'screened',      (sr.id is not null),
      'green',         coalesce(sr.green, 0),
      'yellow',        coalesce(sr.yellow, 0),
      'red',           coalesce(sr.red, 0),
      'unknown',       coalesce(sr.unknown, 0)
    ) as r
    from public.applications a
    left join public.match_profiles p on p.id = a.from_user
    left join public.application_answers ans on ans.application_id = a.id
    left join public.screening_results sr
           on sr.from_user = a.from_user and sr.to_user = me and sr.audience = 'member'
    left join lateral (
      select count(*) as n from public.match_notifications n
       where n.user_id = me and n.kind = 'message'
         and n.link_app_id = a.id and n.read_at is null
    ) nt on true
    where a.to_user = me
  ) t;

  return rows;
end $$;

-- 15.3 《認養申請病例》：點進一封時，把散在各處的東西一次收齊 ----
-- 七個區塊裡，③申請問卷、④對話、⑦時間軸前端本來就拿得到，
-- 這裡補的是前端拿不到或需要跨表組合的：初診細節、罐頭建議、
-- 自己送出過的檢舉與封鎖狀態、志工私人筆記。
create or replace function public.get_application_case(p_app_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  me uuid := auth.uid(); a public.applications%rowtype;
  scr jsonb; codes text[]; tpls jsonb; my_reports jsonb; blocked boolean; note text;
begin
  if me is null then raise exception '請先登入'; end if;
  select * into a from public.applications where id = p_app_id;
  if not found or a.to_user <> me then raise exception '找不到這筆申請'; end if;

  -- ② 初診結果（分層由 get_screening_for 自己處理）
  begin
    scr := public.get_screening_for(a.from_user);
  exception when others then
    scr := null;   -- 對方可能已經停用或封鎖了你，這一區塊就留白
  end;

  -- ⑤ 回覆建議：拿初診的理由碼去對罐頭，不用 AI
  select coalesce(array_agg(distinct f->>'reason_code'), '{}'::text[]) into codes
    from jsonb_array_elements(coalesce(scr->'findings', '[]'::jsonb)) f
   where f->>'reason_code' is not null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'name', t.name, 'text', t.text, 'reason_codes', t.reason_codes)), '[]'::jsonb)
    into tpls
    from public.template_master t
   where cardinality(codes) > 0 and t.reason_codes && codes;

  -- ⑥ 安全：只給「你自己」送出過的檢舉與封鎖狀態。
  -- 別人的檢舉不會出現在這裡——那是管理員的事，而且讓收件方看得到
  -- 等於洩漏其他會員的行為。
  select coalesce(jsonb_agg(jsonb_build_object(
           'why', r.why, 'done', r.done, 'created_at', r.created_at) order by r.created_at desc), '[]'::jsonb)
    into my_reports
    from public.reports r
   where r.by_id = me and r.target_id = a.from_user;

  select exists (select 1 from public.match_user_blocks b
                  where b.blocker_id = me and b.blocked_id = a.from_user) into blocked;

  select n.note into note from public.application_private_notes n
   where n.application_id = p_app_id and n.owner_id = me;

  return jsonb_build_object(
    'app_id', a.id,
    'screening', scr,
    'templates', tpls,
    'my_reports', my_reports,
    'blocked', blocked,
    'note', note
  );
end $$;

-- 15.4 志工私人筆記 -------------------------------------------
create or replace function public.save_case_note(p_app_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.applications where id = p_app_id and to_user = me) then
    raise exception '找不到這筆申請';
  end if;
  insert into public.application_private_notes(application_id, owner_id, note, updated_at)
  values (p_app_id, me, p_note, now())
  on conflict (application_id) do update
    set note = excluded.note, updated_at = now()
    where public.application_private_notes.owner_id = me;
  perform public.log_application_event(p_app_id, 'noted', me, '{}'::jsonb, 'recipient');
end $$;

-- 15.5 權限 ---------------------------------------------------
revoke all on function public.get_crm_board() from public, anon;
grant execute on function public.get_crm_board() to authenticated;
revoke all on function public.get_application_case(uuid) from public, anon;
grant execute on function public.get_application_case(uuid) to authenticated;
revoke all on function public.save_case_note(uuid,text) from public, anon;
grant execute on function public.save_case_note(uuid,text) to authenticated;

-- ============================================================
-- 16) 罐頭中心：理由碼對應改成管理後台可編輯
-- ============================================================

-- 16.1 補上一直漏掉的 GRANT ------------------------------------
-- template_master 從第 10 節建表以來只有 RLS policy、沒有任何 GRANT，
-- 所以 authenticated 連這張表都碰不到——「範本主檔管理」其實從來沒有運作過，
-- 而前端的 getTemplateMaster() 被 try/catch 包著，所以畫面只是靜靜地空白。
-- （這跟第 14 節 application_events 是同一個坑：RLS 決定「哪些列」，
--   GRANT 決定「能不能碰這張表」，兩個都要給。）
grant select on table public.template_master to authenticated;
grant insert, update, delete on table public.template_master to authenticated;

-- 16.2 理由碼要用「選的」，不能自由輸入 --------------------------
-- 打錯一個字，這封罐頭就永遠不會被推薦，而且畫面上完全看不出來。
-- 這支函式把規則庫裡真的存在的理由碼、以及每個理由碼底下有哪些規則，
-- 一次交給後台當作勾選清單。
create or replace function public.list_reason_codes()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(x order by x->>'code'), '[]'::jsonb) from (
    select jsonb_build_object(
      'code',    r.reason_code,
      'outcome', min(r.outcome),
      'rules',   jsonb_agg(jsonb_build_object('code', r.code, 'title', r.title) order by r.code),
      'enabled', bool_or(r.enabled)
    ) as x
    from public.screening_rules r
    where r.reason_code is not null and r.reason_code <> ''
    group by r.reason_code
  ) t;
$$;

revoke all on function public.list_reason_codes() from public, anon;
grant execute on function public.list_reason_codes() to authenticated;

-- ============================================================
-- 17) 四個新題組（規格第 6.3 節）＋ Dealbreaker 嚴重度表單所需欄位
--
--     ⚠️ 每加一個欄位都要問一次「它該在第幾層」。
--     get_visible_match_profiles() 的遮罩是 to_jsonb(p) - array[...] 的
--     **黑名單**制，所以任何新欄位預設都是公開的——漏掉一個就是一次洩漏。
--     下面每個欄位都同時做兩件事：宣告 ＋ 進第 17.2 節的遮罩清單。
-- ============================================================

-- 欄位本身宣告在第 1 節——get_visible_match_profiles() 在第 2 節就會引用它們，
-- 而 SQL 函式在建立當下就驗證函式本體，欄位必須先存在。
-- （這是第三次踩到同一個坑了：match_user_blocks、weekly_work_hours，現在是這四個題組。）


-- ============================================================
-- 18) 規則庫 V1 其餘 41 條（規格第 5 節 B～S）
--
--     🔴 的通則：**雙方都把這個題組標成 non_negotiable 才成立**。
--     只有一方堅持是 🟡「值得問」，不是「不適合」——那是當事人自己要判斷的事。
--     「🟡／🔴 依重要性」用 escalate 表達：對方標成不可妥協才升級。
-- ============================================================

insert into public.screening_rules
  (code, topic, category, outcome, priority, min_stage, cond, requires, reason_code, title, body, ask, enabled) values

-- ── B. 關係期待（R006、R007）────────────────────────────────
  ('R006','relationship_goal','life_plan','yellow',20,0,
   '{"any":[
      {"all":[{"field":"applicant.relationship_goal","op":"in","value":["以結婚為前提的長期穩定關係","長期交往，順其自然發展"]},
              {"field":"recipient.relationship_goal","op":"in","value":["先以朋友身分互相了解","目前不尋找長期關係"]}]},
      {"all":[{"field":"recipient.relationship_goal","op":"in","value":["以結婚為前提的長期穩定關係","長期交往，順其自然發展"]},
              {"field":"applicant.relationship_goal","op":"in","value":["先以朋友身分互相了解","目前不尋找長期關係"]}]}
    ]}'::jsonb,
   '{applicant.relationship_goal,recipient.relationship_goal}',
   'R_REL_GOAL_DIFF','目前對關係方向的期待不同',
   '一方想往長期走，另一方還在觀望或暫時不找長期關係。這不代表不適合，但值得先聊清楚。',
   '["你現在想要的關係，跟一年後想要的會一樣嗎？"]'::jsonb, true),

  ('R007','relationship_goal','life_plan','red',5,0,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.relationship_goal","op":"eq","value":"以結婚為前提的長期穩定關係"},
                {"field":"recipient.relationship_goal","op":"eq","value":"目前不尋找長期關係"}]},
        {"all":[{"field":"recipient.relationship_goal","op":"eq","value":"以結婚為前提的長期穩定關係"},
                {"field":"applicant.relationship_goal","op":"eq","value":"目前不尋找長期關係"}]}]},
      {"field":"applicant.dealbreakers.relationship_goal","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.relationship_goal","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.relationship_goal,recipient.relationship_goal}',
   'H_REL_GOAL','一方一定要長期伴侶，另一方明確不尋找長期關係',
   '雙方都把這件事標為不可妥協。','[]'::jsonb, true),

-- ── C. 結婚意願（R008、R009）────────────────────────────────
  ('R008','marriage_intent','life_plan','yellow',22,1,
   '{"all":[
      {"field":"applicant.marriage_intent","op":"differs","value":"recipient.marriage_intent"},
      {"field":"applicant.marriage_intent","op":"not_in","value":["一定要結婚","不打算結婚"]},
      {"field":"recipient.marriage_intent","op":"not_in","value":["一定要結婚","不打算結婚"]}
    ]}'::jsonb,
   '{applicant.marriage_intent,recipient.marriage_intent}',
   'R_MARRIAGE_DIFF','婚姻期待不同，但雙方都說可以討論',
   '建議在關係深入之前確認，不要放到最後才發現。',
   '["結婚對你來說，是必要的形式還是可有可無？"]'::jsonb, true),

  ('R009','marriage_intent','life_plan','red',5,1,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.marriage_intent","op":"eq","value":"一定要結婚"},
                {"field":"recipient.marriage_intent","op":"eq","value":"不打算結婚"}]},
        {"all":[{"field":"recipient.marriage_intent","op":"eq","value":"一定要結婚"},
                {"field":"applicant.marriage_intent","op":"eq","value":"不打算結婚"}]}]},
      {"field":"applicant.dealbreakers.marriage_intent","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.marriage_intent","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.marriage_intent,recipient.marriage_intent}',
   'H_MARRIAGE','一方一定要結婚，另一方終身不婚',
   '雙方都把這件事標為不可妥協，屬於核心人生規劃差異。','[]'::jsonb, true),

-- ── D. 生育（R012）──────────────────────────────────────────
  ('R012','kids_plan','life_plan','red',5,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.kids_plan","op":"eq","value":"想要小孩"},
                {"field":"recipient.kids_plan","op":"in","value":["不想要小孩","已有小孩，不打算再生"]}]},
        {"all":[{"field":"recipient.kids_plan","op":"eq","value":"想要小孩"},
                {"field":"applicant.kids_plan","op":"in","value":["不想要小孩","已有小孩，不打算再生"]}]}]},
      {"field":"applicant.dealbreakers.kids_plan","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.kids_plan","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.kids_plan,recipient.kids_plan}',
   'H_CHILD_PLAN','雙方生育規劃存在不可妥協的差異',
   '兩邊都把生育規劃標為不可妥協，而方向相反。','[]'::jsonb, true),

-- ── F. 寵物（R015、R016）────────────────────────────────────
  ('R015','pets','pets','yellow',30,0,
   '{"all":[{"field":"applicant.has_pets","op":"in","value":["有，可以一起照顧","有，不能放棄"]},
            {"field":"recipient.pet_acceptance","op":"is_null"}]}'::jsonb,
   '{applicant.has_pets}',
   'R_PET_UNKNOWN','對方目前有寵物，你還沒填寵物接受度',
   '建議先確認自己能不能與寵物共同生活，再決定要不要往下走。','[]'::jsonb, true),

  ('R016','pets','pets','red',6,0,
   '{"all":[{"field":"applicant.has_pets","op":"eq","value":"有，不能放棄"},
            {"field":"recipient.pet_acceptance","op":"eq","value":"過敏或無法與寵物共同生活"}]}'::jsonb,
   '{applicant.has_pets,recipient.pet_acceptance}',
   'H_PET','一方的寵物不可放棄，另一方無法與寵物共同生活',
   '這一項不需要雙方都標不可妥協——「過敏或無法共同生活」本身就是事實限制，不是偏好。','[]'::jsonb, true),

-- ── G. 居住（R017–R020）─────────────────────────────────────
  ('R017','living','home','yellow',35,2,
   '{"all":[{"field":"applicant.living","op":"eq","value":"與父母同住"},
            {"field":"recipient.req_living","op":"eq","value":"希望對方獨立居住"}]}'::jsonb,
   '{applicant.living,recipient.req_living}',
   'R_RESIDENCE_NOW','對方目前與父母同住，而你希望伴侶獨立居住',
   '「目前住哪」不等於「以後住哪」，建議先問未來的打算再判斷。',
   '["未來如果同居或結婚，你會想住在哪裡？"]'::jsonb, true),

  ('R018','cohabit_with_parents','home','red',7,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.cohabit_with_parents","op":"eq","value":"婚後必須與父母同住"},
                {"field":"recipient.cohabit_with_parents","op":"eq","value":"無法接受與長輩同住"}]},
        {"all":[{"field":"recipient.cohabit_with_parents","op":"eq","value":"婚後必須與父母同住"},
                {"field":"applicant.cohabit_with_parents","op":"eq","value":"無法接受與長輩同住"}]}]},
      {"field":"applicant.dealbreakers.cohabit_with_parents","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.cohabit_with_parents","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.cohabit_with_parents,recipient.cohabit_with_parents}',
   'H_COHABIT','一方婚後必須與父母同住，另一方無法接受',
   '雙方都把這件事標為不可妥協。','[]'::jsonb, true),

  ('R019','relocation','home','green',72,2,
   '{"all":[{"field":"applicant.area","op":"differs","value":"recipient.area"},
            {"field":"applicant.relocation","op":"eq","value":"願意搬遷"},
            {"field":"recipient.relocation","op":"eq","value":"願意搬遷"}]}'::jsonb,
   '{applicant.area,recipient.area,applicant.relocation,recipient.relocation}',
   null,'雖然在不同地區，但雙方都願意搬遷',
   '距離目前不是障礙。','[]'::jsonb, true),

  ('R020','relocation','home','yellow',26,2,
   '{"all":[{"field":"applicant.area","op":"differs","value":"recipient.area"},
            {"field":"applicant.relocation","op":"eq","value":"不願意搬遷"},
            {"field":"recipient.relocation","op":"eq","value":"不願意搬遷"}]}'::jsonb,
   '{applicant.area,recipient.area,applicant.relocation,recipient.relocation}',
   'R_RESIDENCE_UNKNOWN','雙方在不同地區，而且都不願意搬遷',
   '這件事沒辦法靠感情解決，建議早一點談。',
   '["如果關係穩定下來，你會怎麼考量工作與居住地？"]'::jsonb, true),

-- ── H. 遠距（R021、R022）────────────────────────────────────
  ('R021','long_distance','home','unknown',45,2,
   '{"all":[{"field":"applicant.long_distance_ok","op":"not_null"},
            {"field":"recipient.long_distance_ok","op":"is_null"}]}'::jsonb,
   '{applicant.long_distance_ok}',
   'R_LONG_DISTANCE_UNKNOWN','你還沒填對遠距的接受度',
   '對方已經填了，建議你也填一下，初診才判斷得出來。','[]'::jsonb, true),

  ('R022','long_distance','home','red',8,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.long_distance_ok","op":"eq","value":"可以接受遠距"},
                {"field":"applicant.relocation","op":"eq","value":"不願意搬遷"},
                {"field":"applicant.area","op":"differs","value":"recipient.area"},
                {"field":"recipient.long_distance_ok","op":"eq","value":"不接受遠距"}]},
        {"all":[{"field":"recipient.long_distance_ok","op":"eq","value":"可以接受遠距"},
                {"field":"recipient.relocation","op":"eq","value":"不願意搬遷"},
                {"field":"applicant.area","op":"differs","value":"recipient.area"},
                {"field":"applicant.long_distance_ok","op":"eq","value":"不接受遠距"}]}]},
      {"field":"applicant.dealbreakers.long_distance","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.long_distance","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.long_distance_ok,recipient.long_distance_ok,applicant.area,recipient.area}',
   'H_LONG_DISTANCE','一方目前只能遠距，另一方明確不接受遠距',
   '雙方都把這件事標為不可妥協。','[]'::jsonb, true)

on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, min_stage = excluded.min_stage, cond = excluded.cond,
  requires = excluded.requires, reason_code = excluded.reason_code,
  title = excluded.title, body = excluded.body, ask = excluded.ask, enabled = excluded.enabled;

insert into public.screening_rules
  (code, topic, category, outcome, priority, min_stage, cond, escalate, requires, reason_code, title, body, ask, enabled) values

-- ── I. 財務（R025、R026、R027）──────────────────────────────
--     R023 收入差距、R024 有負債本身：不觸發任何規則，見第 18.2 節。
  ('R025','partner_debt','finance','yellow',28,2,
   '{"all":[{"field":"recipient.req_partner_debt","op":"in","value":["希望對方沒有負債","不接受伴侶有負債"]},
            {"field":"applicant.debt","op":"in","value":["有，可負擔範圍內","有，目前壓力較大"]}]}'::jsonb,
   '{"field":"recipient.dealbreakers.partner_debt","op":"eq","value":"non_negotiable"}'::jsonb,
   '{applicant.debt,recipient.req_partner_debt}',
   'R_PARTNER_DEBT','對方自願揭露了負債，而你在條件裡寫了不接受',
   '房貸、學貸與高風險債務完全不是同一件事，建議先問是哪一種再判斷。',
   '["方便說一下是哪一種負債嗎？（例如房貸、學貸、信用貸款）"]'::jsonb, true),

  ('R026','finance','finance','green',72,2,
   '{"all":[{"field":"applicant.finance_style","op":"eq","value":"完全獨立"},
            {"field":"recipient.finance_style","op":"eq","value":"完全獨立"}]}'::jsonb,
   null,
   '{applicant.finance_style,recipient.finance_style}',
   null,'雙方都偏好財務完全獨立','這件事上是一致的。','[]'::jsonb, true),

  ('R027','finance','finance','red',9,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.finance_style","op":"eq","value":"完全共同財務"},
                {"field":"recipient.finance_style","op":"eq","value":"完全獨立"}]},
        {"all":[{"field":"recipient.finance_style","op":"eq","value":"完全共同財務"},
                {"field":"applicant.finance_style","op":"eq","value":"完全獨立"}]}]},
      {"field":"applicant.dealbreakers.finance","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.finance","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null,
   '{applicant.finance_style,recipient.finance_style}',
   'H_FINANCE','一方要求完全共同財務，另一方要求完全獨立',
   '雙方都把這件事標為不可妥協。','[]'::jsonb, true),

-- ── J. 作息（R029）──────────────────────────────────────────
--     R028 早睡 vs 夜貓本身：不觸發，見第 18.2 節。
  ('R029','chronotype','rhythm','yellow',34,1,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.chronotype","op":"eq","value":"早鳥型"},
                {"field":"recipient.chronotype","op":"eq","value":"夜貓型"}]},
        {"all":[{"field":"recipient.chronotype","op":"eq","value":"早鳥型"},
                {"field":"applicant.chronotype","op":"eq","value":"夜貓型"}]}]},
      {"field":"applicant.daily_together_need","op":"eq","value":"每天要有固定相處時間"},
      {"field":"recipient.daily_together_need","op":"eq","value":"每天要有固定相處時間"}
    ]}'::jsonb,
   null,
   '{applicant.chronotype,recipient.chronotype,applicant.daily_together_need,recipient.daily_together_need}',
   'R_RHYTHM','作息相反，而且雙方都希望每天有固定的相處時間',
   '可以共同安排的時間可能比想像中少。單純作息不同不會提醒，是加上「都要固定相處」才值得談。',
   '["如果作息對不上，你會希望怎麼安排固定的相處時間？"]'::jsonb, true),

-- ── K. 聯絡頻率（R030、R031）────────────────────────────────
  ('R030','contact_frequency','rhythm','yellow',32,1,
   '{"any":[
      {"all":[{"field":"applicant.contact_frequency","op":"in","value":["每天多次","每天一次"]},
              {"field":"recipient.contact_frequency","op":"in","value":["幾天一次","不固定"]}]},
      {"all":[{"field":"recipient.contact_frequency","op":"in","value":["每天多次","每天一次"]},
              {"field":"applicant.contact_frequency","op":"in","value":["幾天一次","不固定"]}]}
    ]}'::jsonb,
   null,
   '{applicant.contact_frequency,recipient.contact_frequency}',
   'R_CONTACT_FREQ','習慣的聯絡頻率不同',
   '這通常不是不適合，而是要說清楚——不然容易被解讀成「不在乎」。',
   '["多久聯絡一次，對你來說會覺得剛剛好？"]'::jsonb, true),

  ('R031','contact_frequency','rhythm','red',12,1,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.contact_frequency","op":"eq","value":"每天多次"},
                {"field":"recipient.contact_frequency","op":"eq","value":"不固定"}]},
        {"all":[{"field":"recipient.contact_frequency","op":"eq","value":"每天多次"},
                {"field":"applicant.contact_frequency","op":"eq","value":"不固定"}]}]},
      {"field":"applicant.dealbreakers.contact_frequency","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.contact_frequency","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null,
   '{applicant.contact_frequency,recipient.contact_frequency}',
   'H_CONTACT_FREQ','一方把每天固定聯絡列為必要，另一方不希望每日聯絡',
   '雙方都把這件事標為不可妥協。','[]'::jsonb, true),

-- ── L. 獨處需求（R032）──────────────────────────────────────
  ('R032','alone_time','rhythm','yellow',36,1,
   '{"any":[
      {"all":[{"field":"applicant.alone_time_need","op":"eq","value":"需要很多獨處時間"},
              {"field":"recipient.daily_together_need","op":"eq","value":"每天要有固定相處時間"}]},
      {"all":[{"field":"recipient.alone_time_need","op":"eq","value":"需要很多獨處時間"},
              {"field":"applicant.daily_together_need","op":"eq","value":"每天要有固定相處時間"}]}
    ]}'::jsonb,
   null,
   '{applicant.alone_time_need,recipient.alone_time_need,applicant.daily_together_need,recipient.daily_together_need}',
   'R_ALONE_TIME','親密與個人空間的需求可能不同',
   '一方需要較多獨處時間，另一方希望每天有固定相處。這不是「不適合」，是需要各自說清楚界線。',
   '["你需要獨處的時候，希望對方怎麼做比較好？"]'::jsonb, true),

-- ── O. 原生家庭（R038、R039）────────────────────────────────
--     R037 回家頻率差異本身：不觸發，見第 18.2 節。
  ('R038','family_involvement','family','yellow',38,2,
   '{"any":[
      {"all":[{"field":"applicant.req_family_involvement","op":"eq","value":"希望對方每週參與家庭活動"},
              {"field":"recipient.family_visit_freq","op":"in","value":["幾個月一次","很少"]}]},
      {"all":[{"field":"recipient.req_family_involvement","op":"eq","value":"希望對方每週參與家庭活動"},
              {"field":"applicant.family_visit_freq","op":"in","value":["幾個月一次","很少"]}]}
    ]}'::jsonb,
   null,
   /* requires 只能列「兩個方向的分支都會讀」的欄位。這條是對稱的 any：
      A 的期待對上 B 的頻率、或反過來，所以任何一個欄位都不是兩邊都必要的。
      列了反而會讓「只有一邊填」的情況整條被跳過——而那正是它要抓的情況。 */
   '{}',
   'R_FAMILY_INVOLVE','一方期待伴侶經常參與家庭活動，另一方很少回原生家庭',
   '建議先確認彼此對「家庭參與」的想像。',
   '["你希望另一半多常一起回你家？"]'::jsonb, true),

  ('R039','parents_in_decisions','family','red',10,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.parents_in_decisions","op":"eq","value":"父母會參與重大決定"},
                {"field":"recipient.parents_in_decisions","op":"eq","value":"伴侶關係完全獨立"}]},
        {"all":[{"field":"recipient.parents_in_decisions","op":"eq","value":"父母會參與重大決定"},
                {"field":"applicant.parents_in_decisions","op":"eq","value":"伴侶關係完全獨立"}]}]},
      {"field":"applicant.dealbreakers.parents_in_decisions","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.parents_in_decisions","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null,
   '{applicant.parents_in_decisions,recipient.parents_in_decisions}',
   'H_PARENTS','一方的父母會參與重大決定，另一方要求伴侶關係完全獨立',
   '雙方都把這件事標為不可妥協。','[]'::jsonb, true),

-- ── Q. 關係結構（R042）──────────────────────────────────────
  ('R042','relationship_structure','life_plan','red',4,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.relationship_structure","op":"eq","value":"單偶關係"},
                {"field":"recipient.relationship_structure","op":"eq","value":"開放式關係"}]},
        {"all":[{"field":"recipient.relationship_structure","op":"eq","value":"單偶關係"},
                {"field":"applicant.relationship_structure","op":"eq","value":"開放式關係"}]}]},
      {"field":"applicant.dealbreakers.relationship_structure","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.relationship_structure","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null,
   '{applicant.relationship_structure,recipient.relationship_structure}',
   'H_REL_STRUCTURE','核心關係結構衝突：單偶 vs 開放式',
   '雙方都把這件事標為不可妥協。','[]'::jsonb, true),

-- ── S. 衝突節奏（R045、R046）────────────────────────────────
  ('R045','conflict_style','rhythm','yellow',33,1,
   '{"any":[
      {"all":[{"field":"applicant.conflict_style","op":"eq","value":"當下就想處理"},
              {"field":"recipient.conflict_style","op":"eq","value":"需要冷靜一段時間"}]},
      {"all":[{"field":"recipient.conflict_style","op":"eq","value":"當下就想處理"},
              {"field":"applicant.conflict_style","op":"eq","value":"需要冷靜一段時間"}]}
    ]}'::jsonb,
   null,
   '{applicant.conflict_style,recipient.conflict_style}',
   'R_CONFLICT_STYLE','衝突處理的節奏不同',
   '一方想當下處理，另一方需要先冷靜。兩種都沒有錯，但沒說清楚很容易被誤會成逃避。',
   '["需要冷靜的時候，你希望怎麼讓另一半知道你不是在逃避？"]'::jsonb, true),

  ('R046','conflict_style','rhythm','green',71,1,
   '{"all":[{"field":"applicant.conflict_style","op":"eq","value":"會先說一聲再暫停，之後回來處理"},
            {"field":"recipient.conflict_style","op":"eq","value":"會先說一聲再暫停，之後回來處理"}]}'::jsonb,
   null,
   '{applicant.conflict_style,recipient.conflict_style}',
   null,'雙方都會先告知再暫停溝通',
   '這跟冷暴力是完全相反的兩件事——先說一聲再暫停，是有在處理，不是消失。','[]'::jsonb, true),

-- ── 先關起來的四條（規格第 6.4 節）──────────────────────────
--     不是做不出來，是「放在表單上問不到真話」。等第二階段題庫有結構化答案再打開。
  ('R034','guests_at_home','social','yellow',40,2,
   '{"all":[{"field":"applicant.guests_at_home","op":"eq","value":"常帶朋友回家"},
            {"field":"recipient.req_guests","op":"eq","value":"不接受陌生人常進住家"}]}'::jsonb,
   null, '{applicant.guests_at_home,recipient.req_guests}',
   'R_GUESTS','帶朋友回家的頻率與對方的界線可能衝突','','[]'::jsonb, false),

  ('R035','housework','home','yellow',40,2,
   '{"all":[{"field":"applicant.housework_split","op":"differs","value":"recipient.housework_split"}]}'::jsonb,
   null, '{applicant.housework_split,recipient.housework_split}',
   'R_HOUSEWORK','家務期待不同','表單上人人都會選「平均分攤」，所以這條先關著。','[]'::jsonb, false),

  ('R036','housework','home','red',11,2,
   '{"all":[{"field":"applicant.housework_gendered","op":"eq","value":"應由特定性別主要負責"},
            {"field":"recipient.dealbreakers.housework","op":"eq","value":"non_negotiable"}]}'::jsonb,
   null, '{applicant.housework_gendered}',
   'H_HOUSEWORK','家務的性別分工立場與對方的平等要求衝突','','[]'::jsonb, false),

  ('R041','religion','values','red',11,2,
   '{"all":[{"field":"applicant.req_conversion","op":"eq","value":"伴侶必須改宗"},
            {"field":"recipient.conversion_ok","op":"eq","value":"不願改變宗教"},
            {"field":"recipient.dealbreakers.religion","op":"eq","value":"non_negotiable"}]}'::jsonb,
   null, '{applicant.req_conversion,recipient.conversion_ok}',
   'H_RELIGION','一方要求伴侶改宗，另一方不願改變宗教',
   '極少數案例，但問卷上出現會讓所有人不舒服，所以先關著。','[]'::jsonb, false),

  ('R044','ex_contact','boundaries','yellow',40,2,
   '{"all":[{"field":"applicant.ex_contact_freq","op":"eq","value":"每天密切互動"},
            {"field":"recipient.req_ex_contact","op":"eq","value":"列為紅線"}]}'::jsonb,
   null, '{applicant.ex_contact_freq,recipient.req_ex_contact}',
   'R_EX_CONTACT','與前任的互動頻率與對方的紅線衝突',
   '沒有人會在表單上誠實填這題，所以先關著，留給第二階段與付費 AI。','[]'::jsonb, false)

on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, min_stage = excluded.min_stage, cond = excluded.cond,
  escalate = excluded.escalate, requires = excluded.requires, reason_code = excluded.reason_code,
  title = excluded.title, body = excluded.body, ask = excluded.ask, enabled = excluded.enabled;

-- 18.2 「刻意不觸發」的那幾條 ----------------------------------
-- 這些不是漏掉，是判斷過之後決定不做成規則。存成 outcome='never' 讓它們
-- 留在規則庫裡看得到，才不會有人以為是忘記寫。
-- （prohibits 留空——這幾條限制的是「這個組合不成立規則」，不是「這個欄位不得使用」。）
insert into public.screening_rules (code, topic, category, outcome, priority, cond, title, body) values
  ('R023','income','prohibition','never',99,'{"prohibits":[]}'::jsonb,
   '年收入差距不觸發任何規則','收入差距不是風險。做成規則會讓系統變成階級評分。'),
  ('R024','debt','prohibition','never',99,'{"prohibits":[]}'::jsonb,
   '「有負債」本身不觸發黃燈','房貸、學貸與高風險債務完全不是同一件事。只有在對方明確表示不接受時（R025）才提醒。'),
  ('R028','chronotype','prohibition','never',99,'{"prohibits":[]}'::jsonb,
   '早睡型 vs 夜貓型本身不觸發黃燈','要再加上「雙方都要求每天固定相處」（R029）才值得提醒。'),
  ('R033','social','prohibition','never',99,'{"prohibits":[]}'::jsonb,
   '社交頻率差異本身不觸發黃燈','一個愛聚會、一個愛在家，這件事本身不構成問題。'),
  ('R037','family_involvement','prohibition','never',99,'{"prohibits":[]}'::jsonb,
   '回原生家庭的頻率差異本身不觸發黃燈','要加上一方明確期待伴侶參與（R038）才提醒。'),
  ('R040','religion','prohibition','never',99,'{"prohibits":[]}'::jsonb,
   '宗教不同不觸發黃燈','只有「要求對方改宗」才是衝突（R041），信什麼本身不是。'),
  ('R043','ex_contact','prohibition','never',99,'{"prohibits":[]}'::jsonb,
   '與前任仍有聯繫不觸發黃燈','有聯繫不等於有問題。')
on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, cond = excluded.cond, title = excluded.title, body = excluded.body;

-- ============================================================
-- 19) 安全規則 R056–R058：只進管理後台
--
--     這三條跟其他 55 條的形狀不一樣：它們是「關於某一個人」，不是
--     「關於某一對配對」，所以不走 run_screening() 的成對模型，
--     也不會出現在任何會員看得到的初診結果裡。
--
--     三個硬規定（規格第 1.3 節）：
--       ・被標記的人不會知道自己被標記（跟封鎖不通知對方一致）
--       ・🚨 的效果是「提高人工審查優先順序」，不是自動處分
--       ・R058 的自由文字偵測只能輸出 ⚪，永遠不得判定使用者有那些行為
-- ============================================================

-- 19.1 檢舉要分類，R056 才做得出來 -----------------------------
alter table public.reports add column if not exists category text not null default 'other';
alter table public.reports drop constraint if exists reports_category_check;
alter table public.reports add constraint reports_category_check check (category in
  ('violence','harassment','fraud','fake','spam','other'));
create index if not exists reports_target_open_idx on public.reports(target_id) where not done;

insert into public.screening_rules (code, topic, category, outcome, priority, audience, cond, title, body) values
  ('R056','safety','safety','safety',1,'admin','{}'::jsonb,
   '收到暴力／恐嚇／騷擾類別的檢舉','轉人工安全審查。不進配對評分，也不會通知被檢舉的人。'),
  ('R057','safety','safety','safety',2,'admin','{}'::jsonb,
   '多位互不相關的會員檢舉了相似的重大行為',
   '不讓系統自動判罪，只提高人工審查的優先順序。「互不相關」＝檢舉人之間沒有申請關係、也沒有互相封鎖。'),
  ('R058','safety','safety','unknown',3,'admin','{}'::jsonb,
   '自由文字裡出現可能涉及安全或界線的詞',
   '「我無法接受冷暴力」跟「我生氣就會冷暴力」在關鍵字比對下完全一樣——規則引擎不該分辨，也不該假裝分辨得出來。這裡只負責把這筆排到人工前面。')
on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, audience = excluded.audience,
  title = excluded.title, body = excluded.body;

-- 19.2 R058 的關鍵詞：存成資料，管理員可以改 --------------------
create table if not exists public.safety_keywords (
  word    text primary key,
  note    text not null default '',
  enabled boolean not null default true
);
insert into public.safety_keywords (word, note) values
  ('暴力','肢體或言語暴力'), ('動手','肢體暴力'), ('恐嚇','威脅'),
  ('冷暴力','情緒隔離'), ('情緒勒索','關係控制'),
  ('毒品','違法物質'), ('賭博','成癮行為'),
  ('跟蹤','騷擾'), ('偷拍','隱私侵害')
on conflict (word) do nothing;

-- 19.3 安全佇列 ------------------------------------------------
create or replace function public.admin_safety_queue()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare me uuid := auth.uid(); out_rows jsonb;
begin
  if me is null or not public.match_is_admin(me) then
    raise exception '只有管理員可以查看安全佇列';
  end if;

  select coalesce(jsonb_agg(x order by (x->>'priority')::int, x->>'name'), '[]'::jsonb) into out_rows
  from (
    select jsonb_build_object(
      'user_id',  p.id,
      'name',     coalesce(nullif(p.name,''), '（未命名）'),
      'account_status', p.account_status,
      'posting_locked', p.posting_locked,
      -- 1 = 有 🚨，2 = 只有 ⚪。排序用，不是分數。
      'priority', case when sev.n > 0 then 1 else 2 end,
      'flags',    sev.flags
    ) as x
    from public.match_profiles p
    join lateral (
      select
        count(*) filter (where f->>'outcome' = 'safety') as n,
        jsonb_agg(f order by f->>'outcome') as flags
      from (
        -- R056：暴力／恐嚇／騷擾類別的未處理檢舉
        select jsonb_build_object(
                 'code','R056','outcome','safety',
                 'title','收到暴力／恐嚇／騷擾類別的檢舉',
                 'detail', jsonb_build_object('count', count(*))) as f
          from public.reports r
         where r.target_id = p.id and not r.done
           and r.category in ('violence','harassment')
         having count(*) > 0

        union all

        -- R057：多位「互不相關」的會員檢舉。互不相關＝檢舉人之間
        -- 沒有申請關係、也沒有互相封鎖，避免一群朋友互相拉幫結派。
        select jsonb_build_object(
                 'code','R057','outcome','safety',
                 'title','多位互不相關的會員提出檢舉',
                 'detail', jsonb_build_object('reporters', count(distinct r.by_id))) as f
          from public.reports r
         where r.target_id = p.id and not r.done and r.by_id is not null
        having count(distinct r.by_id) >= 2
           and not exists (
             select 1 from public.reports r1, public.reports r2
              where r1.target_id = p.id and r2.target_id = p.id
                and not r1.done and not r2.done and r1.by_id < r2.by_id
                and (exists (select 1 from public.applications a
                              where (a.from_user = r1.by_id and a.to_user = r2.by_id)
                                 or (a.from_user = r2.by_id and a.to_user = r1.by_id))
                  or exists (select 1 from public.match_user_blocks b
                              where (b.blocker_id = r1.by_id and b.blocked_id = r2.by_id)
                                 or (b.blocker_id = r2.by_id and b.blocked_id = r1.by_id)))
           )

        union all

        -- R058：自由文字偵測。輸出一律是 ⚪，而且措辭永遠是「可能涉及」，
        -- 不得寫成「這個人有這些行為」。
        select jsonb_build_object(
                 'code','R058','outcome','unknown',
                 'title','自由文字中出現可能涉及安全／界線的詞',
                 'detail', jsonb_build_object('words', jsonb_agg(distinct k.word))) as f
          from public.safety_keywords k
         where k.enabled
           and (coalesce(p.bio,'') || ' ' || coalesce(p.wants,'') || ' ' || coalesce(p.taboo,''))
               like '%' || k.word || '%'
        having count(*) > 0
      ) s(f)
    ) sev on sev.flags is not null
    where p.account_status <> 'deleted'
  ) t;

  return out_rows;
end $$;

revoke all on function public.admin_safety_queue() from public, anon;
grant execute on function public.admin_safety_queue() to authenticated;

alter table public.safety_keywords enable row level security;
drop policy if exists "safety_keywords_admin_only" on public.safety_keywords;
create policy "safety_keywords_admin_only" on public.safety_keywords for all
  to authenticated using (public.match_is_admin(auth.uid()))
  with check (public.match_is_admin(auth.uid()));
grant select, insert, update, delete on table public.safety_keywords to authenticated;

-- ============================================================
-- 20) 第二階段結構化問診：S2-01 ～ S2-05（先掛著，enabled=false）
--
--     跟需求規格的一處出入，先講清楚：
--     規格給的欄位名是 contact_frequency_importance、family_decision_boundary
--     這一類「每題一個 importance 欄位」。實作沒有照抄，因為：
--
--     （a）重要度已經有一個機制了——dealbreakers jsonb，而且引擎的 10 條 🔴
--          規則都在讀 applicant.dealbreakers.<topic>。再開五個 *_importance
--          欄位等於同一件事有兩個來源，之後一定會有人問「哪個算數」。
--          所以重要度一律進 dealbreakers，只是**問的地方**搬到第二階段題目旁邊。
--
--     （b）五題裡有四題，上一輪已經有欄位而且有啟用中的規則在用
--          （contact_frequency／alone_time_need／parents_in_decisions／
--            req_family_involvement）。照抄新欄位名會變成同一個問題問兩次。
--          所以是把既有欄位的**選項換成規格裡更細的那一版**，欄位名不動。
--
--     真正新增的只有五個：規格裡確實沒有對應欄位的那幾題。
-- ============================================================

-- 20.1 重要度改成四級 ------------------------------------------
-- ⚪ 不在意 none／🟡 可以討論 discussable／🟠 非常重要 very_important／
-- 🔴 不可妥協 non_negotiable。
-- 舊資料只會有 none／discussable／non_negotiable，全部仍然有效，不用轉換。
-- 🔴 的判定維持不變：**雙方都 non_negotiable 才算核心衝突**。
-- 🟠 不會讓燈變紅，只會讓同一盞黃燈排得比較前面（priority）。

-- 20.2 新增的五個欄位（都是第 2 層資料）------------------------
-- 欄位本身宣告在第 1 節（遮罩函式在第 2 節就會引用，SQL 函式建立當下就驗證本體）。

-- 20.3 既有四個欄位換成更細的選項 -------------------------------
-- 舊值一一對到新值，不會有人的資料被清空。
update public.match_profiles set contact_frequency = case contact_frequency
  when '每天多次'   then '希望一天中保持多次聯絡'
  when '每天一次'   then '希望每天至少有簡短聯絡'
  when '幾天一次'   then '每 2～3 天聯絡一次即可'
  when '不固定'     then '不需要固定聯絡，有事情再說'
  else contact_frequency end
 where contact_frequency in ('每天多次','每天一次','幾天一次','不固定');

update public.match_profiles set alone_time_need = case alone_time_need
  when '需要很多獨處時間' then '我非常重視獨立生活與個人空間'
  when '需要一些'         then '我需要不少自己的時間'
  when '普通'             then '陪伴與獨處大約各半'
  when '不太需要'         then '很少，我喜歡大部分時間一起行動'
  else alone_time_need end
 where alone_time_need in ('需要很多獨處時間','需要一些','普通','不太需要');

update public.match_profiles set parents_in_decisions = case parents_in_decisions
  when '父母會參與重大決定'   then '家人的意見通常會是重要決定因素'
  when '會參考但自己決定'     then '伴侶優先，但會充分考慮家人'
  when '伴侶關係完全獨立'     then '我和伴侶共同決定'
  else parents_in_decisions end
 where parents_in_decisions in ('父母會參與重大決定','會參考但自己決定','伴侶關係完全獨立');

update public.match_profiles set req_family_involvement = case req_family_involvement
  when '希望對方每週參與家庭活動' then '希望經常參與'
  when '希望對方少參與'           then '幾乎不要求'
  else req_family_involvement end
 where req_family_involvement in ('希望對方每週參與家庭活動','希望對方少參與');

-- 20.4 既有規則跟著換成新選項 -----------------------------------
-- 選項換了規則沒換 = 那條規則從此永遠不會命中，而且畫面上看不出來。
update public.screening_rules set cond = '{"any":[
    {"all":[{"field":"applicant.contact_frequency","op":"in","value":["希望一天中保持多次聯絡","希望每天有一段較完整的聊天時間"]},
            {"field":"recipient.contact_frequency","op":"in","value":["不需要固定聯絡，有事情再說","每 2～3 天聯絡一次即可"]}]},
    {"all":[{"field":"recipient.contact_frequency","op":"in","value":["希望一天中保持多次聯絡","希望每天有一段較完整的聊天時間"]},
            {"field":"applicant.contact_frequency","op":"in","value":["不需要固定聯絡，有事情再說","每 2～3 天聯絡一次即可"]}]}
  ]}'::jsonb where code = 'R030';

update public.screening_rules set cond = '{"all":[
    {"any":[
      {"all":[{"field":"applicant.contact_frequency","op":"eq","value":"希望一天中保持多次聯絡"},
              {"field":"recipient.contact_frequency","op":"eq","value":"不需要固定聯絡，有事情再說"}]},
      {"all":[{"field":"recipient.contact_frequency","op":"eq","value":"希望一天中保持多次聯絡"},
              {"field":"applicant.contact_frequency","op":"eq","value":"不需要固定聯絡，有事情再說"}]}]},
    {"field":"applicant.dealbreakers.contact_frequency","op":"eq","value":"non_negotiable"},
    {"field":"recipient.dealbreakers.contact_frequency","op":"eq","value":"non_negotiable"}
  ]}'::jsonb where code = 'R031';

update public.screening_rules set cond = '{"any":[
    {"all":[{"field":"applicant.alone_time_need","op":"eq","value":"我非常重視獨立生活與個人空間"},
            {"field":"recipient.daily_together_need","op":"eq","value":"每天要有固定相處時間"}]},
    {"all":[{"field":"recipient.alone_time_need","op":"eq","value":"我非常重視獨立生活與個人空間"},
            {"field":"applicant.daily_together_need","op":"eq","value":"每天要有固定相處時間"}]}
  ]}'::jsonb where code = 'R032';

update public.screening_rules set cond = '{"any":[
    {"all":[{"field":"applicant.req_family_involvement","op":"in","value":["希望經常參與","希望像自己家人一樣高度參與"]},
            {"field":"recipient.family_visit_freq","op":"in","value":["幾個月一次","很少"]}]},
    {"all":[{"field":"recipient.req_family_involvement","op":"in","value":["希望經常參與","希望像自己家人一樣高度參與"]},
            {"field":"applicant.family_visit_freq","op":"in","value":["幾個月一次","很少"]}]}
  ]}'::jsonb where code = 'R038';

update public.screening_rules set cond = '{"all":[
    {"any":[
      {"all":[{"field":"applicant.parents_in_decisions","op":"in","value":["家人的意見通常會是重要決定因素","希望取得家人的同意再決定"]},
              {"field":"recipient.parents_in_decisions","op":"eq","value":"我和伴侶共同決定"}]},
      {"all":[{"field":"recipient.parents_in_decisions","op":"in","value":["家人的意見通常會是重要決定因素","希望取得家人的同意再決定"]},
              {"field":"applicant.parents_in_decisions","op":"eq","value":"我和伴侶共同決定"}]}]},
    {"field":"applicant.dealbreakers.parents_in_decisions","op":"eq","value":"non_negotiable"},
    {"field":"recipient.dealbreakers.parents_in_decisions","op":"eq","value":"non_negotiable"}
  ]}'::jsonb where code = 'R039';

-- 20.5 五條 S2 規則：先掛著，enabled = false ---------------------
-- topic 刻意跟既有的簡易版規則相同——這樣等 enabled=true 之後，
-- 第 13.7 節的「同一個題組只報最嚴重的那一層」會自動處理重疊，
-- 不會同一件事講兩次。priority 也刻意排在簡易版前面（數字小的優先），
-- 兩者同時命中時留下比較細的那一條。
insert into public.screening_rules
  (code, topic, category, outcome, priority, min_stage, cond, requires, reason_code, title, body, ask, enabled) values

  /* priority 一定要比同題組的簡易版小（數字小＝優先留下）：
     R031=12、R032=36、R039=10、R045=33。不然翻開開關之後，
     「一個題組只留一條」會留下比較粗的那一條，等於白做。 */
  ('S2-01','contact_frequency','communication','red',6,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.contact_frequency","op":"eq","value":"希望一天中保持多次聯絡"},
                {"field":"recipient.contact_frequency","op":"in","value":["不需要固定聯絡，有事情再說","每 2～3 天聯絡一次即可"]}]},
        {"all":[{"field":"recipient.contact_frequency","op":"eq","value":"希望一天中保持多次聯絡"},
                {"field":"applicant.contact_frequency","op":"in","value":["不需要固定聯絡，有事情再說","每 2～3 天聯絡一次即可"]}]}]},
      {"field":"applicant.dealbreakers.contact_frequency","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.contact_frequency","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.contact_frequency,recipient.contact_frequency}',
   'R_CONTACT_FREQ','核心相處需求衝突：日常聯絡密度',
   '雙方對日常聯絡密度的期待相反，而且都標為不可妥協。',
   '["如果工作很忙，你覺得最低限度怎麼聯絡，會讓彼此都比較安心？"]'::jsonb, false),

  ('S2-02','alone_time','rhythm','red',7,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.alone_time_need","op":"eq","value":"我非常重視獨立生活與個人空間"},
                {"field":"recipient.alone_time_need","op":"eq","value":"很少，我喜歡大部分時間一起行動"},
                {"field":"recipient.partner_alone_time_acceptance","op":"eq","value":"無法接受"}]},
        {"all":[{"field":"recipient.alone_time_need","op":"eq","value":"我非常重視獨立生活與個人空間"},
                {"field":"applicant.alone_time_need","op":"eq","value":"很少，我喜歡大部分時間一起行動"},
                {"field":"applicant.partner_alone_time_acceptance","op":"eq","value":"無法接受"}]}]},
      {"field":"applicant.dealbreakers.alone_time","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.alone_time","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   /* partner_alone_time_acceptance 只有「陪伴需求高」的那一方會填，
      列進 requires 會讓另一方沒填時整條被跳過。 */
   '{applicant.alone_time_need,recipient.alone_time_need}',
   'R_ALONE_TIME','親密與個人空間的需求差距很大',
   '一方高度需要獨處、另一方高度需要陪伴，而且明確表示無法接受。這不是誰太黏或誰太冷淡，是兩種都成立的需求剛好對不上。',
   '["當你需要自己待著時，你希望怎麼讓伴侶知道這不是拒絕他？"]'::jsonb, false),

  ('S2-03','housework','home','red',9,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.housework_model","op":"eq","value":"傾向由其中一方主要負責"},
                {"field":"recipient.housework_model","op":"eq","value":"原則上平均分配"}]},
        {"all":[{"field":"recipient.housework_model","op":"eq","value":"傾向由其中一方主要負責"},
                {"field":"applicant.housework_model","op":"eq","value":"原則上平均分配"}]}]},
      {"field":"applicant.dealbreakers.housework","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.housework","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.housework_model,recipient.housework_model}',
   'R_HOUSEWORK','共同生活責任的期待存在核心衝突',
   '一方認為應該平均分配、另一方傾向由其中一方主要負責，而且雙方都標為不可妥協。',
   '["如果兩個人對乾淨的標準不一樣，你覺得該怎麼決定標準？"]'::jsonb, false),

  ('S2-04','conflict_style','rhythm','yellow',30,2,
   '{"any":[
      {"all":[{"field":"applicant.conflict_pause_preference","op":"eq","value":"當下就談清楚"},
              {"field":"recipient.conflict_pause_preference","op":"in","value":["可以隔天再談","可能需要 2～3 天","我通常需要等自己準備好，不希望有固定時間"]}]},
      {"all":[{"field":"recipient.conflict_pause_preference","op":"eq","value":"當下就談清楚"},
              {"field":"applicant.conflict_pause_preference","op":"in","value":["可以隔天再談","可能需要 2～3 天","我通常需要等自己準備好，不希望有固定時間"]}]}
    ]}'::jsonb,
   '{applicant.conflict_pause_preference,recipient.conflict_pause_preference}',
   'R_CONFLICT_STYLE','衝突處理的節奏不同',
   '一方傾向盡快處理，另一方需要較長的情緒整理時間。兩種都沒有錯。',
   '["如果其中一個人需要暫停，你們能不能約定一個彼此都安心的恢復溝通時間？"]'::jsonb, false),

  ('S2-04B','conflict_style','rhythm','unknown',31,2,
   '{"any":[{"field":"applicant.conflict_return_commitment","op":"in","value":["不習慣","不想承諾時間"]},
            {"field":"recipient.conflict_return_commitment","op":"in","value":["不習慣","不想承諾時間"]}]}'::jsonb,
   /* 任一方回答「不習慣／不想承諾」就要提醒，不需要兩邊都填 */
   '{}',
   'R_CONFLICT_RETURN','衝突後重新建立聯繫的方式需要確認',
   '有一方在需要暫停時不習慣說明何時回來談。這**不等於冷暴力**——真正是否涉及懲罰性沉默，要看實際情境，系統不會替任何人下這個判斷。',
   '["如果你需要暫停討論，你願意先說一聲大概多久之後回來談嗎？"]'::jsonb, false),

  ('S2-05','parents_in_decisions','family','red',8,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.parents_in_decisions","op":"in","value":["希望取得家人的同意再決定","家人的意見通常會是重要決定因素"]},
                {"field":"recipient.parents_in_decisions","op":"eq","value":"我和伴侶共同決定"}]},
        {"all":[{"field":"recipient.parents_in_decisions","op":"in","value":["希望取得家人的同意再決定","家人的意見通常會是重要決定因素"]},
                {"field":"applicant.parents_in_decisions","op":"eq","value":"我和伴侶共同決定"}]}]},
      {"field":"applicant.dealbreakers.parents_in_decisions","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.parents_in_decisions","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   '{applicant.parents_in_decisions,recipient.parents_in_decisions}',
   'H_PARENTS','伴侶與原生家庭的決策界線可能存在核心衝突',
   '一方認為重大決定要取得家人同意、另一方認為應由伴侶共同決定，而且雙方都標為不可妥協。這是界線設定不同，不是誰依賴家庭。',
   '["如果家人跟伴侶意見不同，你會希望最後怎麼決定？"]'::jsonb, false)

on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, min_stage = excluded.min_stage, cond = excluded.cond,
  requires = excluded.requires, reason_code = excluded.reason_code,
  title = excluded.title, body = excluded.body, ask = excluded.ask, enabled = excluded.enabled;

-- ============================================================
-- 21) 第二階段結構化表單做好了，把六條 S2 規則打開
-- ============================================================
-- 表單在「我的申請 → 回答第二階段」裡，五題選擇題各自帶一個重要度。
-- requires 會照顧還沒填的人：缺欄位就整條跳過，那個題組記成 ⚪ 資料不足，
-- 不會拿沒填的欄位硬猜。
update public.screening_rules set enabled = true where code like 'S2-%';

-- ============================================================
-- 22) 把 vet_scores 那個百分比廢掉（規格第 9 步）
--
--     那個數字沒有任何校準基礎——我們沒有「配對成功」的標準答案可以回歸，
--     62% 跟 58% 的差別是憑空的。而且只要它還在資料庫裡，遲早有人把它
--     畫回畫面上。所以不是改語意，是整欄拿掉。
--
--     AI 分析改成輸出「觀察／需要追蹤／建議確認的問題」，存在原本的 vet 欄位
--     （JSON 字串）。舊資料是純文字，前端會照原樣顯示並標明是舊版格式。
-- ============================================================
alter table public.applications drop column if exists vet_scores;

-- ============================================================
-- 23) 剩下三個生活場景：居家社交／宗教界線／前任與異性界線
--
--     R034／R035／R036／R041／R044 原本是「不是做不出來，是放在表單上問不到
--     真話」而先關著的五條。這一節不是直接把它們打開——舊的條件式讀的是
--     guests_at_home、housework_split、req_conversion、ex_contact_freq 這些
--     從來沒有問過的欄位，直接開只會得到一條永遠不命中的規則。
--
--     所以是先決定「問什麼才問得到真話」，再把規則重寫到那些欄位上：
--
--     ・R034 居家社交：問的不是外向／內向，是共同生活時私人空間的界線。
--     ・R035 家務：問的不是「你願不願意做家事」（沒有辨識力，人人都選平均分攤），
--       是「你對公平的定義是什麼」。兩個人對公平的定義不同，比誰多做一點更容易
--       累積怨氣。
--     ・R036 不獨立成題。單獨問「你是否認為某個性別應該負責家務」會變成立場問卷，
--       而且社會期許會讓答案失真。改成 R035 的子規則，讀同一個 housework_fairness。
--     ・R041 宗教：不問信仰內容，只問「要求與界線」。信仰不同本身永遠不亮燈，
--       會亮的是「要求對方改變信仰」與「子女教育的期待落差」。
--     ・R044 界線：不問「你能不能接受前任」，問「哪些行為需要先講一聲」。
--       有異性朋友永遠不亮燈，會亮的是兩個人的界線清單差太多。
--
--     欄位與選項的唯一來源是 data/relationship-topics.json，
--     `node tools/gen-topics.mjs --check` 會確認這裡比對的字串真的存在於選項裡——
--     選項改一個字而規則沒跟著改，那條規則會從此永遠不命中，畫面上看不出來。
-- ============================================================

insert into public.screening_rules
  (code, topic, category, outcome, priority, min_stage, cond, escalate, requires,
   reason_code, title, body, ask, enabled) values

  -- ── 居家社交界線 ────────────────────────────────────────
  ('R034','home_social_boundary','social','yellow',34,2,
   '{"any":[
      {"all":[{"field":"applicant.home_social_frequency","op":"eq","value":"喜歡常邀請朋友來家裡"},
              {"field":"recipient.home_social_frequency","op":"in","value":["希望家是高度私人的空間","比較喜歡在外面聚會"]}]},
      {"all":[{"field":"recipient.home_social_frequency","op":"eq","value":"喜歡常邀請朋友來家裡"},
              {"field":"applicant.home_social_frequency","op":"in","value":["希望家是高度私人的空間","比較喜歡在外面聚會"]}]}
    ]}'::jsonb,
   null,
   '{applicant.home_social_frequency,recipient.home_social_frequency}',
   'R_HOME_SOCIAL','居家社交的期待不同',
   '一方希望家裡常有朋友來，另一方希望家是比較私人的空間。這不是外向或內向的問題，是共同生活時空間怎麼用。',
   '["如果住在一起，你希望多久有一次朋友來家裡？有沒有哪些時候你會希望家裡只有你們兩個人？"]'::jsonb, true),

  ('R034B','home_social_boundary','social','red',13,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.home_social_frequency","op":"eq","value":"喜歡常邀請朋友來家裡"},
                {"field":"recipient.home_guest_boundary","op":"eq","value":"不希望朋友進入私人空間"}]},
        {"all":[{"field":"recipient.home_social_frequency","op":"eq","value":"喜歡常邀請朋友來家裡"},
                {"field":"applicant.home_guest_boundary","op":"eq","value":"不希望朋友進入私人空間"}]}]},
      {"field":"applicant.dealbreakers.home_social_boundary","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.home_social_boundary","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null,
   /* requires 只能列「兩個方向的分支都會讀」的欄位。這條是對稱的 any，
      單邊才會填的欄位列進去，另一邊沒填時整條會被跳過——而那正是它要抓的情況。 */
   '{}',
   'H_HOME_SOCIAL','共同生活空間的使用方式存在核心衝突',
   '一方希望家裡常有朋友來，另一方不希望朋友進入私人空間，而且雙方都標為不可妥協。',
   '[]'::jsonb, true),

  -- ── 家務責任：判的是「公平的定義」，不是誰做得多 ──────────
  ('R035','housework','home','yellow',35,2,
   '{"all":[
      {"field":"applicant.housework_fairness","op":"differs","value":"recipient.housework_fairness"},
      {"field":"applicant.housework_fairness","op":"not_in","value":["尚未想過"]},
      {"field":"recipient.housework_fairness","op":"not_in","value":["尚未想過"]}
    ]}'::jsonb,
   null,
   '{applicant.housework_fairness,recipient.housework_fairness}',
   'R_HOUSEWORK','對「家務公平」的定義不同',
   '兩個人對公平的定義不一樣（例如一方認為要做一樣多，另一方認為整體貢獻平衡就好）。這不代表誰不願意做，但長期不談清楚容易累積怨氣。',
   '["你們各自覺得「公平」是做一樣多，還是整體加起來平衡就好？"]'::jsonb, true),

  /* R036 不是獨立的題目，是 R035 的子規則——讀同一個 housework_fairness。
     單獨問「你是否認為某個性別應該負責家務」會變成立場問卷，而且社會期許
     會讓答案失真。這裡也不判誰對誰錯，只指出兩邊的前提不一樣。 */
  ('R036','housework','home','red',11,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.housework_fairness","op":"eq","value":"依傳統性別角色分工"},
                {"field":"recipient.housework_fairness","op":"eq","value":"兩個人做一樣多"}]},
        {"all":[{"field":"recipient.housework_fairness","op":"eq","value":"依傳統性別角色分工"},
                {"field":"applicant.housework_fairness","op":"eq","value":"兩個人做一樣多"}]}]},
      {"field":"applicant.dealbreakers.housework","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.housework","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null,
   '{applicant.housework_fairness,recipient.housework_fairness}',
   'H_HOUSEWORK','家務分工的前提不同，而且雙方都不可妥協',
   '一方以傳統性別角色為分工前提，另一方要求平均分擔，而且雙方都標為不可妥協。系統不判斷哪一種比較好，只指出這件事需要在同居之前談清楚。',
   '[]'::jsonb, true),

  ('R035B','housework','home','yellow',36,2,
   '{"any":[
      {"all":[{"field":"applicant.cleanliness_conflict_style","op":"eq","value":"以要求較高的一方為主"},
              {"field":"recipient.cleanliness_conflict_style","op":"in","value":["各自負責自己的空間","誰在意誰處理"]}]},
      {"all":[{"field":"recipient.cleanliness_conflict_style","op":"eq","value":"以要求較高的一方為主"},
              {"field":"applicant.cleanliness_conflict_style","op":"in","value":["各自負責自己的空間","誰在意誰處理"]}]}
    ]}'::jsonb,
   null,
   '{applicant.cleanliness_conflict_style,recipient.cleanliness_conflict_style}',
   'R_HOUSEWORK','整潔標準不同時的處理方式不一致',
   '一方認為應該向標準較高的人看齊，另一方認為各自管好自己的區域就好。這件事本身很小，但它決定了每一次「你怎麼又沒收」要怎麼收場。',
   '["如果你們對乾淨的標準不一樣，你希望是往高的那邊靠，還是各自管各自的？"]'::jsonb, true),

  -- ── 宗教界線：只問要求與界線，不問信仰內容 ────────────────
  /* 信仰不同本身永遠不亮燈。這裡沒有任何一條規則會去比
     religion_importance 或雙方的信仰內容——那不是暖陽要判斷的事。 */
  ('R041','religion_boundary','values','red',11,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.religion_partner_expectation","op":"eq","value":"希望伴侶跟隨自己的信仰"},
                {"field":"recipient.religion_partner_expectation","op":"in","value":["可以互相尊重，不需要改變","無法接受信仰不同"]}]},
        {"all":[{"field":"recipient.religion_partner_expectation","op":"eq","value":"希望伴侶跟隨自己的信仰"},
                {"field":"applicant.religion_partner_expectation","op":"in","value":["可以互相尊重，不需要改變","無法接受信仰不同"]}]}]},
      {"field":"applicant.dealbreakers.religion_boundary","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.religion_boundary","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null, '{}',
   'H_RELIGION','對信仰的期待存在核心衝突',
   '一方希望伴侶跟隨自己的信仰，另一方希望維持各自的信仰，而且雙方都標為不可妥協。這一條看的是「要求」，不是信仰本身。',
   '[]'::jsonb, true),

  ('R041B','religion_boundary','values','yellow',37,2,
   '{"all":[
      {"field":"applicant.religion_child_plan","op":"differs","value":"recipient.religion_child_plan"},
      {"any":[{"field":"applicant.religion_child_plan","op":"in","value":["希望依照我的信仰","希望孩子在共同的信仰下長大"]},
              {"field":"recipient.religion_child_plan","op":"in","value":["希望依照我的信仰","希望孩子在共同的信仰下長大"]}]}
    ]}'::jsonb,
   null,
   '{applicant.religion_child_plan,recipient.religion_child_plan}',
   'R_RELIGION_CHILD','對子女宗教教育的期待不同',
   '有一方對孩子的宗教教育已經有明確期待，另一方的想法不同或還沒想過。這通常不是現在要解決的事，但值得先知道彼此的想法。',
   '["如果未來有孩子，你希望在信仰上怎麼安排？這件事你已經想得很清楚了嗎？"]'::jsonb, true),

  /* religion_importance 只用在這一條，而且刻意是 ⚪（中性提示）不是黃燈。
     信仰不同不是問題、信仰虔誠更不是問題——這條唯一的作用是讓兩個人知道
     彼此的生活節奏可能不一樣，不帶任何「需要處理」的暗示。
     它也不看是什麼信仰，只看「在生活中佔多重」。 */
  ('R041C','religion_boundary','values','unknown',40,2,
   '{"any":[
      {"all":[{"field":"applicant.religion_importance","op":"eq","value":"是生活的核心"},
              {"field":"recipient.religion_importance","op":"in","value":["沒有宗教信仰","尊重但不特別實踐"]}]},
      {"all":[{"field":"recipient.religion_importance","op":"eq","value":"是生活的核心"},
              {"field":"applicant.religion_importance","op":"in","value":["沒有宗教信仰","尊重但不特別實踐"]}]}
    ]}'::jsonb,
   null,
   '{applicant.religion_importance,recipient.religion_importance}',
   'R_RELIGION_LIFE','信仰在兩個人生活中的份量不同',
   '一方的信仰是生活的核心，另一方沒有特別的信仰實踐。**這不是問題，也不是警示**——只是作息、節慶與週末安排可能不太一樣，先知道會比較好聊。',
   '["你的信仰在日常生活裡通常會怎麼呈現？有哪些是你希望對方一起參與的？"]'::jsonb, true),

  -- ── 前任與異性界線：問界線，不問禁忌 ──────────────────────
  /* 「有異性朋友」永遠不會亮燈。會亮的是兩個人對界線的定義差太多。 */
  ('R044','relationship_boundary','boundaries','red',12,2,
   '{"all":[
      {"any":[
        {"all":[{"field":"applicant.ex_contact_acceptance","op":"eq","value":"完全不能接受"},
                {"field":"recipient.ex_contact_acceptance","op":"eq","value":"沒有問題"}]},
        {"all":[{"field":"recipient.ex_contact_acceptance","op":"eq","value":"完全不能接受"},
                {"field":"applicant.ex_contact_acceptance","op":"eq","value":"沒有問題"}]}]},
      {"field":"applicant.dealbreakers.relationship_boundary","op":"eq","value":"non_negotiable"},
      {"field":"recipient.dealbreakers.relationship_boundary","op":"eq","value":"non_negotiable"}
    ]}'::jsonb,
   null,
   '{applicant.ex_contact_acceptance,recipient.ex_contact_acceptance}',
   'H_BOUNDARY','對前任聯絡的界線存在核心衝突',
   '一方完全不能接受伴侶與前任聯絡，另一方認為沒有問題，而且雙方都標為不可妥協。',
   '[]'::jsonb, true),

  ('R044B','relationship_boundary','boundaries','yellow',38,2,
   '{"any":[
      {"all":[{"field":"applicant.opposite_friend_boundary","op":"eq","value":"完全沒問題"},
              {"field":"recipient.opposite_friend_boundary","op":"in","value":["很難接受","需要提前告知"]}]},
      {"all":[{"field":"recipient.opposite_friend_boundary","op":"eq","value":"完全沒問題"},
              {"field":"applicant.opposite_friend_boundary","op":"in","value":["很難接受","需要提前告知"]}]}
    ]}'::jsonb,
   null,
   '{applicant.opposite_friend_boundary,recipient.opposite_friend_boundary}',
   'R_BOUNDARY','對異性朋友往來的界線期待不同',
   '一方認為完全沒問題，另一方希望先講一聲或覺得比較難接受。有異性朋友本身不是問題，需要對齊的是「哪些事情要先說」。',
   '["有哪些事情你會希望對方先跟你說一聲？不是限制，是想知道你的界線在哪裡。"]'::jsonb, true),

  /* 複選的界線清單：比的是兩份清單差幾項，不是誰勾得多。
     勾得多不代表比較保守，勾得少也不代表比較隨便——差太多才需要談。 */
  ('R044C','relationship_boundary','boundaries','yellow',39,2,
   '{"all":[{"field":"applicant.relationship_boundary_actions","op":"diff_count_gte",
             "value":"recipient.relationship_boundary_actions","n":3}]}'::jsonb,
   null,
   '{applicant.relationship_boundary_actions,recipient.relationship_boundary_actions}',
   'R_BOUNDARY','對「哪些行為需要先講一聲」的認知落差較大',
   '兩個人勾選的界線清單有三項以上不一樣。這不代表誰比較嚴格或比較隨便，而是同一個行為在兩個人心裡的份量不同——多數的「我以為你知道」都是從這裡開始的。',
   '["有沒有哪一件事，你覺得本來就該先說，但其實對方可能不這麼想？"]'::jsonb, true)

on conflict (code) do update set
  topic = excluded.topic, category = excluded.category, outcome = excluded.outcome,
  priority = excluded.priority, min_stage = excluded.min_stage, cond = excluded.cond,
  escalate = excluded.escalate, requires = excluded.requires, reason_code = excluded.reason_code,
  title = excluded.title, body = excluded.body, ask = excluded.ask, enabled = excluded.enabled;

-- ============================================================
-- 24) 對話室安全提醒（三級）與 Consent Mode
--
--     這一節有兩條寫死的原則，違反哪一條都比「漏偵測」更糟：
--
--     (1) **系統不做法律定性。** 不寫「此言論構成性騷擾」。
--         是否構成性騷擾、適用哪一套法律、有沒有刑事責任，都要看情境、
--         關係、是否持續、是否違反意願等具體事實，不能靠一句文字下結論。
--         系統只描述「這段內容可能涉及什麼」，並把選項交回當事人。
--
--     (2) **不能只做關鍵字比對。**「我不喜歡別人問我會不會口交」跟
--         「妳會口交嗎」含同一個詞，但一個是在講自己的界線、一個是要求。
--         只看關鍵字會把前者也亮紅燈——那會讓人不敢談論自己的界線，
--         剛好害到最需要保護的那個人。
--         所以偵測是兩層：先抓訊號類別，再看訊號的「組合」。
--
--     偵測在伺服器端跑（send_match_message 裡），等級存在訊息上。
--     放前端的話，改一下 devtools 就沒有了。
-- ============================================================

-- 24.1 訊號類別 ------------------------------------------------
--      規則是資料不是程式：要調整用字不必改函式、不必重新部署。
--      pattern 是 POSIX 正規表示式，對 body 做大小寫不敏感比對。
create table if not exists public.chat_safety_signals (
  code    text primary key,
  class   text not null check (class in
            ('sexual','body_topic','threat','threat_harm','coercion',
             'intimate_image','request','selfref','refusal','reported')),
  pattern text not null,
  note    text not null default '',
  enabled boolean not null default true
);

/* ⚠️ 這個 check 一定要獨立成 alter，不能只寫在 create table 裡。
   `create table if not exists` 對已經存在的表是完全的 no-op——表建好之後才加進
   清單的類別（例如第 25 節的 'reported'），在既有資料庫上永遠不會生效，
   只會在 insert 的時候炸成 23514。而本機測試每次都先 drop schema，
   剛好是唯一碰不到這條路徑的跑法。
   凡是「之後可能會加值」的 check，都要照這個寫法拉出來。 */
alter table public.chat_safety_signals drop constraint if exists chat_safety_signals_class_check;
alter table public.chat_safety_signals add constraint chat_safety_signals_class_check
  check (class in ('sexual','body_topic','threat','threat_harm','coercion',
                   'intimate_image','request','selfref','refusal','reported'));

insert into public.chat_safety_signals (code, class, pattern, note) values
  -- 露骨性內容
  ('S_ACT','sexual','(口交|肛交|做愛|上床|性交|自慰|一夜情|約砲|約炮)','性行為'),
  ('S_BODY','sexual','(胸部|奶子|下體|生殖器|陰道|陰莖|屁股|裸體|裸照)','性器官或裸露'),
  -- 較私密但不必然是性要求的身體話題
  ('B_BODY','body_topic','(身材|三圍|罩杯|體重多少|腿|穿多少)','私密的身體話題'),
  -- 威脅
  ('T_LEAK','threat','(傳出去|散[佈布]|公開你的|公開妳的|讓大家看|給你家人看|給妳家人看)','散布威脅'),
  /* 人身威脅單獨成一類：在對話裡威脅要傷害對方，本身就是紅燈，
     不需要再搭配任何性相關內容。 */
  ('T_HARM','threat_harm','(弄死|殺了你|殺了妳|讓你好看|讓妳好看|找人處理你|找人處理妳|打死你|打死妳)','人身威脅'),
  ('T_COND','threat','(不給我|不答應|不聽話).{0,12}(就|我就)','條件式威脅'),
  -- 強迫
  ('C_MUST','coercion','(一定要|必須|不然就|否則就|你敢|妳敢)','強迫語氣'),
  -- 私密影像
  ('I_PIC','intimate_image','(裸照|私密照|不穿衣服的照片|脫光|裸.{0,3}視訊)','私密影像'),
  -- 第二人稱要求：這是把「談論」跟「要求」分開的關鍵訊號
  /* 中文的疑問語尾不只有「嗎」。少了呢／啊／問號，
     「你體重多少啊」就會被當成陳述句而漏掉。 */
  ('R_ASK','request','(你|妳|您).{0,12}(嗎|嘛|吧|呢|啊|\?|？)','對對方提問'),
  /* 動詞跟「給我」中間通常夾著受詞：「傳裸照給我」。
     寫死成「傳給我」會漏掉最常見的那種說法。 */
  ('R_GIVE','request','((傳|拍|發|寄|給).{0,8}給我|給我看|讓我看|給我一張)','要求提供'),
  ('R_WANT','request','(我想看|我要看|我想要你|我想要妳)','表達索求'),
  -- 反向訊號：在講自己的界線、引述別人的話、或在拒絕。
  -- 命中這些的時候，同一句裡的性相關詞不該被當成「要求」。
  ('X_SELF','selfref','(我不喜歡|我不想|我討厭|我不願意|不要問我|別問我|我覺得不舒服)','在講自己的界線'),
  ('X_QUOTE','selfref','(他問我|她問我|對方問我|有人問我|之前有人)','在引述別人說過的話'),
  -- 對方已經表達拒絕：後續再送性內容，性質完全不同
  ('X_STOP','refusal','(不要|停止|別再|我不想談|請停下|不舒服|拒絕)','表達拒絕'),
  /* 「別人對我做了什麼」的第一人稱轉述。對話室**不用**這一類——
     在對話室裡命中的會是受害者自己那則訊息，替受害者的訊息標紅燈是最糟的結果。
     只有第 25 節的意見回饋在用：那裡的語境本來就是「我來說一件發生在我身上的事」，
     講到這種話通常代表他要找的是檢舉，不是產品意見。 */
  ('P_TOME','reported','(讓我好看|恐嚇我|威脅我|騷擾我|逼我|跟蹤我|傳.{0,8}給我)','轉述別人對自己做的事')
on conflict (code) do update set
  class = excluded.class, pattern = excluded.pattern,
  note = excluded.note, enabled = excluded.enabled;

alter table public.chat_safety_signals enable row level security;
drop policy if exists "chat_safety_signals_read" on public.chat_safety_signals;
create policy "chat_safety_signals_read" on public.chat_safety_signals
  for select to authenticated using (true);
drop policy if exists "chat_safety_signals_write_admin" on public.chat_safety_signals;
create policy "chat_safety_signals_write_admin" on public.chat_safety_signals
  for all to authenticated
  using (public.match_is_admin(auth.uid())) with check (public.match_is_admin(auth.uid()));
grant select on public.chat_safety_signals to authenticated;
grant insert, update, delete on public.chat_safety_signals to authenticated;

-- 24.2 一段文字命中哪些訊號類別 --------------------------------
create or replace function public.chat_signal_classes(p_body text)
returns text[] language sql stable set search_path = public, pg_temp as $$
  select coalesce(array_agg(distinct s.class), '{}'::text[])
    from public.chat_safety_signals s
   where s.enabled and coalesce(p_body,'') ~* s.pattern;
$$;

-- 24.3 Consent Mode ------------------------------------------
--      兩個成年人真的想談性話題時，不該一看到性詞就一直跳警告。
--      但這是「雙方各自按下」才成立，而且隨時可以撤回——
--      單方面宣告的同意不是同意。
create table if not exists public.chat_consent (
  application_id uuid not null references public.applications(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  agreed_at      timestamptz not null default now(),
  primary key (application_id, user_id)
);
alter table public.chat_consent enable row level security;
drop policy if exists "chat_consent_participant" on public.chat_consent;
create policy "chat_consent_participant" on public.chat_consent
  for select to authenticated using (exists (
    select 1 from public.applications a
     where a.id = application_id and auth.uid() in (a.from_user, a.to_user)));
grant select on public.chat_consent to authenticated;

create or replace function public.chat_consent_on(p_app_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select (select count(*) from public.chat_consent c where c.application_id = p_app_id) >= 2;
$$;

-- 自己按下或撤回同意。永遠只能動自己那一列——替對方按下同意是最不能允許的事。
create or replace function public.set_chat_consent(p_app_id uuid, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_app public.applications;
begin
  select * into v_app from public.applications where id = p_app_id;
  if v_app is null or auth.uid() not in (v_app.from_user, v_app.to_user) then
    raise exception '無權使用這個對話';
  end if;
  if v_app.stage < 2 then raise exception '第二階段後才有對話室'; end if;
  if p_on then
    insert into public.chat_consent(application_id, user_id) values (p_app_id, auth.uid())
      on conflict do nothing;
  else
    delete from public.chat_consent where application_id = p_app_id and user_id = auth.uid();
  end if;
  return public.chat_consent_state(p_app_id);
end $$;
revoke all on function public.set_chat_consent(uuid, boolean) from public, anon;
grant execute on function public.set_chat_consent(uuid, boolean) to authenticated;

create or replace function public.chat_consent_state(p_app_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_app public.applications; v_me boolean; v_other boolean;
begin
  select * into v_app from public.applications where id = p_app_id;
  if v_app is null or auth.uid() not in (v_app.from_user, v_app.to_user) then
    raise exception '無權使用這個對話';
  end if;
  select exists(select 1 from public.chat_consent
                 where application_id = p_app_id and user_id = auth.uid()) into v_me;
  select exists(select 1 from public.chat_consent
                 where application_id = p_app_id and user_id <> auth.uid()) into v_other;
  return jsonb_build_object('mine', v_me, 'other', v_other, 'both', v_me and v_other);
end $$;
revoke all on function public.chat_consent_state(uuid) from public, anon;
grant execute on function public.chat_consent_state(uuid) to authenticated;

-- 24.4 判等級 --------------------------------------------------
--      p_refused = 對方在最近的對話裡已經表達過拒絕。
--      這個參數存在的理由：同一句話在「對方剛說不要」之後送出，
--      性質跟第一次問完全不同。
create or replace function public.chat_safety_level(
  p_body text, p_consent boolean default false, p_refused boolean default false
) returns jsonb language plpgsql stable set search_path = public, pg_temp as $$
declare cls text[]; sexual boolean; body_t boolean; threat boolean; harm boolean;
        coercion boolean; image boolean; request boolean; selfref boolean;
begin
  cls := public.chat_signal_classes(p_body);
  sexual   := 'sexual'         = any(cls);
  body_t   := 'body_topic'     = any(cls);
  threat   := 'threat'         = any(cls);
  harm     := 'threat_harm'    = any(cls);
  coercion := 'coercion'       = any(cls);
  image    := 'intimate_image' = any(cls);
  request  := 'request'        = any(cls);
  selfref  := 'selfref'        = any(cls);

  -- 威脅要傷害對方，本身就是紅燈，不需要搭配任何性相關內容
  if harm then return jsonb_build_object('level','danger','code','D_HARM'); end if;

  /* 🔴 安全紅燈：脅迫、強迫、或在對方說過不要之後仍然繼續。
     這一層 **不受 Consent Mode 影響**——同意談性話題，
     從來不等於同意被威脅或被強迫。 */
  if threat and (sexual or image or coercion) then
    return jsonb_build_object('level','danger','code','D_THREAT');
  end if;
  if coercion and (sexual or image) then
    return jsonb_build_object('level','danger','code','D_COERCE');
  end if;
  if p_refused and (sexual or image) and request then
    return jsonb_build_object('level','danger','code','D_PERSIST');
  end if;

  /* 在講自己的界線、或在引述別人說過的話，就不是在對對方提出要求。
     「我不喜歡別人問我會不會口交」跟「妳會口交嗎」含同一個詞，
     把前者也亮燈，等於讓人不敢談自己的界線。 */
  if selfref then return jsonb_build_object('level', null, 'code', null); end if;

  -- Consent Mode 開著的時候，🟠 與 🟡 都不再打斷對話（🔴 仍然會亮）
  if p_consent then return jsonb_build_object('level', null, 'code', null); end if;

  if sexual and request then
    return jsonb_build_object('level','sexual','code','S_UNINVITED');
  end if;
  if (body_t or sexual) and request then
    return jsonb_build_object('level','boundary','code','B_PRIVATE');
  end if;
  return jsonb_build_object('level', null, 'code', null);
end $$;

-- 24.5 訊息上存等級 --------------------------------------------
alter table public.match_messages add column if not exists safety_level text;
alter table public.match_messages add column if not exists safety_code text;
-- 理由同上：等級之後可能會增加，check 要獨立成 alter 才會在既有資料庫上更新
alter table public.match_messages drop constraint if exists match_messages_safety_level_check;
alter table public.match_messages add constraint match_messages_safety_level_check
  check (safety_level is null or safety_level in ('boundary','sexual','danger'));

-- 24.6 送訊息時就地判定 ----------------------------------------
--      注意：**不擋下訊息**。擋下來的話送出的人會改寫幾個字再送一次，
--      而收到的人反而失去「這個人剛剛說了什麼」的證據。
--      暖陽的選擇是讓它送出去、標記起來、把選項交給收到的人。
create or replace function public.send_match_message(p_app_id uuid, p_body text, p_kind text default 'message')
returns public.match_messages
language plpgsql security definer set search_path = '' as $$
declare v_app public.applications; v_profile public.match_profiles; v_msg public.match_messages;
        v_consent boolean; v_refused boolean; v_safe jsonb;
begin
  select * into v_app from public.applications where id = p_app_id;
  if v_app is null or auth.uid() not in (v_app.from_user, v_app.to_user) then raise exception '無權使用這個對話'; end if;
  if v_app.stage < 2 or v_app.status <> 'open' then raise exception '第二階段後且申請進行中才能對話'; end if;
  if exists (select 1 from public.match_blocks where application_id = p_app_id) then raise exception '這段對話已被關閉'; end if;
  if public.match_is_blocked(v_app.from_user, v_app.to_user) then raise exception '這段對話已被關閉'; end if;
  select * into v_profile from public.match_profiles where id = auth.uid();
  if v_profile.account_status <> 'active' or v_profile.posting_locked then raise exception '你的發言權限目前受限'; end if;
  if p_kind not in ('message','question') then raise exception '不支援的訊息類型'; end if;
  if char_length(btrim(coalesce(p_body,''))) not between 1 and 2000 then raise exception '訊息需為 1 到 2000 字'; end if;
  if (select count(*) from public.match_messages where sender_id = auth.uid() and created_at > now() - interval '1 minute') >= 10
    then raise exception '傳送太頻繁，請稍後再試'; end if;

  v_consent := public.chat_consent_on(p_app_id);
  -- 對方最近 20 則裡有沒有表達過拒絕
  select exists (
    select 1 from (
      select body from public.match_messages
       where application_id = p_app_id and sender_id <> auth.uid()
       order by created_at desc limit 20) t
     where 'refusal' = any(public.chat_signal_classes(t.body))
  ) into v_refused;
  v_safe := public.chat_safety_level(btrim(p_body), v_consent, v_refused);

  insert into public.match_messages(application_id, sender_id, kind, body, safety_level, safety_code)
    values (p_app_id, auth.uid(), p_kind, btrim(p_body),
            nullif(v_safe->>'level',''), nullif(v_safe->>'code',''))
    returning * into v_msg;
  return v_msg;
end $$;
revoke all on function public.send_match_message(uuid,text,text) from public, anon;
grant execute on function public.send_match_message(uuid,text,text) to authenticated;

-- 24.7 🔴 進管理端的安全佇列 ------------------------------------
--      只給管理員看得到「有幾則、在哪一段對話」，不外流訊息內容——
--      內容要在檢舉稽核的流程裡看，不是在一張列表上隨手翻。
create or replace function public.admin_chat_danger_counts()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare out_rows jsonb;
begin
  if auth.uid() is null or not public.match_is_admin(auth.uid()) then
    raise exception '只有管理員可以查看';
  end if;
  select coalesce(jsonb_agg(x order by x->>'last_at' desc), '[]'::jsonb) into out_rows
    from (
      select jsonb_build_object(
        'application_id', m.application_id,
        'sender_id', m.sender_id,
        'n', count(*),
        'last_at', max(m.created_at)
      ) as x
      from public.match_messages m
      where m.safety_level = 'danger'
        and m.created_at > now() - interval '30 days'
      group by m.application_id, m.sender_id
    ) t;
  return out_rows;
end $$;
revoke all on function public.admin_chat_danger_counts() from public, anon;
grant execute on function public.admin_chat_danger_counts() to authenticated;

-- ============================================================
-- 25) 意見回饋：使用者回報遇到的問題
--
--     跟「檢舉」刻意分開，不是為了整齊，是因為兩件事的後果完全不同：
--       ・檢舉 → 關於**某個人**的行為，有安全含意，進安全佇列，有時效承諾。
--       ・意見回饋 → 關於**產品**（壞掉了、看不懂、想要什麼），沒有安全含意。
--     混在一起最糟的後果不是雜亂，是**一則「有人一直傳很噁心的訊息給我」
--     掉進一個沒有時效、沒有人每天看的產品意見清單裡**。
--     所以送出前會就地檢查，看起來像在講某個人的話就先問一次要不要改用檢舉。
--
--     另外刻意**不承諾一定回覆**。檢舉那個「3 個工作日內回覆」目前已經沒有任何
--     排程在盯了（見 README 第 36 節），不該再多一個做不到的承諾。
--     這裡寫的是「我們會看，但不保證每一則都回覆」——做得到的才寫。
-- ============================================================

create table if not exists public.feedback (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  category   text not null default 'other'
               check (category in ('bug','confusing','suggestion','content','other')),
  body       text not null check (char_length(btrim(body)) between 5 and 2000),
  -- 在哪一頁遇到的。純粹是為了重現問題，不是行為追蹤：
  -- 只存分頁代號（例如 'board'），不存瀏覽紀錄、不存停留時間。
  page       text not null default '',
  -- 瀏覽器與畫面寬度，由使用者自己勾選要不要附上（預設不附）。
  -- 版面壞掉的回報沒有這個幾乎修不了，但那是使用者的資訊，要他自己決定。
  env        text not null default '',
  status     text not null default 'new' check (status in ('new','seen','done')),
  admin_note text not null default '',
  created_at timestamptz not null default now(),
  handled_at timestamptz
);
-- 理由同第 24 節：類別與狀態之後很可能會增加，check 要獨立成 alter
alter table public.feedback drop constraint if exists feedback_category_check;
alter table public.feedback add constraint feedback_category_check
  check (category in ('bug','confusing','suggestion','content','other'));
alter table public.feedback drop constraint if exists feedback_status_check;
alter table public.feedback add constraint feedback_status_check
  check (status in ('new','seen','done'));

create index if not exists feedback_status_created_idx on public.feedback(status, created_at desc);
create index if not exists feedback_user_idx on public.feedback(user_id, created_at desc);

alter table public.feedback enable row level security;

-- 自己看得到自己送出的（不然送出去就是個黑洞，沒有人會想送第二次）
drop policy if exists "feedback_read_own_or_admin" on public.feedback;
create policy "feedback_read_own_or_admin" on public.feedback
  for select to authenticated
  using (user_id = auth.uid() or public.match_is_admin(auth.uid()));

-- 只有管理員能改狀態；使用者送出後不能自己改內容或狀態
drop policy if exists "feedback_update_admin" on public.feedback;
create policy "feedback_update_admin" on public.feedback
  for update to authenticated
  using (public.match_is_admin(auth.uid())) with check (public.match_is_admin(auth.uid()));

grant select on public.feedback to authenticated;
grant update on public.feedback to authenticated;

-- 送出走安全函式：欄位由伺服器決定，前端不能自己塞 status／user_id
create or replace function public.submit_feedback(
  p_category text, p_body text, p_page text default '', p_env text default ''
) returns public.feedback
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_row public.feedback; v_profile public.match_profiles;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into v_profile from public.match_profiles where id = auth.uid();
  if v_profile.account_status <> 'active' then raise exception '你的帳號目前無法使用這個功能'; end if;
  if p_category not in ('bug','confusing','suggestion','content','other') then
    raise exception '不支援的類別';
  end if;
  if char_length(btrim(coalesce(p_body,''))) not between 5 and 2000 then
    raise exception '請寫 5 到 2000 字';
  end if;
  -- 同一個人短時間內只能送幾則。不是防使用者，是防「按鈕連點兩下送出兩則」
  -- 以及被盜的帳號拿來洗版。
  if (select count(*) from public.feedback
       where user_id = auth.uid() and created_at > now() - interval '10 minutes') >= 5 then
    raise exception '你剛剛已經送出好幾則了，休息一下再送';
  end if;
  insert into public.feedback(user_id, category, body, page, env)
    values (auth.uid(), p_category, btrim(p_body), left(coalesce(p_page,''), 40),
            left(coalesce(p_env,''), 200))
    returning * into v_row;
  return v_row;
end $$;
revoke all on function public.submit_feedback(text,text,text,text) from public, anon;
grant execute on function public.submit_feedback(text,text,text,text) to authenticated;

-- 送出前的提醒：這段文字看起來像在講某個人嗎？
--
-- 直接沿用第 24 節對話室的訊號類別，不另外抄一份詞庫——
-- 抄一份就會有第二份會走鐘的東西。這裡只回傳「要不要提醒」，
-- 不做任何判定、不擋下送出：使用者說「這件事我就是想當成產品問題講」也可以。
--
-- 直接用第 24 節的 chat_safety_level()，不是只拿它的訊號類別。
-- 第一版只比對類別，結果「我不喜歡別人問我會不會口交，希望站上能講清楚界線」
-- 也被判成在講某個人——那正是第 24 節的反向訊號（selfref）要擋掉的誤判，
-- 只抄一半等於把那條防線丟掉。用整支函式就自動帶著它。
create or replace function public.feedback_looks_personal(p_body text)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select (public.chat_safety_level(coalesce(p_body,''), false, false)->>'level') is not null
      -- reported_harm 不受 selfref 抵銷：講自己被打，本來就是第一人稱
      or 'reported_harm' = any(public.chat_signal_classes(coalesce(p_body,'')))
      or ('reported' = any(public.chat_signal_classes(coalesce(p_body,'')))
          and not ('selfref' = any(public.chat_signal_classes(coalesce(p_body,'')))));
$$;

-- 管理端清單
create or replace function public.admin_feedback_list(p_status text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare out_rows jsonb;
begin
  if auth.uid() is null or not public.match_is_admin(auth.uid()) then
    raise exception '只有管理員可以查看意見回饋';
  end if;
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) into out_rows
    from (
      select jsonb_build_object(
        'id', f.id, 'category', f.category, 'body', f.body, 'page', f.page,
        'env', f.env, 'status', f.status, 'admin_note', f.admin_note,
        'created_at', f.created_at, 'handled_at', f.handled_at,
        'name', coalesce(nullif(p.name,''), '（未命名）'),
        'user_id', f.user_id
      ) as x
      from public.feedback f
      left join public.match_profiles p on p.id = f.user_id
      where p_status is null or f.status = p_status
    ) t;
  return out_rows;
end $$;
revoke all on function public.admin_feedback_list(text) from public, anon;
grant execute on function public.admin_feedback_list(text) to authenticated;

create or replace function public.admin_set_feedback_status(
  p_id uuid, p_status text, p_note text default ''
) returns public.feedback
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_row public.feedback;
begin
  if auth.uid() is null or not public.match_is_admin(auth.uid()) then
    raise exception '只有管理員可以處理意見回饋';
  end if;
  if p_status not in ('new','seen','done') then raise exception '不支援的狀態'; end if;
  update public.feedback
     set status = p_status,
         admin_note = left(coalesce(p_note, admin_note), 1000),
         handled_at = case when p_status = 'done' then now() else handled_at end
   where id = p_id returning * into v_row;
  if v_row.id is null then raise exception '找不到這一則'; end if;
  return v_row;
end $$;
revoke all on function public.admin_set_feedback_status(uuid,text,text) from public, anon;
grant execute on function public.admin_set_feedback_status(uuid,text,text) to authenticated;

-- ============================================================
-- 26) 自訂選項：興趣、個性、物種、性別都可以自己新增
--
--     這四個欄位有一個共同點，而且是這一節存在的全部理由：
--     **它們在佈告欄上是第 0 層公開的。**
--     也就是說，開放自由輸入等於開了一條「把任何文字放到所有人都看得到的地方」
--     的管道——而暖陽整套四層漸進式揭露，就是為了讓聯絡方式要走完三階段、
--     雙方都同意才交換。一個叫做「我的興趣」的欄位如果可以填
--     「IG: xxx_1234」，那整套解鎖流程就被繞過去了，而且是使用者自己繞的，
--     不會有人來檢舉。
--
--     所以自訂值一律在伺服器端檢查。放前端的話改一下 devtools 就沒有了。
--     檢查的是形式（長度、數量、有沒有聯絡方式），不是內容好壞——
--     系統不評價別人怎麼描述自己。
-- ============================================================

-- 26.1 一段文字裡有沒有聯絡方式 --------------------------------
--      寧可誤擋也不要漏：這裡擋下來的代價是使用者改個寫法，
--      漏掉的代價是那個人的聯絡方式對全站公開，而且他以為只有配對成功的人看得到。
create or replace function public.looks_like_contact(p_text text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  -- 括號不能省：|| 的優先序比 ~* 低，不括起來會變成
  -- (p_text ~* '(') || 其餘字串，整個函式就回傳 text 而不是 boolean。
  select coalesce(p_text,'') ~* ('('
      || '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'          -- email
      || '|09[0-9]{8}|09[0-9]{2}-?[0-9]{3}-?[0-9]{3}'      -- 手機
      || '|\+?886[- ]?9[0-9]{8}'
      || '|(line|賴|萊|加賴)[ :：]?id'                      -- LINE ID
      || '|(ig|insta|instagram|fb|facebook|telegram|tg|wechat|微信|discord)[ :：@]'
      || '|@[a-z0-9._]{4,}'                                -- @帳號
      || '|https?://|t\.me/|line\.me/'
      || ')');
$$;

-- 26.2 清洗一組自訂標籤 ----------------------------------------
--      修剪空白與換行、去掉重複、限制長度與數量。
--      回傳清乾淨的陣列；有聯絡方式的話由呼叫端負責擋，不在這裡靜靜丟掉——
--      靜靜丟掉會讓使用者以為存好了。
create or replace function public.clean_tags(p_tags jsonb, p_max_n int default 20, p_max_len int default 12)
returns jsonb language sql immutable set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(t order by ord), '[]'::jsonb) from (
    select distinct on (t) t, ord from (
      select btrim(regexp_replace(v, '[\s　]+', ' ', 'g')) as t,
             row_number() over () as ord
        from jsonb_array_elements_text(
               case when jsonb_typeof(coalesce(p_tags,'[]'::jsonb)) = 'array'
                    then p_tags else '[]'::jsonb end) v
    ) x
    where t <> '' and char_length(t) <= p_max_len
    order by t, ord
  ) y
  where ord <= p_max_n;
$$;

-- 26.3 存檔時檢查 ----------------------------------------------
create or replace function public.guard_profile_custom_text()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare bad text; raw jsonb; n int;
begin
  /* 順序很重要：**先檢查原始輸入，最後才清洗。**
     反過來寫的話，clean_tags 的長度上限會先把「IG @mycoolname」這種
     超過 12 個字的聯絡方式整條丟掉——結果是使用者以為存好了，
     實際上那一項消失了，而且他不知道為什麼。
     凡是使用者會發現不見的東西，都要報錯講清楚；
     clean_tags 只負責他不會發現的整理（修剪空白、去重複）。 */
  raw := (case when jsonb_typeof(coalesce(new.interests,'[]'::jsonb)) = 'array'
               then new.interests else '[]'::jsonb end)
      || (case when jsonb_typeof(coalesce(new.personality,'[]'::jsonb)) = 'array'
               then new.personality else '[]'::jsonb end);

  -- ① 標籤裡不能有聯絡方式（這一整節的重點）
  select t into bad from jsonb_array_elements_text(raw) t
   where public.looks_like_contact(t) limit 1;
  if bad is not null then
    raise exception '「%」看起來是聯絡方式。興趣與個性標籤在佈告欄上是公開的，'
      '聯絡方式請填在「解鎖後才看得到的資訊」，那一欄要雙方都通過三階段並同意才會交換。', bad;
  end if;

  -- ② 太長的標籤：報錯，不要靜靜丟掉
  select t into bad from jsonb_array_elements_text(raw) t
   where char_length(btrim(t)) > 12 limit 1;
  if bad is not null then
    raise exception '「%」超過 12 個字。標籤是卡片上的小標，太長會排不下——'
      '想多寫一點的話，自我介紹那一欄沒有這個限制。', bad;
  end if;

  -- ③ 太多：一樣報錯
  new.interests   := public.clean_tags(new.interests, 999, 12);
  new.personality := public.clean_tags(new.personality, 999, 12);
  n := jsonb_array_length(new.interests);
  if n > 20 then raise exception '興趣最多 20 個，目前有 % 個', n; end if;
  n := jsonb_array_length(new.personality);
  if n > 20 then raise exception '個性標籤最多 20 個，目前有 % 個', n; end if;

  -- 物種與性別的自訂值：一樣是公開欄位
  if public.looks_like_contact(coalesce(new.species,'')) or
     public.looks_like_contact(coalesce(new.gender,'')) then
    raise exception '物種與性別欄位不能填聯絡方式，那兩欄在佈告欄上是公開的。';
  end if;
  -- 自訂物種／性別限制長度並修掉換行（卡片版面靠它們排版）
  new.species := btrim(regexp_replace(coalesce(new.species,''), '[\s　]+', ' ', 'g'));
  new.gender  := btrim(regexp_replace(coalesce(new.gender,''),  '[\s　]+', ' ', 'g'));
  if char_length(new.species) > 12 then raise exception '物種請控制在 12 個字以內'; end if;
  if char_length(new.gender)  > 12 then raise exception '性別請控制在 12 個字以內'; end if;
  return new;
end $$;

-- 這個 trigger 要排在既有的權限 guard 之前跑（a_ 開頭），
-- 因為它會改寫 new，而權限 guard 只負責把受保護欄位還原，兩者互不干擾。
drop trigger if exists trg_a_profile_custom_text on public.match_profiles;
create trigger trg_a_profile_custom_text
  before insert or update on public.match_profiles
  for each row execute function public.guard_profile_custom_text();

-- 26.4 全站已經有人在用的自訂標籤 ------------------------------
--      讓後來的人可以直接勾，而不是每個人各自打一次「攝影」「登山」。
--      只回傳「有幾個人在用」達到門檻的，避免把某一個人獨有的標籤
--      端到所有人面前——那等於用標籤反向指認一個人。
create or replace function public.popular_custom_tags(p_field text, p_min_users int default 3)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare out_rows jsonb;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_field not in ('interests','personality') then raise exception '不支援的欄位'; end if;
  execute format($q$
    select coalesce(jsonb_agg(t order by n desc, t), '[]'::jsonb)
      from (select v as t, count(*) as n
              from public.match_profiles p,
                   lateral jsonb_array_elements_text(coalesce(p.%I,'[]'::jsonb)) v
             where p.account_status = 'active'
             group by v having count(*) >= $1) s
  $q$, p_field) into out_rows using greatest(p_min_users, 2);
  return out_rows;
end $$;
revoke all on function public.popular_custom_tags(text,int) from public, anon;
grant execute on function public.popular_custom_tags(text,int) to authenticated;

-- ============================================================
-- 27) 🌱 暖陽陪伴紀錄（第 1、2 步）：companion_links ＋ 對話書籤
--
--     規格見 docs/companion-journal-spec.md。這一節只做前兩步：
--     關係本身，以及聊天與陪伴紀錄之間的那座橋（🔖 記住這句）。
--
--     ── 三條寫死的產品規則 ──────────────────────────────────
--     (1) **不建立陪伴紀錄也能解鎖聯絡方式。** 配對功能在第三階段就完成了。
--         這裡沒有任何函式會擋住解鎖——放成條件的話，陪伴紀錄就從
--         「值得回來的理由」變成「不做就拿不到東西的關卡」。
--     (2) **使用者離開不算失敗。** 兩個人交換聯絡方式後再也沒登入，
--         可能代表暖陽已經完成它的工作。所以這裡沒有連續登入、沒有簽到、
--         沒有「你已經 N 天沒有記錄了」。看到有人想加那種東西，回來讀這一行。
--     (3) **不打分數。** 這一節不存任何關係評分，之後也不會加。
--
--     ── 規格第 7.1 節那個沒有答案的分岔（單方面可不可以建立）──
--     這裡的解法是把它拆成兩件事：
--       ・**共同的那本**（companion_links）要兩個人各自按下才成立，
--         跟 Consent Mode 同一個模式。一本關於兩個人的紀錄，不該由一個人
--         替兩個人決定；而且未經邀請的「某某想跟你建立陪伴紀錄」本身就是壓力。
--       ・**書籤是個人的，預設只有自己看得到。** 想留一句話不需要對方批准，
--         也不會通知對方。要分享再自己改成共同。
--     這樣就同時有了「回憶是自己的」跟「共同的東西要雙方同意」。
-- ============================================================

create table if not exists public.companion_links (
  id             uuid primary key default gen_random_uuid(),
  user_a         uuid not null references auth.users(id) on delete cascade,
  user_b         uuid not null references auth.users(id) on delete cascade,
  application_id uuid references public.applications(id) on delete set null,
  started_at     timestamptz not null default now(),
  status         text not null default 'pending',
  -- 關係結束之後的處置（規格第 6.1 節）：各自選各自的
  ended_at       timestamptz,
  purge_at       timestamptz,
  disposition_a  text,
  disposition_b  text,
  -- 誰按過「建立」。兩個都 true 才會變成 active。
  agreed_a       boolean not null default false,
  agreed_b       boolean not null default false,
  constraint companion_links_pair check (user_a < user_b)
);
-- 這些 check 獨立成 alter：之後加值時才會在既有資料庫上生效（見第 26 節的教訓）
alter table public.companion_links drop constraint if exists companion_links_status_check;
alter table public.companion_links add constraint companion_links_status_check
  check (status in ('pending','active','paused','ended'));
alter table public.companion_links drop constraint if exists companion_links_disp_a_check;
alter table public.companion_links add constraint companion_links_disp_a_check
  check (disposition_a is null or disposition_a in ('delete','archive','mine_only'));
alter table public.companion_links drop constraint if exists companion_links_disp_b_check;
alter table public.companion_links add constraint companion_links_disp_b_check
  check (disposition_b is null or disposition_b in ('delete','archive','mine_only'));
create unique index if not exists companion_links_pair_idx
  on public.companion_links(user_a, user_b);

alter table public.companion_links enable row level security;
drop policy if exists "companion_links_participant" on public.companion_links;
create policy "companion_links_participant" on public.companion_links
  for select to authenticated using (auth.uid() in (user_a, user_b));
grant select on public.companion_links to authenticated;

-- 27.1 對話書籤（🔖 記住這句）--------------------------------
--      四種：💛 喜歡的話／🌱 關係里程碑／📝 重要約定／🎁 想保存的回憶。
--      預設 private——收藏一句話是很個人的事，不該自動變成一個公開的表態。
create table if not exists public.message_bookmarks (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  message_id     bigint not null references public.match_messages(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  kind           text not null default 'love',
  note           text not null default '',
  visibility     text not null default 'private',
  created_at     timestamptz not null default now(),
  unique (message_id, user_id)
);
alter table public.message_bookmarks drop constraint if exists message_bookmarks_kind_check;
alter table public.message_bookmarks add constraint message_bookmarks_kind_check
  check (kind in ('love','milestone','promise','memory'));
alter table public.message_bookmarks drop constraint if exists message_bookmarks_vis_check;
alter table public.message_bookmarks add constraint message_bookmarks_vis_check
  check (visibility in ('private','both'));
create index if not exists message_bookmarks_app_idx
  on public.message_bookmarks(application_id, created_at desc);

alter table public.message_bookmarks enable row level security;
drop policy if exists "message_bookmarks_read" on public.message_bookmarks;
-- 自己的永遠讀得到；對方的只有他自己改成「共同」才讀得到
create policy "message_bookmarks_read" on public.message_bookmarks
  for select to authenticated using (
    user_id = auth.uid()
    or (visibility = 'both' and exists (
      select 1 from public.applications a
       where a.id = application_id and auth.uid() in (a.from_user, a.to_user))));
grant select on public.message_bookmarks to authenticated;

-- 27.2 收藏／取消收藏 ------------------------------------------
create or replace function public.toggle_message_bookmark(
  p_message_id bigint, p_kind text default 'love',
  p_note text default '', p_visibility text default 'private'
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_msg public.match_messages; v_app public.applications; v_existing public.message_bookmarks;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into v_msg from public.match_messages where id = p_message_id;
  if v_msg.id is null then raise exception '找不到這則訊息'; end if;
  select * into v_app from public.applications where id = v_msg.application_id;
  if auth.uid() not in (v_app.from_user, v_app.to_user) then
    raise exception '無權使用這個對話';
  end if;
  if p_kind not in ('love','milestone','promise','memory') then raise exception '不支援的書籤類型'; end if;
  if p_visibility not in ('private','both') then raise exception '不支援的可見範圍'; end if;

  select * into v_existing from public.message_bookmarks
   where message_id = p_message_id and user_id = auth.uid();

  if v_existing.id is not null then
    /* 同一種再按一次＝取消；換一種＝改類型。
       這樣一顆按鈕就夠了，不必為了取消再多一個垃圾桶。 */
    if v_existing.kind = p_kind and coalesce(p_note,'') = '' then
      delete from public.message_bookmarks where id = v_existing.id;
      return jsonb_build_object('state','removed');
    end if;
    update public.message_bookmarks
       set kind = p_kind, note = left(coalesce(p_note, note), 500), visibility = p_visibility
     where id = v_existing.id returning * into v_existing;
    return jsonb_build_object('state','updated','kind',v_existing.kind,
                              'visibility',v_existing.visibility,'note',v_existing.note);
  end if;

  insert into public.message_bookmarks(application_id, message_id, user_id, kind, note, visibility)
    values (v_msg.application_id, p_message_id, auth.uid(), p_kind,
            left(coalesce(p_note,''), 500), p_visibility)
    returning * into v_existing;
  return jsonb_build_object('state','added','kind',v_existing.kind,
                            'visibility',v_existing.visibility,'note',v_existing.note);
end $$;
revoke all on function public.toggle_message_bookmark(bigint,text,text,text) from public, anon;
grant execute on function public.toggle_message_bookmark(bigint,text,text,text) to authenticated;

-- 27.3 一段對話裡的書籤 ----------------------------------------
--      RLS 已經過濾過了，這裡拿到什麼就是該看到什麼。
create or replace function public.list_message_bookmarks(p_app_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_app public.applications; out_rows jsonb;
begin
  select * into v_app from public.applications where id = p_app_id;
  if v_app.id is null or auth.uid() not in (v_app.from_user, v_app.to_user) then
    raise exception '無權使用這個對話';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'message_id', b.message_id, 'kind', b.kind, 'note', b.note,
           'visibility', b.visibility, 'mine', b.user_id = auth.uid(),
           'created_at', b.created_at) order by b.created_at), '[]'::jsonb)
    into out_rows
    from public.message_bookmarks b
   where b.application_id = p_app_id
     and (b.user_id = auth.uid() or b.visibility = 'both');
  return out_rows;
end $$;
revoke all on function public.list_message_bookmarks(uuid) from public, anon;
grant execute on function public.list_message_bookmarks(uuid) to authenticated;

-- 27.4 建立／查詢陪伴紀錄 --------------------------------------
create or replace function public.companion_state(p_app_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_app public.applications; v_link public.companion_links; v_a uuid; v_b uuid; v_me_is_a boolean;
begin
  select * into v_app from public.applications where id = p_app_id;
  if v_app.id is null or auth.uid() not in (v_app.from_user, v_app.to_user) then
    raise exception '無權使用這份申請';
  end if;
  v_a := least(v_app.from_user, v_app.to_user);
  v_b := greatest(v_app.from_user, v_app.to_user);
  v_me_is_a := (auth.uid() = v_a);
  select * into v_link from public.companion_links where user_a = v_a and user_b = v_b;
  return jsonb_build_object(
    /* 有沒有資格建立：第三階段而且雙方都已經解鎖。
       注意這是「陪伴紀錄的資格」，不是解鎖的條件——解鎖不看這個。 */
    'eligible', (v_app.stage >= 3 and v_app.unlock_from and v_app.unlock_to),
    'exists',   v_link.id is not null,
    'status',   coalesce(v_link.status, 'none'),
    'mine',     coalesce(case when v_me_is_a then v_link.agreed_a else v_link.agreed_b end, false),
    'other',    coalesce(case when v_me_is_a then v_link.agreed_b else v_link.agreed_a end, false),
    'started_at', v_link.started_at,
    'days',     case when v_link.status = 'active'
                     then greatest(0, (current_date - v_link.started_at::date)) else null end,
    'link_id',  v_link.id);
end $$;
revoke all on function public.companion_state(uuid) from public, anon;
grant execute on function public.companion_state(uuid) to authenticated;

-- 各自表態。兩個人都按下才會變成 active。
create or replace function public.set_companion_agree(p_app_id uuid, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_app public.applications; v_a uuid; v_b uuid; v_me_is_a boolean; v_link public.companion_links;
begin
  select * into v_app from public.applications where id = p_app_id;
  if v_app.id is null or auth.uid() not in (v_app.from_user, v_app.to_user) then
    raise exception '無權使用這份申請';
  end if;
  if not (v_app.stage >= 3 and v_app.unlock_from and v_app.unlock_to) then
    raise exception '要雙方都完成第三階段解鎖之後才能建立陪伴紀錄';
  end if;
  v_a := least(v_app.from_user, v_app.to_user);
  v_b := greatest(v_app.from_user, v_app.to_user);
  v_me_is_a := (auth.uid() = v_a);

  insert into public.companion_links(user_a, user_b, application_id, status)
    values (v_a, v_b, p_app_id, 'pending')
    on conflict (user_a, user_b) do nothing;
  select * into v_link from public.companion_links where user_a = v_a and user_b = v_b;

  /* 只動自己那一格。替對方按下同意是最不能允許的事——
     這跟第 24 節 Consent Mode 是同一條規則。 */
  if v_me_is_a then update public.companion_links set agreed_a = p_on where id = v_link.id;
  else               update public.companion_links set agreed_b = p_on where id = v_link.id; end if;

  /* started_at 只在「第一次成立」時寫進去。
     暫停之後再回來不重算——把「你們的陪伴紀錄從 X 開始」洗掉，
     等於把暫停講成一次失敗，而規則 (2) 就是為了不要那樣。 */
  update public.companion_links
     set status = case when agreed_a and agreed_b then 'active'
                       when status = 'active' then 'paused' else status end,
         started_at = case when agreed_a and agreed_b and status = 'pending'
                           then now() else started_at end
   where id = v_link.id;

  return public.companion_state(p_app_id);
end $$;
revoke all on function public.set_companion_agree(uuid, boolean) from public, anon;
grant execute on function public.set_companion_agree(uuid, boolean) to authenticated;

-- ============================================================
-- 28) 🌱 陪伴紀錄第 3、4 步：回憶、里程碑、共同目標
--
--     規格見 docs/companion-journal-spec.md 第 2 節與第 8 節。
--
--     ── 這一節新加的一條規則：暫停之後是唯讀，但自己的筆記還能寫 ──
--     status 有三種寫入權限：
--       ・active  → 都可以寫
--       ・paused  → 只能新增「只有我看得到」的回憶。
--                   共同的東西（共同的回憶、里程碑、目標）不能再動——
--                   有一方已經撤回同意了，繼續往共同的那本寫等於當作沒看到。
--                   但也不能因此把人鎖在自己的筆記外面：那本來就是他自己的。
--       ・ended   → 全部唯讀，等 6.1 的處置。
--
--     ── 里程碑刻意不排順序 ──
--     沒有進度條、沒有「你們完成了 3/8 個里程碑」。預設清單只是提示詞，
--     真正要用的是 custom。關係不是一條大家都該照走的階梯。
-- ============================================================

-- 28.1 誰能寫、能寫什麼 ----------------------------------------
create or replace function public.companion_link_for(p_link_id uuid)
returns public.companion_links language plpgsql stable security definer
set search_path = public, pg_temp as $$
declare v public.companion_links;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into v from public.companion_links where id = p_link_id;
  if v.id is null or auth.uid() not in (v.user_a, v.user_b) then
    raise exception '無權使用這本陪伴紀錄';
  end if;
  return v;
end $$;

-- p_shared = true 代表要寫的是「共同的那本」
create or replace function public.companion_assert_writable(p_link public.companion_links,
                                                            p_shared boolean)
returns void language plpgsql immutable as $$
begin
  if p_link.status = 'ended' then
    raise exception '這本陪伴紀錄已經結束，只能閱讀';
  end if;
  if p_shared and p_link.status <> 'active' then
    raise exception '陪伴紀錄目前暫停中，只能新增「只有我看得到」的內容';
  end if;
end $$;

-- 28.2 回憶 ----------------------------------------------------
create table if not exists public.companion_memories (
  id         uuid primary key default gen_random_uuid(),
  link_id    uuid not null references public.companion_links(id) on delete cascade,
  at         date not null default current_date,
  type       text not null default 'moment',
  title      text not null default '',
  body       text not null default '',
  -- 照片先留欄位不開放：私密 bucket 與清理政策還沒決定（規格第 7 節第 2 題）
  photo_path text,
  created_by uuid not null references auth.users(id) on delete cascade,
  visibility text not null default 'both',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.companion_memories drop constraint if exists companion_memories_type_check;
alter table public.companion_memories add constraint companion_memories_type_check
  check (type in ('moment','together','words','feeling','other'));
alter table public.companion_memories drop constraint if exists companion_memories_vis_check;
alter table public.companion_memories add constraint companion_memories_vis_check
  check (visibility in ('both','private'));
create index if not exists companion_memories_link_idx
  on public.companion_memories(link_id, at desc, created_at desc);

alter table public.companion_memories enable row level security;
drop policy if exists "companion_memories_read" on public.companion_memories;
create policy "companion_memories_read" on public.companion_memories
  for select to authenticated using (
    created_by = auth.uid()
    or (visibility = 'both' and exists (
      select 1 from public.companion_links l
       where l.id = link_id and auth.uid() in (l.user_a, l.user_b))));
grant select on public.companion_memories to authenticated;

-- 28.3 里程碑 --------------------------------------------------
create table if not exists public.companion_milestones (
  id         uuid primary key default gen_random_uuid(),
  link_id    uuid not null references public.companion_links(id) on delete cascade,
  milestone_type text not null default 'custom',
  at         date not null default current_date,
  note       text not null default '',
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.companion_milestones drop constraint if exists companion_milestones_type_check;
alter table public.companion_milestones add constraint companion_milestones_type_check
  check (milestone_type in ('first_meet','first_trip','met_family','moved_in',
                            'anniversary','made_up','custom'));
create index if not exists companion_milestones_link_idx
  on public.companion_milestones(link_id, at desc);

alter table public.companion_milestones enable row level security;
drop policy if exists "companion_milestones_read" on public.companion_milestones;
create policy "companion_milestones_read" on public.companion_milestones
  for select to authenticated using (exists (
    select 1 from public.companion_links l
     where l.id = link_id and auth.uid() in (l.user_a, l.user_b)));
grant select on public.companion_milestones to authenticated;

-- 28.4 共同目標 ------------------------------------------------
--      status 一定要有 paused：只給「未開始／進行中／完成」，
--      「這件事我們現在不想推」就只能留在「未開始」裡看起來像拖延。
--      關係不是專案管理。
create table if not exists public.companion_goals (
  id         uuid primary key default gen_random_uuid(),
  link_id    uuid not null references public.companion_links(id) on delete cascade,
  title      text not null,
  category   text not null default 'other',
  status     text not null default 'idle',
  created_by uuid not null references auth.users(id) on delete cascade,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.companion_goals drop constraint if exists companion_goals_status_check;
alter table public.companion_goals add constraint companion_goals_status_check
  check (status in ('idle','doing','done','paused'));
alter table public.companion_goals drop constraint if exists companion_goals_cat_check;
alter table public.companion_goals add constraint companion_goals_cat_check
  check (category in ('travel','money','home','health','family','learn','other'));
create index if not exists companion_goals_link_idx on public.companion_goals(link_id, created_at);

alter table public.companion_goals enable row level security;
drop policy if exists "companion_goals_read" on public.companion_goals;
create policy "companion_goals_read" on public.companion_goals
  for select to authenticated using (exists (
    select 1 from public.companion_links l
     where l.id = link_id and auth.uid() in (l.user_a, l.user_b)));
grant select on public.companion_goals to authenticated;

-- 28.5 寫入的 RPC ----------------------------------------------
create or replace function public.add_companion_memory(
  p_link_id uuid, p_title text, p_body text default '',
  p_type text default 'moment', p_at date default null,
  p_visibility text default 'both'
) returns public.companion_memories
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v public.companion_memories;
begin
  v_link := public.companion_link_for(p_link_id);
  perform public.companion_assert_writable(v_link, p_visibility = 'both');
  if btrim(coalesce(p_title,'')) = '' and btrim(coalesce(p_body,'')) = '' then
    raise exception '寫一點東西再儲存吧';
  end if;
  insert into public.companion_memories(link_id, at, type, title, body, created_by, visibility)
    values (p_link_id, coalesce(p_at, current_date), coalesce(p_type,'moment'),
            left(btrim(coalesce(p_title,'')), 80), left(coalesce(p_body,''), 4000),
            auth.uid(), coalesce(p_visibility,'both'))
    returning * into v;
  return v;
end $$;
revoke all on function public.add_companion_memory(uuid,text,text,text,date,text) from public, anon;
grant execute on function public.add_companion_memory(uuid,text,text,text,date,text) to authenticated;

/* 只有作者能改、能刪自己寫的。
   共同不等於可以替對方修改他寫下的東西——那是改寫別人的記憶。 */
create or replace function public.update_companion_memory(
  p_id uuid, p_title text default null, p_body text default null,
  p_visibility text default null
) returns public.companion_memories
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.companion_memories; v_link public.companion_links;
begin
  select * into v from public.companion_memories where id = p_id;
  if v.id is null then raise exception '找不到這則回憶'; end if;
  if v.created_by <> auth.uid() then raise exception '只有寫下它的人可以修改'; end if;
  v_link := public.companion_link_for(v.link_id);
  perform public.companion_assert_writable(v_link,
    coalesce(p_visibility, v.visibility) = 'both');
  update public.companion_memories
     set title = left(coalesce(p_title, title), 80),
         body = left(coalesce(p_body, body), 4000),
         visibility = coalesce(p_visibility, visibility),
         updated_at = now()
   where id = p_id returning * into v;
  return v;
end $$;
revoke all on function public.update_companion_memory(uuid,text,text,text) from public, anon;
grant execute on function public.update_companion_memory(uuid,text,text,text) to authenticated;

create or replace function public.delete_companion_memory(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.companion_memories;
begin
  select * into v from public.companion_memories where id = p_id;
  if v.id is null then raise exception '找不到這則回憶'; end if;
  if v.created_by <> auth.uid() then raise exception '只有寫下它的人可以刪除'; end if;
  perform public.companion_link_for(v.link_id);
  delete from public.companion_memories where id = p_id;
end $$;
revoke all on function public.delete_companion_memory(uuid) from public, anon;
grant execute on function public.delete_companion_memory(uuid) to authenticated;

create or replace function public.add_companion_milestone(
  p_link_id uuid, p_milestone_type text default 'custom',
  p_note text default '', p_at date default null
) returns public.companion_milestones
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v public.companion_milestones;
begin
  v_link := public.companion_link_for(p_link_id);
  perform public.companion_assert_writable(v_link, true);
  insert into public.companion_milestones(link_id, milestone_type, at, note, created_by)
    values (p_link_id, coalesce(p_milestone_type,'custom'), coalesce(p_at, current_date),
            left(coalesce(p_note,''), 200), auth.uid())
    returning * into v;
  return v;
end $$;
revoke all on function public.add_companion_milestone(uuid,text,text,date) from public, anon;
grant execute on function public.add_companion_milestone(uuid,text,text,date) to authenticated;

create or replace function public.delete_companion_milestone(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.companion_milestones;
begin
  select * into v from public.companion_milestones where id = p_id;
  if v.id is null then raise exception '找不到這個里程碑'; end if;
  if v.created_by <> auth.uid() then raise exception '只有記下它的人可以刪除'; end if;
  perform public.companion_link_for(v.link_id);
  delete from public.companion_milestones where id = p_id;
end $$;
revoke all on function public.delete_companion_milestone(uuid) from public, anon;
grant execute on function public.delete_companion_milestone(uuid) to authenticated;

create or replace function public.add_companion_goal(
  p_link_id uuid, p_title text, p_category text default 'other'
) returns public.companion_goals
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v public.companion_goals;
begin
  v_link := public.companion_link_for(p_link_id);
  perform public.companion_assert_writable(v_link, true);
  if btrim(coalesce(p_title,'')) = '' then raise exception '目標要有一個名字'; end if;
  insert into public.companion_goals(link_id, title, category, created_by)
    values (p_link_id, left(btrim(p_title), 80), coalesce(p_category,'other'), auth.uid())
    returning * into v;
  return v;
end $$;
revoke all on function public.add_companion_goal(uuid,text,text) from public, anon;
grant execute on function public.add_companion_goal(uuid,text,text) to authenticated;

/* 狀態兩個人都能改——「我們現在不想推這件事」不該只有提出的人可以說。
   刪除仍然只有作者：那是把別人提過的事整個抹掉。 */
create or replace function public.set_companion_goal_status(p_id uuid, p_status text)
returns public.companion_goals
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.companion_goals; v_link public.companion_links;
begin
  select * into v from public.companion_goals where id = p_id;
  if v.id is null then raise exception '找不到這個目標'; end if;
  v_link := public.companion_link_for(v.link_id);
  perform public.companion_assert_writable(v_link, true);
  if p_status not in ('idle','doing','done','paused') then raise exception '不支援的狀態'; end if;
  update public.companion_goals
     set status = p_status,
         completed_at = case when p_status = 'done' then now() else null end
   where id = p_id returning * into v;
  return v;
end $$;
revoke all on function public.set_companion_goal_status(uuid,text) from public, anon;
grant execute on function public.set_companion_goal_status(uuid,text) to authenticated;

create or replace function public.delete_companion_goal(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.companion_goals;
begin
  select * into v from public.companion_goals where id = p_id;
  if v.id is null then raise exception '找不到這個目標'; end if;
  if v.created_by <> auth.uid() then raise exception '只有提出它的人可以刪除'; end if;
  perform public.companion_link_for(v.link_id);
  delete from public.companion_goals where id = p_id;
end $$;
revoke all on function public.delete_companion_goal(uuid) from public, anon;
grant execute on function public.delete_companion_goal(uuid) to authenticated;

-- 28.6 時間線 --------------------------------------------------
--      回憶、里程碑，以及第 27 節的對話書籤合在一起，照日期排。
--      書籤本來就是「聊天與陪伴紀錄之間的橋」，所以它們是時間線的第一批內容。
create or replace function public.companion_timeline(p_link_id uuid, p_limit int default 200)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; out_rows jsonb;
begin
  v_link := public.companion_link_for(p_link_id);
  select coalesce(jsonb_agg(x order by x->>'at' desc, x->>'created_at' desc), '[]'::jsonb)
    into out_rows
    from (
      select jsonb_build_object(
        'kind','memory', 'id', m.id, 'at', m.at, 'type', m.type,
        'title', m.title, 'body', m.body, 'visibility', m.visibility,
        'mine', m.created_by = auth.uid(), 'created_at', m.created_at) as x
        from public.companion_memories m
       where m.link_id = p_link_id
         and (m.created_by = auth.uid() or m.visibility = 'both')
      union all
      select jsonb_build_object(
        'kind','milestone', 'id', s.id, 'at', s.at, 'type', s.milestone_type,
        'title', '', 'body', s.note, 'visibility', 'both',
        'mine', s.created_by = auth.uid(), 'created_at', s.created_at)
        from public.companion_milestones s
       where s.link_id = p_link_id
      union all
      /* 書籤掛在申請上，不是掛在 link 上——同一對人可能只有一段對話，
         但要用 link 的兩個人去對應，不能直接信 application_id。 */
      select jsonb_build_object(
        'kind','bookmark', 'id', b.id, 'at', b.created_at::date, 'type', b.kind,
        'title', left(msg.body, 80), 'body', b.note, 'visibility', b.visibility,
        'mine', b.user_id = auth.uid(), 'created_at', b.created_at)
        from public.message_bookmarks b
        join public.match_messages msg on msg.id = b.message_id
        join public.applications a on a.id = b.application_id
       where least(a.from_user, a.to_user) = v_link.user_a
         and greatest(a.from_user, a.to_user) = v_link.user_b
         and (b.user_id = auth.uid() or b.visibility = 'both')
    ) s
   limit greatest(1, least(p_limit, 500));
  return out_rows;
end $$;
revoke all on function public.companion_timeline(uuid,int) from public, anon;
grant execute on function public.companion_timeline(uuid,int) to authenticated;

create or replace function public.companion_goals_list(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public.companion_link_for(p_link_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', g.id, 'title', g.title, 'category', g.category, 'status', g.status,
            'mine', g.created_by = auth.uid(), 'completed_at', g.completed_at,
            'created_at', g.created_at) order by g.created_at), '[]'::jsonb)
            from public.companion_goals g where g.link_id = p_link_id);
end $$;
revoke all on function public.companion_goals_list(uuid) from public, anon;
grant execute on function public.companion_goals_list(uuid) to authenticated;

-- ============================================================
-- 29) 🌱 陪伴紀錄第 5 步：關係健康檢查（規格第 4 節）
--
--     ── 兩個人的答案不會自動互通 ──────────────────────────
--     A 填「最近覺得孤單」，系統**不會**通知 B「你的伴侶說跟你交往很孤單」。
--     那只會直接製造一場架，而且會讓人下次不敢誠實填。
--     所以 share_with_partner 預設 false，而且共同觀察**只在兩邊都選擇分享時**
--     才產生，措辭固定是並列描述（「你們最近都覺得工作比較忙」），
--     不是轉述指控。
--
--     ── 不輸出分數 ────────────────────────────────────────
--     沒有 Relationship Health Score。理由跟第 22 節把 vet_scores 整欄刪掉一樣：
--     沒有校準基礎的數字會被當成結論。
--     選項刻意用文字而不是 1～5——數字放在那裡遲早會有人把它加起來。
--
--     ── 不做每 N 天強迫填的問卷 ────────────────────────────
--     每月最多一次，完全選填，而且系統不主動狂推。
-- ============================================================

-- 29.1 題目：前後端共用同一份 ----------------------------------
create or replace function public.checkin_questions()
returns jsonb language sql immutable as $$
  select '[
    {"key":"connected","label":"最近跟對方的距離",
     "options":["更靠近了","跟之前差不多","有點遠"],"multi":false},
    {"key":"heard","label":"最近說的話有沒有被聽見",
     "options":["大多有","有時候有","不太有"],"multi":false},
    {"key":"time","label":"最近相處的時間",
     "options":["剛好","有點少","太少","太多了想要一點自己的時間"],"multi":false},
    {"key":"stress","label":"最近的壓力主要來自哪裡",
     "options":["工作","家人","金錢","健康","關係本身","說不上來"],"multi":true},
    {"key":"want_more","label":"最近想要多一點的是",
     "options":["一起做的事","自己的時間","被問候","被理解","說不上來"],"multi":true},
    {"key":"note","label":"想補一句話","options":[],"multi":false,"free":true}
  ]'::jsonb
$$;
grant execute on function public.checkin_questions() to authenticated, anon;

create table if not exists public.relationship_checkins (
  id         uuid primary key default gen_random_uuid(),
  link_id    uuid not null references public.companion_links(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  answers    jsonb not null default '{}'::jsonb,
  -- 預設 false，見規格第 4 節。這個預設值本身就是那條規則。
  share_with_partner boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists relationship_checkins_link_idx
  on public.relationship_checkins(link_id, created_at desc);

alter table public.relationship_checkins enable row level security;
drop policy if exists "relationship_checkins_read" on public.relationship_checkins;
-- 自己的永遠讀得到；對方的只有他自己選擇分享時才讀得到
create policy "relationship_checkins_read" on public.relationship_checkins
  for select to authenticated using (
    user_id = auth.uid()
    or (share_with_partner and exists (
      select 1 from public.companion_links l
       where l.id = link_id and auth.uid() in (l.user_a, l.user_b))));
grant select on public.relationship_checkins to authenticated;

-- 29.2 填一次 --------------------------------------------------
create or replace function public.submit_checkin(
  p_link_id uuid, p_answers jsonb, p_share boolean default false
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_last timestamptz; v_id uuid; v_keys text[];
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status = 'ended' then raise exception '這本陪伴紀錄已經結束，只能閱讀'; end if;

  select max(created_at) into v_last from public.relationship_checkins
   where link_id = p_link_id and user_id = auth.uid();
  /* 每月最多一次。這個上限的用途是**擋住系統自己**——
     一旦可以天天填，畫面上遲早會長出「你已經 5 天沒有回診了」。 */
  if v_last is not null and v_last > now() - interval '30 days' then
    raise exception '關係健康檢查每 30 天最多一次，下一次可以在 % 之後',
      to_char(v_last + interval '30 days', 'YYYY-MM-DD');
  end if;

  if jsonb_typeof(coalesce(p_answers,'{}'::jsonb)) <> 'object' then
    raise exception '答案格式不正確';
  end if;
  -- 只收題目表裡有的 key，別的丟掉（這張表會被 AI 讀，不能變成任意欄位的倉庫）
  select array_agg(q->>'key') into v_keys from jsonb_array_elements(public.checkin_questions()) q;
  insert into public.relationship_checkins(link_id, user_id, answers, share_with_partner)
    values (p_link_id, auth.uid(),
            (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
               from jsonb_each(coalesce(p_answers,'{}'::jsonb)) as t(k, v)
              where k = any(v_keys)),
            coalesce(p_share, false))
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'shared', coalesce(p_share,false));
end $$;
revoke all on function public.submit_checkin(uuid,jsonb,boolean) from public, anon;
grant execute on function public.submit_checkin(uuid,jsonb,boolean) to authenticated;

/* 分享是可以反悔的：填的時候沒想分享，後來想分享；或反過來。
   只動自己那一列。 */
create or replace function public.set_checkin_share(p_id uuid, p_share boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.relationship_checkins;
begin
  select * into v from public.relationship_checkins where id = p_id;
  if v.id is null or v.user_id <> auth.uid() then raise exception '只有本人可以改自己的回診紀錄'; end if;
  update public.relationship_checkins set share_with_partner = coalesce(p_share,false)
   where id = p_id returning * into v;
  return jsonb_build_object('id', v.id, 'shared', v.share_with_partner);
end $$;
revoke all on function public.set_checkin_share(uuid,boolean) from public, anon;
grant execute on function public.set_checkin_share(uuid,boolean) to authenticated;

-- 29.3 本次回診摘要 --------------------------------------------
--      沒有分數。輸出的是「狀態」與「一個可以談的方向」。
create or replace function public.checkin_summary(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_link public.companion_links; v_other uuid;
  v_mine public.relationship_checkins; v_theirs public.relationship_checkins;
  v_both jsonb := '[]'::jsonb; v_next text := null; q jsonb; k text;
begin
  v_link := public.companion_link_for(p_link_id);
  v_other := case when auth.uid() = v_link.user_a then v_link.user_b else v_link.user_a end;

  select * into v_mine from public.relationship_checkins
   where link_id = p_link_id and user_id = auth.uid()
   order by created_at desc limit 1;

  /* 對方那一份只有在他自己選擇分享時才拿得到——
     而且就算拿到了，也只能拿來做並列描述。 */
  select * into v_theirs from public.relationship_checkins
   where link_id = p_link_id and user_id = v_other and share_with_partner
   order by created_at desc limit 1;

  if v_mine.id is not null and v_theirs.id is not null and v_mine.share_with_partner then
    for q in select * from jsonb_array_elements(public.checkin_questions()) loop
      k := q->>'key';
      if k <> 'note' and v_mine.answers ? k and v_theirs.answers ? k then
        if (q->>'multi')::boolean then
          -- 兩個人都勾到的那幾項才算共同
          v_both := v_both || (
            select coalesce(jsonb_agg(jsonb_build_object('key', k, 'label', q->>'label', 'value', e)), '[]'::jsonb)
              from jsonb_array_elements_text(v_mine.answers->k) e
             where v_theirs.answers->k ? e);
        elsif v_mine.answers->>k = v_theirs.answers->>k then
          v_both := v_both || jsonb_build_array(
            jsonb_build_object('key', k, 'label', q->>'label', 'value', v_mine.answers->>k));
        end if;
      end if;
    end loop;
  end if;

  -- 「一個可以談的方向」——一次只給一個，而且是問句，不是指令
  if v_mine.id is not null then
    if v_mine.answers->>'time' in ('有點少','太少') then
      v_next := '要不要找一個時間，聊聊最近各自的時間都花在哪裡？';
    elsif v_mine.answers->>'heard' = '不太有' then
      v_next := '有沒有一件最近想說、但還沒說出口的事？';
    elsif v_mine.answers->>'connected' = '有點遠' then
      v_next := '最近有什麼事情，是你希望對方知道的？';
    elsif v_mine.answers ? 'want_more' then
      v_next := '你最近想要多一點的那件事，對方知道嗎？';
    end if;
  end if;

  return jsonb_build_object(
    'has_mine',   v_mine.id is not null,
    'mine',       coalesce(v_mine.answers, '{}'::jsonb),
    'mine_at',    v_mine.created_at,
    'mine_shared', coalesce(v_mine.share_with_partner, false),
    'mine_id',    v_mine.id,
    /* 對方填了但沒分享時，這裡只會是 false，不會透露「他填了但不給你看」——
       那句話本身就是一個指控。 */
    'both_shared', (v_theirs.id is not null and coalesce(v_mine.share_with_partner,false)),
    'shared_observations', v_both,
    'next_question', v_next,
    'can_submit_after', (select max(created_at) + interval '30 days'
                           from public.relationship_checkins
                          where link_id = p_link_id and user_id = auth.uid()));
end $$;
revoke all on function public.checkin_summary(uuid) from public, anon;
grant execute on function public.checkin_summary(uuid) to authenticated;

-- ============================================================
-- 30) 🌱 陪伴紀錄第 6、7 步：診療室的讀取權限與診療紀錄（規格第 3、5 節）
--
--     第 6 步一定要排在第 7 步之前，不然預設就會變成全開。
--
--     ── 三條硬規定（規格第 3 節）──────────────────────────
--     (1) **預設全部 false。** 進診療室不會自動把所有歷史翻出來。
--         每一次要讀什麼，都是使用者當下勾的。
--     (2) **對話只能整段授權、不能整本授權，而且是一次性的。**
--         所以這裡**沒有** allow_chat_range 這個欄位。
--         規格原本寫了一個，但一個叫 allow_* 的欄位存在資料庫裡，
--         遲早會有人把它當成常設開關來讀——那正好違反「一次性」。
--         改成 last_chat_days：只記上一次勾了幾天，純粹拿來預填畫面，
--         build_clinic_context() 從頭到尾不看它。
--     (3) **共同關係分析要雙方同意；只幫一個人整理感受則不需要。**
--         界線是輸出裡有沒有對另一個人的判斷。
--
--     由 (3) 再推出一條規格沒寫、但不補上就會破功的規則：
--     **對話只能在 joint 模式、而且兩個人都同意時才進得了 AI 的輸入。**
--     對話裡有對方說的話。solo 模式說好了「只讀使用者自己給的片段」，
--     那就不能從後門把整段對話撈進去。
--
--     ── 診療室不判誰有理（規格第 5 節）────────────────────
--     輸出固定四段：事實／感受／需求／下一個問題。
--     唯一的例外是安全：輸入若涉及人身安全，離開關係協調模式，
--     切換成安全模式，而且**不能**回答「你們可以試著理解彼此的需求」——
--     在有人身安全疑慮的情境裡，「各退一步」會把責任推回受害的一方。
-- ============================================================

create table if not exists public.clinic_context_permissions (
  link_id     uuid not null references public.companion_links(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  allow_profile      boolean not null default false,
  allow_dealbreakers boolean not null default false,
  allow_stage2       boolean not null default false,
  allow_checkins     boolean not null default false,
  allow_sessions     boolean not null default false,
  allow_goals        boolean not null default false,
  allow_joint        boolean not null default false,
  -- 上一次勾了幾天，只拿來預填畫面。不是權限，沒有任何地方把它當權限讀。
  last_chat_days     int not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (link_id, user_id)
);
alter table public.clinic_context_permissions enable row level security;
drop policy if exists "clinic_perm_own" on public.clinic_context_permissions;
create policy "clinic_perm_own" on public.clinic_context_permissions
  for select to authenticated using (user_id = auth.uid());
grant select on public.clinic_context_permissions to authenticated;

create table if not exists public.clinic_sessions (
  id         uuid primary key default gen_random_uuid(),
  link_id    uuid not null references public.companion_links(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  mode       text not null default 'solo',
  topic      text not null default '',
  input      text not null default '',
  ai_summary jsonb,
  followup   jsonb,
  safety_mode boolean not null default false,
  saved      boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.clinic_sessions drop constraint if exists clinic_sessions_mode_check;
alter table public.clinic_sessions add constraint clinic_sessions_mode_check
  check (mode in ('solo','joint'));
create index if not exists clinic_sessions_link_idx
  on public.clinic_sessions(link_id, created_at desc);

alter table public.clinic_sessions enable row level security;
drop policy if exists "clinic_sessions_own" on public.clinic_sessions;
/* 診療紀錄只有本人讀得到，joint 也一樣。
   joint 指的是「輸出可以談到兩個人」，不是「對方可以翻我的診療紀錄」。 */
create policy "clinic_sessions_own" on public.clinic_sessions
  for select to authenticated using (user_id = auth.uid());
grant select on public.clinic_sessions to authenticated;

-- 30.1 權限：讀與寫 --------------------------------------------
create or replace function public.clinic_permissions(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v public.clinic_context_permissions; v_other_joint boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  select * into v from public.clinic_context_permissions
   where link_id = p_link_id and user_id = auth.uid();
  select coalesce(bool_or(allow_joint), false) into v_other_joint
    from public.clinic_context_permissions
   where link_id = p_link_id and user_id <> auth.uid();
  return jsonb_build_object(
    'allow_profile',      coalesce(v.allow_profile, false),
    'allow_dealbreakers', coalesce(v.allow_dealbreakers, false),
    'allow_stage2',       coalesce(v.allow_stage2, false),
    'allow_checkins',     coalesce(v.allow_checkins, false),
    'allow_sessions',     coalesce(v.allow_sessions, false),
    'allow_goals',        coalesce(v.allow_goals, false),
    'allow_joint',        coalesce(v.allow_joint, false),
    'other_allow_joint',  v_other_joint,
    'last_chat_days',     coalesce(v.last_chat_days, 0));
end $$;
revoke all on function public.clinic_permissions(uuid) from public, anon;
grant execute on function public.clinic_permissions(uuid) to authenticated;

create or replace function public.set_clinic_permission(p_link_id uuid, p_key text, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.companion_link_for(p_link_id);
  if p_key not in ('allow_profile','allow_dealbreakers','allow_stage2',
                   'allow_checkins','allow_sessions','allow_goals','allow_joint') then
    raise exception '不支援的授權項目';
  end if;
  insert into public.clinic_context_permissions(link_id, user_id)
    values (p_link_id, auth.uid()) on conflict (link_id, user_id) do nothing;
  -- 只動自己那一列，而且一次只動一格
  execute format('update public.clinic_context_permissions set %I = $1, updated_at = now()
                   where link_id = $2 and user_id = $3', p_key)
    using coalesce(p_on,false), p_link_id, auth.uid();
  return public.clinic_permissions(p_link_id);
end $$;
revoke all on function public.set_clinic_permission(uuid,text,boolean) from public, anon;
grant execute on function public.set_clinic_permission(uuid,text,boolean) to authenticated;

-- 30.2 安全模式的判定 ------------------------------------------
--      直接接第 24 節的 chat_safety_level()，不另外寫一套。
--      兩邊用同一組偵測，才不會「對話室亮紅燈、診療室卻繼續勸和」。
--
--      但診療室多了一種第 24 節抓不到、而且規格點名的情境：
--      **「他打我，但我不知道是不是我先惹他生氣」**。
--      對話室的偵測看的是「有人在對另一個人要求或威脅」，
--      這一句沒有威脅任何人，它是受害者在轉述發生在自己身上的事。
--      所以另外開一類 reported_harm，只給診療室與意見回饋用——
--      在對話室裡命中的會是受害者自己那則訊息，替受害者的訊息標紅燈是最糟的結果。
--
--      跟第 25 節的 reported 分開，是為了不要把「他逼我太緊」這種
--      關係壓力也推進安全模式：那會讓人不敢談日常的拉扯。
alter table public.chat_safety_signals drop constraint if exists chat_safety_signals_class_check;
alter table public.chat_safety_signals add constraint chat_safety_signals_class_check
  check (class in ('sexual','body_topic','threat','threat_harm','coercion',
                   'intimate_image','request','selfref','refusal','reported','reported_harm'));
insert into public.chat_safety_signals (code, class, pattern, note) values
  ('P_HIT','reported_harm',
   '(他|她|對方|男友|女友|老公|老婆|伴侶|前任).{0,6}(打我|動手|推我|掐我|踹我|摔我|勒我|扯我頭髮)',
   '轉述對方對自己的肢體暴力'),
  ('P_FORCE','reported_harm',
   '被(他|她|對方|男友|女友|老公|老婆|伴侶).{0,8}(強迫|性侵|限制行動|不准出門|不讓我走|跟蹤)',
   '轉述強迫或控制人身自由')
on conflict (code) do update set
  class = excluded.class, pattern = excluded.pattern,
  note = excluded.note, enabled = excluded.enabled;

create or replace function public.clinic_safety_mode(p_input text)
returns jsonb language plpgsql stable set search_path = public, pg_temp as $$
declare v jsonb; cls text[]; harm boolean;
begin
  v   := public.chat_safety_level(coalesce(p_input,''), false, false);
  cls := public.chat_signal_classes(coalesce(p_input,''));
  harm := 'reported_harm' = any(cls);
  return jsonb_build_object(
    /* coalesce 是必要的：沒有任何訊號時 level 是 null，
       而 null = 'danger' 的結果是 null，不是 false——
       前端拿到 null 會當成「還沒判斷」而不是「安全」。 */
    'safety', coalesce(v->>'level','') = 'danger' or harm,
    'level',  coalesce(v->>'level', case when harm then 'danger' else null end),
    'code',   coalesce(v->>'code', case when harm then 'P_REPORTED_HARM' else null end));
end $$;
grant execute on function public.clinic_safety_mode(text) to authenticated;

-- 30.3 組出這一次可以給 AI 看的東西 ----------------------------
-- 這支不是 stable：它會把「這一次讀了幾天對話」記回去（純粹拿來預填畫面）。
create or replace function public.build_clinic_context(
  p_link_id uuid, p_mode text default 'solo', p_chat_days int default 0
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_link public.companion_links; v_perm jsonb; v_other uuid;
  ctx jsonb := '{}'::jsonb; v_days int; v_app uuid;
begin
  v_link := public.companion_link_for(p_link_id);
  v_perm := public.clinic_permissions(p_link_id);
  v_other := case when auth.uid() = v_link.user_a then v_link.user_b else v_link.user_a end;
  if p_mode not in ('solo','joint') then raise exception '不支援的模式'; end if;

  /* 共同關係分析要雙方同意。單方面把一段關係交給 AI 分析，
     等於替另一個人決定他要不要被分析。 */
  if p_mode = 'joint' and not ((v_perm->>'allow_joint')::boolean
                               and (v_perm->>'other_allow_joint')::boolean) then
    raise exception '共同關係分析要兩個人都同意才能開始';
  end if;

  if (v_perm->>'allow_profile')::boolean then
    ctx := ctx || jsonb_build_object('profile', (
      select jsonb_build_object('name', p.name, 'bio', p.bio,
                                'interests', p.interests, 'personality', p.personality)
        from public.match_profiles p where p.id = auth.uid()));
  end if;
  if (v_perm->>'allow_dealbreakers')::boolean then
    ctx := ctx || jsonb_build_object('dealbreakers', (
      select coalesce(p.dealbreakers, '{}'::jsonb) from public.match_profiles p where p.id = auth.uid()));
  end if;
  if (v_perm->>'allow_stage2')::boolean then
    ctx := ctx || jsonb_build_object('stage2', (
      select coalesce(jsonb_agg(a.application_answers), '[]'::jsonb)
        from public.applications a
       where least(a.from_user,a.to_user) = v_link.user_a
         and greatest(a.from_user,a.to_user) = v_link.user_b));
  end if;
  if (v_perm->>'allow_checkins')::boolean then
    ctx := ctx || jsonb_build_object('checkins', (
      select coalesce(jsonb_agg(jsonb_build_object('at', c.created_at, 'answers', c.answers)
                                order by c.created_at desc), '[]'::jsonb)
        from public.relationship_checkins c
       where c.link_id = p_link_id and c.user_id = auth.uid()));
  end if;
  if (v_perm->>'allow_goals')::boolean then
    ctx := ctx || jsonb_build_object('goals', public.companion_goals_list(p_link_id));
  end if;
  if (v_perm->>'allow_sessions')::boolean then
    ctx := ctx || jsonb_build_object('past_sessions', (
      select coalesce(jsonb_agg(jsonb_build_object('at', s.created_at, 'topic', s.topic,
                                                   'summary', s.ai_summary)
                                order by s.created_at desc), '[]'::jsonb)
        from (select * from public.clinic_sessions
               where link_id = p_link_id and user_id = auth.uid()
               order by created_at desc limit 5) s));
  end if;

  /* 對話：三個條件同時成立才進得來——
     joint 模式、兩個人都同意、而且這一次明確指定了天數。
     常設開關在這裡是拿不到東西的（last_chat_days 從頭到尾沒被讀）。 */
  v_days := greatest(0, least(coalesce(p_chat_days, 0), 90));
  if p_mode = 'joint' and v_days > 0 then
    select a.id into v_app from public.applications a
     where least(a.from_user,a.to_user) = v_link.user_a
       and greatest(a.from_user,a.to_user) = v_link.user_b
     order by a.created_at desc limit 1;
    ctx := ctx || jsonb_build_object('chat_days', v_days, 'chat', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'who', case when m.sender_id = auth.uid() then '我' else '對方' end,
               'at', m.created_at, 'body', m.body) order by m.created_at), '[]'::jsonb)
        from public.match_messages m
       where m.application_id = v_app and m.created_at > now() - make_interval(days => v_days)));
    update public.clinic_context_permissions set last_chat_days = v_days, updated_at = now()
     where link_id = p_link_id and user_id = auth.uid();
  end if;

  return ctx || jsonb_build_object('mode', p_mode, 'link_id', p_link_id);
end $$;
revoke all on function public.build_clinic_context(uuid,text,int) from public, anon;
grant execute on function public.build_clinic_context(uuid,text,int) to authenticated;

-- 30.4 存下這一次的診療紀錄 ------------------------------------
create or replace function public.save_clinic_session(
  p_link_id uuid, p_topic text, p_input text, p_summary jsonb,
  p_mode text default 'solo', p_safety boolean default false
) returns public.clinic_sessions
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.clinic_sessions; v_link public.companion_links;
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status = 'ended' then raise exception '這本陪伴紀錄已經結束，只能閱讀'; end if;
  insert into public.clinic_sessions(link_id, user_id, mode, topic, input, ai_summary,
                                     safety_mode)
    values (p_link_id, auth.uid(), coalesce(p_mode,'solo'),
            left(coalesce(p_topic,''), 120), left(coalesce(p_input,''), 8000),
            p_summary, coalesce(p_safety,false))
    returning * into v;
  return v;
end $$;
revoke all on function public.save_clinic_session(uuid,text,text,jsonb,text,boolean) from public, anon;
grant execute on function public.save_clinic_session(uuid,text,text,jsonb,text,boolean) to authenticated;

create or replace function public.list_clinic_sessions(p_link_id uuid, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public.companion_link_for(p_link_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', s.id, 'at', s.created_at, 'mode', s.mode, 'topic', s.topic,
            'summary', s.ai_summary, 'safety_mode', s.safety_mode) order by s.created_at desc),
            '[]'::jsonb)
            from (select * from public.clinic_sessions
                   where link_id = p_link_id and user_id = auth.uid()
                   order by created_at desc limit greatest(1, least(p_limit, 100))) s);
end $$;
revoke all on function public.list_clinic_sessions(uuid,int) from public, anon;
grant execute on function public.list_clinic_sessions(uuid,int) to authenticated;

create or replace function public.delete_clinic_session(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.clinic_sessions where id = p_id and user_id = auth.uid();
  if not found then raise exception '找不到這份診療紀錄'; end if;
end $$;
revoke all on function public.delete_clinic_session(uuid) from public, anon;
grant execute on function public.delete_clinic_session(uuid) to authenticated;

-- ============================================================
-- 31) 🌱 陪伴紀錄第 8 步（一半）：回憶膠囊，以及關係結束之後的處置
--
--     規格 6.1、6.2 這兩題已經決定過了，所以做得下去。
--     同一步的**年度回顧還沒做**：它要先回答規格第 7 節第 3 題
--     （資料要留一年以上，跟現在隱私權政策寫的保存期限衝突）。
--
--     ── 6.2 回憶膠囊：關係非 active 時不自動開 ──────────────
--     半年後自動跳出來的那封信，如果那時候兩個人已經分開了，它會變成傷害。
--     所以到期只是「可以開」，不是「自動打開」：
--       ・status = 'active' → 到期自動顯示
--       ・其他狀態         → 只靜靜列一行，點了才開，而且點之前先問一次
--     膠囊不因為關係結束就刪除——它是本人寫給自己的，處置跟著 6.1 走。
--
--     ── 6.1 30 天是「選擇的期限」，不是「保留的期限」──────
--     這兩個很容易寫反：
--       ・期限內選了 → **立刻**照選的做，不用等 30 天。
--       ・期限內沒選 → 到期時**自動刪除**。沒有回應不能被當成「同意永久保留」，
--         分手之後最可能發生的事就是再也不登入，而那不是同意。
--     所以 purge_due() 到期的動作是刪除，不是封存。
--
--     ⚠️ **這需要排程，而排程還沒有。** purge_due() 已經寫好了，
--     但沒有東西每天去呼叫它（跟第 36 節檢舉時效通知是同一個缺口）。
--     **在排程接上之前，介面上不可以對使用者承諾「30 天後會自動刪除」**——
--     承諾了卻沒有東西在執行，比不承諾更糟。
-- ============================================================

create table if not exists public.companion_capsules (
  id         uuid primary key default gen_random_uuid(),
  link_id    uuid not null references public.companion_links(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  open_at    date not null,
  title      text not null default '',
  body       text not null,
  opened_at  timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists companion_capsules_user_idx
  on public.companion_capsules(link_id, user_id, open_at);

alter table public.companion_capsules enable row level security;
drop policy if exists "companion_capsules_own" on public.companion_capsules;
-- 膠囊是本人寫給自己的，對方永遠讀不到
create policy "companion_capsules_own" on public.companion_capsules
  for select to authenticated using (user_id = auth.uid());
grant select on public.companion_capsules to authenticated;

-- 一方刪掉自己寫的東西時，在封存本裡留下痕跡。
-- 不留的話另一方會以為自己記錯了。
create table if not exists public.companion_tombstones (
  id         uuid primary key default gen_random_uuid(),
  link_id    uuid not null references public.companion_links(id) on delete cascade,
  deleted_by uuid not null references auth.users(id) on delete cascade,
  kind       text not null,
  n          int  not null default 0,
  at         timestamptz not null default now()
);
alter table public.companion_tombstones enable row level security;
drop policy if exists "companion_tombstones_read" on public.companion_tombstones;
create policy "companion_tombstones_read" on public.companion_tombstones
  for select to authenticated using (exists (
    select 1 from public.companion_links l
     where l.id = link_id and auth.uid() in (l.user_a, l.user_b)));
grant select on public.companion_tombstones to authenticated;

-- 31.1 膠囊 ----------------------------------------------------
create or replace function public.write_capsule(
  p_link_id uuid, p_open_at date, p_body text, p_title text default ''
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_id uuid;
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status = 'ended' then raise exception '這本陪伴紀錄已經結束，只能閱讀'; end if;
  if p_open_at is null or p_open_at <= current_date then
    raise exception '要選一個未來的日期，膠囊才有意義';
  end if;
  if btrim(coalesce(p_body,'')) = '' then raise exception '寫一點東西再封起來吧'; end if;
  insert into public.companion_capsules(link_id, user_id, open_at, title, body)
    values (p_link_id, auth.uid(), p_open_at, left(coalesce(p_title,''), 80),
            left(p_body, 8000))
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'open_at', p_open_at);
end $$;
revoke all on function public.write_capsule(uuid,date,text,text) from public, anon;
grant execute on function public.write_capsule(uuid,date,text,text) to authenticated;

/* 清單裡**不含內容**。到期只代表「可以開」，不代表已經開。 */
create or replace function public.list_capsules(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links;
begin
  v_link := public.companion_link_for(p_link_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', c.id, 'open_at', c.open_at, 'title', c.title,
            'due', c.open_at <= current_date,
            'opened', c.opened_at is not null,
            /* 關係還在進行中才自動顯示。其他狀態下只列一行，
               點了才開——而且前端要先問一次。 */
            'auto_open', (c.open_at <= current_date and c.opened_at is null
                          and v_link.status = 'active')) order by c.open_at)
            , '[]'::jsonb)
            from public.companion_capsules c
           where c.link_id = p_link_id and c.user_id = auth.uid());
end $$;
revoke all on function public.list_capsules(uuid) from public, anon;
grant execute on function public.list_capsules(uuid) to authenticated;

create or replace function public.open_capsule(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.companion_capsules;
begin
  select * into c from public.companion_capsules where id = p_id and user_id = auth.uid();
  if c.id is null then raise exception '找不到這封信'; end if;
  -- 沒到期就拿不到內容。擋在資料庫，不是擋在畫面上。
  if c.open_at > current_date then
    raise exception '這封信要到 % 才能打開', to_char(c.open_at, 'YYYY-MM-DD');
  end if;
  if c.opened_at is null then
    update public.companion_capsules set opened_at = now() where id = p_id;
  end if;
  return jsonb_build_object('id', c.id, 'open_at', c.open_at,
                            'title', c.title, 'body', c.body);
end $$;
revoke all on function public.open_capsule(uuid) from public, anon;
grant execute on function public.open_capsule(uuid) to authenticated;

-- 31.2 結束一段關係 --------------------------------------------
create or replace function public.end_companion_link(p_link_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links;
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status = 'ended' then return public.companion_disposition_state(p_link_id); end if;
  update public.companion_links
     set status = 'ended', ended_at = now(), purge_at = now() + interval '30 days'
   where id = p_link_id;
  return public.companion_disposition_state(p_link_id);
end $$;

create or replace function public.companion_disposition_state(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_me_is_a boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  v_me_is_a := (auth.uid() = v_link.user_a);
  return jsonb_build_object(
    'status', v_link.status,
    'ended_at', v_link.ended_at,
    'purge_at', v_link.purge_at,
    'mine', case when v_me_is_a then v_link.disposition_a else v_link.disposition_b end,
    /* 對方選了什麼不揭露。那是他自己的決定，而且知道了也改變不了什麼，
       只會變成分手之後多一件可以拿來想的事。 */
    'tombstones', (select coalesce(jsonb_agg(jsonb_build_object(
                     'kind', t.kind, 'n', t.n, 'mine', t.deleted_by = auth.uid())), '[]'::jsonb)
                     from public.companion_tombstones t where t.link_id = p_link_id));
end $$;
revoke all on function public.end_companion_link(uuid) from public, anon;
grant execute on function public.end_companion_link(uuid) to authenticated;
revoke all on function public.companion_disposition_state(uuid) from public, anon;
grant execute on function public.companion_disposition_state(uuid) to authenticated;

-- 刪掉某個人在這段關係裡寫的所有東西，並留下痕跡
create or replace function public.companion_purge_side(p_link_id uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare n int; v_link public.companion_links;
begin
  select * into v_link from public.companion_links where id = p_link_id;

  delete from public.companion_memories where link_id = p_link_id and created_by = p_user;
  get diagnostics n = row_count;
  if n > 0 then insert into public.companion_tombstones(link_id, deleted_by, kind, n)
    values (p_link_id, p_user, 'memory', n); end if;

  delete from public.companion_milestones where link_id = p_link_id and created_by = p_user;
  get diagnostics n = row_count;
  if n > 0 then insert into public.companion_tombstones(link_id, deleted_by, kind, n)
    values (p_link_id, p_user, 'milestone', n); end if;

  delete from public.companion_goals where link_id = p_link_id and created_by = p_user;
  get diagnostics n = row_count;
  if n > 0 then insert into public.companion_tombstones(link_id, deleted_by, kind, n)
    values (p_link_id, p_user, 'goal', n); end if;

  delete from public.relationship_checkins where link_id = p_link_id and user_id = p_user;
  delete from public.clinic_sessions where link_id = p_link_id and user_id = p_user;
  delete from public.companion_capsules where link_id = p_link_id and user_id = p_user;

  -- 對話書籤也是這段關係的一部分
  delete from public.message_bookmarks b using public.applications a
   where b.application_id = a.id and b.user_id = p_user
     and least(a.from_user, a.to_user) = v_link.user_a
     and greatest(a.from_user, a.to_user) = v_link.user_b;
end $$;
revoke all on function public.companion_purge_side(uuid,uuid) from public, anon, authenticated;

create or replace function public.set_companion_disposition(p_link_id uuid, p_choice text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_me_is_a boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status <> 'ended' then raise exception '這段關係還沒結束'; end if;
  if p_choice not in ('delete','archive','mine_only') then raise exception '不支援的處置方式'; end if;
  v_me_is_a := (auth.uid() = v_link.user_a);

  if v_me_is_a then update public.companion_links set disposition_a = p_choice where id = p_link_id;
  else                update public.companion_links set disposition_b = p_choice where id = p_link_id; end if;

  -- 選了就立刻做，不用等 30 天。30 天是選擇的期限，不是保留的期限。
  if p_choice = 'delete' then
    perform public.companion_purge_side(p_link_id, auth.uid());
  end if;
  return public.companion_disposition_state(p_link_id);
end $$;
revoke all on function public.set_companion_disposition(uuid,text) from public, anon;
grant execute on function public.set_companion_disposition(uuid,text) to authenticated;

/* 到期還沒選的，刪掉。沒有回應不是同意永久保留。
   ⚠️ 這支函式目前**沒有東西在呼叫它**——要接 pg_cron 或 Scheduled Function。
   在那之前，介面上不可以承諾「30 天後自動刪除」。 */
create or replace function public.purge_due_companion_links()
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
begin
  for r in select * from public.companion_links
            where status = 'ended' and purge_at is not null and purge_at < now() loop
    if r.disposition_a is null then perform public.companion_purge_side(r.id, r.user_a); n := n + 1; end if;
    if r.disposition_b is null then perform public.companion_purge_side(r.id, r.user_b); n := n + 1; end if;
    update public.companion_links
       set disposition_a = coalesce(disposition_a, 'delete'),
           disposition_b = coalesce(disposition_b, 'delete'),
           purge_at = null
     where id = r.id;
  end loop;
  return n;
end $$;
revoke all on function public.purge_due_companion_links() from public, anon, authenticated;
grant execute on function public.purge_due_companion_links() to service_role;

-- 31.3 時間線改版：尊重「只留我自己寫的」---------------------
--      放在這裡覆寫第 28.6 節的版本，因為它要用到這一節的 disposition 欄位。
create or replace function public.companion_timeline(p_link_id uuid, p_limit int default 200)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; out_rows jsonb; v_mine_only boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  /* coalesce 不能省：處置方式還沒選的時候它是 null，
     而 null = 'mine_only' 的結果是 null 不是 false，
     接著 `not v_mine_only` 也是 null，整個 where 就變成什麼都不符合——
     一段還沒結束的關係，時間線會整個變空。 */
  v_mine_only := coalesce((case when auth.uid() = v_link.user_a
                                then v_link.disposition_a else v_link.disposition_b end)
                          = 'mine_only', false);
  select coalesce(jsonb_agg(x order by x->>'at' desc, x->>'created_at' desc), '[]'::jsonb)
    into out_rows
    from (
      select jsonb_build_object(
        'kind','memory', 'id', m.id, 'at', m.at, 'type', m.type,
        'title', m.title, 'body', m.body, 'visibility', m.visibility,
        'mine', m.created_by = auth.uid(), 'created_at', m.created_at) as x
        from public.companion_memories m
       where m.link_id = p_link_id
         and (m.created_by = auth.uid() or (m.visibility = 'both' and not v_mine_only))
      union all
      select jsonb_build_object(
        'kind','milestone', 'id', s.id, 'at', s.at, 'type', s.milestone_type,
        'title', '', 'body', s.note, 'visibility', 'both',
        'mine', s.created_by = auth.uid(), 'created_at', s.created_at)
        from public.companion_milestones s
       where s.link_id = p_link_id and (s.created_by = auth.uid() or not v_mine_only)
      union all
      select jsonb_build_object(
        'kind','bookmark', 'id', b.id, 'at', b.created_at::date, 'type', b.kind,
        'title', left(msg.body, 80), 'body', b.note, 'visibility', b.visibility,
        'mine', b.user_id = auth.uid(), 'created_at', b.created_at)
        from public.message_bookmarks b
        join public.match_messages msg on msg.id = b.message_id
        join public.applications a on a.id = b.application_id
       where least(a.from_user, a.to_user) = v_link.user_a
         and greatest(a.from_user, a.to_user) = v_link.user_b
         and (b.user_id = auth.uid() or (b.visibility = 'both' and not v_mine_only))
    ) s
   limit greatest(1, least(p_limit, 500));
  return out_rows;
end $$;
revoke all on function public.companion_timeline(uuid,int) from public, anon;
grant execute on function public.companion_timeline(uuid,int) to authenticated;

-- 31.4 我的陪伴紀錄清單 ----------------------------------------
--      個人中心那個分頁要靠它。已結束的也列出來——處置方式要在那裡選。
create or replace function public.my_companion_links()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  return (select coalesce(jsonb_agg(x order by x->>'started_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'link_id', l.id,
      'status',  l.status,
      'started_at', l.started_at,
      'ended_at', l.ended_at,
      'days', case when l.status = 'active'
                   then greatest(0, (current_date - l.started_at::date)) else null end,
      'other_name', coalesce(nullif(p.name,''), '對方'),
      'other_id', p.id,
      /* 處置方式只回自己那一格。對方選了什麼不揭露。 */
      'my_disposition', case when auth.uid() = l.user_a then l.disposition_a else l.disposition_b end,
      'purge_at', l.purge_at) as x
      from public.companion_links l
      join public.match_profiles p
        on p.id = case when auth.uid() = l.user_a then l.user_b else l.user_a end
     where auth.uid() in (l.user_a, l.user_b)
       and l.status <> 'pending') s);
end $$;
revoke all on function public.my_companion_links() from public, anon;
grant execute on function public.my_companion_links() to authenticated;

-- ============================================================
-- 32) 🌱 陪伴紀錄第 8 步的另一半：伴侶關係的相互承認，與年度回顧
--
--     規格第 7 節第 3 題（年度回顧要留一年以上，跟隱私權政策的保存期限衝突）
--     的答案：**年度回顧只給互相承認彼此為伴侶的兩個人。**
--     其餘的關係不做年度回顧，也就不需要為了年度回顧多留任何東西。
--     於是「保留超過一年」不再是一個對所有人生效的預設，
--     而是一件兩個人各自明確按下、而且隨時可以收回的事。
--
--     ── 這一節跟第 27 節刻意不一樣的地方：單方面按下**不會**讓對方看到 ──
--     第 27 節建立陪伴紀錄時，我讓「對方想為這段相遇留下紀錄」顯示出來，
--     因為那是一個關於「要不要一起記東西」的邀請。
--     承認彼此是伴侶不是邀請，是一句告白。
--     把「某某已經認定你是他的伴侶」推到另一個人面前，
--     他接下來按或不按都不再是自由的——按了可能只是不想讓對方難堪，
--     不按則變成一次當面的拒絕。
--     所以這裡改成**兩個人都按下才會同時看到**，在那之前誰都不知道對方按了沒有。
--     收回也一樣安靜，不會通知。
--
--     ── 這不是等級，也不是成就 ──
--     沒有徽章、沒有「配對成功率」、沒有把它放在別人看得到的地方。
--     它只做兩件事：讓年度回顧出現，以及讓這段紀錄的保存期限跟著關係走。
-- ============================================================

alter table public.companion_links add column if not exists partner_a boolean not null default false;
alter table public.companion_links add column if not exists partner_b boolean not null default false;
alter table public.companion_links add column if not exists partnered_at timestamptz;

create or replace function public.set_companion_partner(p_link_id uuid, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_me_is_a boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status <> 'active' then
    raise exception '陪伴紀錄要在進行中才能做這件事';
  end if;
  v_me_is_a := (auth.uid() = v_link.user_a);
  if v_me_is_a then update public.companion_links set partner_a = coalesce(p_on,false) where id = p_link_id;
  else               update public.companion_links set partner_b = coalesce(p_on,false) where id = p_link_id; end if;

  -- partnered_at 只在第一次成立時寫，收回再按回來不重算（跟 started_at 同一個理由）
  update public.companion_links
     set partnered_at = case when partner_a and partner_b and partnered_at is null
                             then now() else partnered_at end
   where id = p_link_id;
  return public.companion_partner_state(p_link_id);
end $$;
revoke all on function public.set_companion_partner(uuid, boolean) from public, anon;
grant execute on function public.set_companion_partner(uuid, boolean) to authenticated;

create or replace function public.companion_partner_state(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_me_is_a boolean; v_mine boolean; v_both boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  v_me_is_a := (auth.uid() = v_link.user_a);
  v_mine := case when v_me_is_a then v_link.partner_a else v_link.partner_b end;
  v_both := v_link.partner_a and v_link.partner_b;
  return jsonb_build_object(
    'mine', v_mine,
    /* **只有在兩邊都按下時才回傳 other。**
       單方面按下時這裡永遠是 false，不是「對方還沒按」——
       因為連「對方按了沒有」這件事本身都不該讓人知道。
       想改這一行之前，先讀這一節開頭那段。 */
    'other', v_both,
    'both',  v_both,
    'partnered_at', case when v_both then v_link.partnered_at else null end,
    'eligible', v_link.status = 'active');
end $$;
revoke all on function public.companion_partner_state(uuid) from public, anon;
grant execute on function public.companion_partner_state(uuid) to authenticated;

-- 32.1 保存期限 ------------------------------------------------
--      隱私權政策裡那條「陪伴紀錄保留多久」的程式版本。
--      沒有互相承認的關係不做年度回顧，也就不需要為了它多留東西。
create or replace function public.companion_keeps_history(p_link_id uuid)
returns boolean language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links;
begin
  v_link := public.companion_link_for(p_link_id);
  return v_link.partner_a and v_link.partner_b;
end $$;
revoke all on function public.companion_keeps_history(uuid) from public, anon;
grant execute on function public.companion_keeps_history(uuid) to authenticated;

-- 32.2 年度回顧 ------------------------------------------------
--      **這裡沒有 AI，也沒有任何數字。**
--      年度回顧就是把那一年你們自己寫下的東西照時間端出來。
--      放一個「今年你們記了 12 則回憶」進去，它就會變成一個要衝的數字；
--      放一段 AI 講評進去，它就會變成一份年度評鑑。兩個都不要。
create or replace function public.companion_annual_review(
  p_link_id uuid, p_period_end date default null
) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_link public.companion_links; v_from date; v_to date;
  v_mem jsonb; v_ms jsonb; v_bm jsonb; v_goals jsonb; v_first date;
begin
  v_link := public.companion_link_for(p_link_id);
  if not (v_link.partner_a and v_link.partner_b) then
    raise exception '年度回顧只在兩個人都承認彼此是伴侶之後才會出現';
  end if;
  v_to   := coalesce(p_period_end, current_date);
  v_from := (v_to - interval '1 year')::date;

  select coalesce(jsonb_agg(jsonb_build_object(
           'at', m.at, 'type', m.type, 'title', m.title, 'body', m.body,
           'mine', m.created_by = auth.uid()) order by m.at), '[]'::jsonb)
    into v_mem
    from public.companion_memories m
   where m.link_id = p_link_id and m.at > v_from and m.at <= v_to
     and (m.created_by = auth.uid() or m.visibility = 'both');

  select coalesce(jsonb_agg(jsonb_build_object(
           'at', s.at, 'type', s.milestone_type, 'note', s.note) order by s.at), '[]'::jsonb)
    into v_ms
    from public.companion_milestones s
   where s.link_id = p_link_id and s.at > v_from and s.at <= v_to;

  select coalesce(jsonb_agg(jsonb_build_object(
           'at', b.created_at::date, 'kind', b.kind, 'body', msg.body,
           'note', b.note, 'mine', b.user_id = auth.uid()) order by b.created_at), '[]'::jsonb)
    into v_bm
    from public.message_bookmarks b
    join public.match_messages msg on msg.id = b.message_id
    join public.applications a on a.id = b.application_id
   where least(a.from_user, a.to_user) = v_link.user_a
     and greatest(a.from_user, a.to_user) = v_link.user_b
     and b.created_at::date > v_from and b.created_at::date <= v_to
     and (b.user_id = auth.uid() or b.visibility = 'both');

  /* 目標只列「完成了」與「先放著」，而且兩個並列，不分好壞。
     先放著不是沒做到，是那一年你們決定先不推它。 */
  select coalesce(jsonb_agg(jsonb_build_object(
           'title', g.title, 'category', g.category, 'status', g.status) order by g.created_at), '[]'::jsonb)
    into v_goals
    from public.companion_goals g
   where g.link_id = p_link_id and g.status in ('done','paused');

  select min(x) into v_first from (
    select min(at) as x from public.companion_memories where link_id = p_link_id
    union all select min(at) from public.companion_milestones where link_id = p_link_id
    union all select v_link.started_at::date) t;

  return jsonb_build_object(
    'period_start', v_from, 'period_end', v_to,
    'partnered_at', v_link.partnered_at,
    'first_entry',  v_first,
    'memories', v_mem, 'milestones', v_ms, 'bookmarks', v_bm, 'goals', v_goals,
    /* 有沒有東西可以看，交給前端判斷有沒有內容就好。
       這裡刻意不回傳任何 count 欄位——一個數字放在那裡，遲早會被畫成一個數字。 */
    'empty', (v_mem = '[]'::jsonb and v_ms = '[]'::jsonb
              and v_bm = '[]'::jsonb and v_goals = '[]'::jsonb));
end $$;
revoke all on function public.companion_annual_review(uuid,date) from public, anon;
grant execute on function public.companion_annual_review(uuid,date) to authenticated;

-- 哪幾個年度可以看：從第一筆紀錄那一年到今年
create or replace function public.companion_annual_periods(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_first date; d date; out_rows jsonb := '[]'::jsonb;
begin
  v_link := public.companion_link_for(p_link_id);
  if not (v_link.partner_a and v_link.partner_b) then return '[]'::jsonb; end if;
  v_first := v_link.started_at::date;
  d := current_date;
  while d > v_first loop
    out_rows := out_rows || jsonb_build_array(jsonb_build_object(
      'end', d, 'start', (d - interval '1 year')::date));
    d := (d - interval '1 year')::date;
  end loop;
  if out_rows = '[]'::jsonb then
    out_rows := jsonb_build_array(jsonb_build_object(
      'end', current_date, 'start', (current_date - interval '1 year')::date));
  end if;
  return out_rows;
end $$;
revoke all on function public.companion_annual_periods(uuid) from public, anon;
grant execute on function public.companion_annual_periods(uuid) to authenticated;

-- 32.3 清單也要帶上伴侶狀態（一樣只在兩邊都按下時才回傳）--------
create or replace function public.my_companion_links()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  return (select coalesce(jsonb_agg(x order by x->>'started_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'link_id', l.id,
      'status',  l.status,
      'started_at', l.started_at,
      'ended_at', l.ended_at,
      'days', case when l.status = 'active'
                   then greatest(0, (current_date - l.started_at::date)) else null end,
      'other_name', coalesce(nullif(p.name,''), '對方'),
      'other_id', p.id,
      'my_disposition', case when auth.uid() = l.user_a then l.disposition_a else l.disposition_b end,
      'purge_at', l.purge_at,
      'partner_mine', case when auth.uid() = l.user_a then l.partner_a else l.partner_b end,
      -- 只有兩邊都按下才成立，也只有那時候才看得出對方按過
      'partnered', (l.partner_a and l.partner_b),
      'partnered_at', case when l.partner_a and l.partner_b then l.partnered_at else null end) as x
      from public.companion_links l
      join public.match_profiles p
        on p.id = case when auth.uid() = l.user_a then l.user_b else l.user_a end
     where auth.uid() in (l.user_a, l.user_b)
       and l.status <> 'pending') s);
end $$;
revoke all on function public.my_companion_links() from public, anon;
grant execute on function public.my_companion_links() to authenticated;

-- ============================================================
-- 33) 💛 他們的故事：配對成功的伴侶把故事貼出來給其他人看
--
--     ── 這一節在做的事，本質上是第 26 節那個洞的放大版 ──────
--     暖陽整套四層漸進式揭露，就是為了讓聯絡方式要走完三階段、
--     雙方都同意才交換。一個可以自由輸入、而且**訪客也看得到**的欄位，
--     等於開了一條把任何文字放到所有人面前的管道。
--     所以這裡有三道關，缺一不可：
--       ① 伺服器端擋聯絡方式（沿用第 26 節的 looks_like_contact）
--       ② **兩個人都要同意才送得出去**
--       ③ 人工審核通過才公開
--
--     ── 四條寫死的產品規則 ────────────────────────────────
--     (1) **只有互相承認彼此是伴侶的兩個人才能寫。**（第 32 節的條件）
--     (2) **改了字，同意就作廢。** 對方同意的是「那一段文字」，
--         不是「你之後想寫的任何東西」。這一條沒做的話，
--         第 ② 道關可以被一次編輯繞過去。
--     (3) **任何一方隨時可以撤下，而且立刻生效、不需要對方同意、不用問原因。**
--         一段關於兩個人的公開文字，其中一個人不想要了就是不想要了。
--     (4) **關係結束就自動下架。** 一則屬於已經分開的兩個人的「成功故事」
--         留在公開頁面上，對兩邊都是傷害。這一條不靠排程，
--         直接做在 end_companion_link() 裡。
--
--     ── 沒有的東西 ────────────────────────────────────────
--     沒有愛心、沒有瀏覽數、沒有排行榜、沒有精選。
--     一旦故事之間可以比較，寫故事就變成一件要表現的事。
--     排序永遠是「最新的在前面」。
-- ============================================================

create table if not exists public.companion_stories (
  id          uuid primary key default gen_random_uuid(),
  link_id     uuid not null unique references public.companion_links(id) on delete cascade,
  title       text not null default '',
  body        text not null default '',
  -- 各自決定自己要不要具名。預設兩邊都不具名——
  -- 「這兩個帳號在一起」本身就是一則新的公開資訊，佈告欄上原本沒有。
  show_name_a boolean not null default false,
  show_name_b boolean not null default false,
  author      uuid references auth.users(id) on delete set null,
  agreed_a    boolean not null default false,
  agreed_b    boolean not null default false,
  status      text not null default 'draft',
  admin_note  text not null default '',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  published_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.companion_stories drop constraint if exists companion_stories_status_check;
alter table public.companion_stories add constraint companion_stories_status_check
  check (status in ('draft','pending','published','rejected'));
create index if not exists companion_stories_public_idx
  on public.companion_stories(status, published_at desc);

alter table public.companion_stories enable row level security;
drop policy if exists "companion_stories_own" on public.companion_stories;
/* 表本身只有當事人與管理員讀得到。
   訪客要看的是 list_public_stories()，那支只回安全的欄位——
   直接開放讀表的話，link_id、author、agreed_* 會一起流出去。 */
create policy "companion_stories_own" on public.companion_stories
  for select to authenticated using (
    public.match_is_admin(auth.uid())
    or exists (select 1 from public.companion_links l
                where l.id = link_id and auth.uid() in (l.user_a, l.user_b)));
grant select on public.companion_stories to authenticated;

-- 33.1 寫與改 --------------------------------------------------
create or replace function public.save_story(p_link_id uuid, p_title text, p_body text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v public.companion_stories;
begin
  v_link := public.companion_link_for(p_link_id);
  if not (v_link.partner_a and v_link.partner_b) then
    raise exception '故事只能由互相承認彼此是伴侶的兩個人一起寫';
  end if;
  if v_link.status <> 'active' then raise exception '陪伴紀錄要在進行中才能寫故事'; end if;

  if btrim(coalesce(p_title,'')) = '' then raise exception '故事要有一個標題'; end if;
  if char_length(btrim(coalesce(p_body,''))) < 30 then
    raise exception '再多寫一點吧，至少 30 個字';
  end if;
  if char_length(p_body) > 4000 then raise exception '故事最多 4000 個字'; end if;
  /* ① 聯絡方式。沿用第 26 節那一支——這裡是訪客也看得到的地方，
     一則故事如果可以寫「有興趣的人加我 LINE」，整套解鎖流程就被繞過去了。 */
  if public.looks_like_contact(p_title) or public.looks_like_contact(p_body) then
    raise exception '故事裡不要放聯絡方式（email、電話、LINE／IG 帳號、網址）——這一頁訪客也看得到';
  end if;

  insert into public.companion_stories(link_id, title, body, author, status)
    values (p_link_id, left(btrim(p_title), 60), btrim(p_body), auth.uid(), 'draft')
  on conflict (link_id) do update set
    title = excluded.title, body = excluded.body, author = auth.uid(),
    /* ② 改了字，同意就作廢。對方同意的是「那一段文字」，
       不是「你之後想寫的任何東西」。少了這一行，雙方同意那道關
       可以被一次編輯整個繞過去。 */
    agreed_a = false, agreed_b = false,
    status = 'draft', admin_note = '', reviewed_by = null, reviewed_at = null,
    published_at = null, updated_at = now()
  returning * into v;
  return public.story_state(p_link_id);
end $$;
revoke all on function public.save_story(uuid,text,text) from public, anon;
grant execute on function public.save_story(uuid,text,text) to authenticated;

-- 各自決定自己要不要具名
create or replace function public.set_story_name(p_link_id uuid, p_show boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links;
begin
  v_link := public.companion_link_for(p_link_id);
  if auth.uid() = v_link.user_a then
    update public.companion_stories set show_name_a = coalesce(p_show,false), updated_at = now()
     where link_id = p_link_id;
  else
    update public.companion_stories set show_name_b = coalesce(p_show,false), updated_at = now()
     where link_id = p_link_id;
  end if;
  return public.story_state(p_link_id);
end $$;
revoke all on function public.set_story_name(uuid,boolean) from public, anon;
grant execute on function public.set_story_name(uuid,boolean) to authenticated;

-- 33.2 同意送出／撤下 ------------------------------------------
create or replace function public.set_story_agree(p_link_id uuid, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v public.companion_stories; v_me_is_a boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  select * into v from public.companion_stories where link_id = p_link_id;
  if v.id is null then raise exception '還沒有故事'; end if;
  v_me_is_a := (auth.uid() = v_link.user_a);

  -- 只動自己那一格
  if v_me_is_a then update public.companion_stories set agreed_a = coalesce(p_on,false) where id = v.id;
  else               update public.companion_stories set agreed_b = coalesce(p_on,false) where id = v.id; end if;

  /* ③ 撤下是立刻生效的，而且不需要對方同意、不用寫原因。
     一段關於兩個人的公開文字，其中一個人不想要了就是不想要了。
     已經審過的也一樣會掉下來——之後要再上，就要重新審一次。 */
  update public.companion_stories
     set status = case
           when not (agreed_a and agreed_b) then 'draft'
           when status = 'published' then 'published'
           when status = 'rejected'  then 'rejected'
           else 'pending' end,
         published_at = case when agreed_a and agreed_b and status = 'published'
                             then published_at else null end,
         updated_at = now()
   where id = v.id;
  return public.story_state(p_link_id);
end $$;
revoke all on function public.set_story_agree(uuid,boolean) from public, anon;
grant execute on function public.set_story_agree(uuid,boolean) to authenticated;

create or replace function public.story_state(p_link_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v public.companion_stories; v_me_is_a boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  v_me_is_a := (auth.uid() = v_link.user_a);
  select * into v from public.companion_stories where link_id = p_link_id;
  return jsonb_build_object(
    'eligible', (v_link.partner_a and v_link.partner_b and v_link.status = 'active'),
    'exists',   v.id is not null,
    'title',    coalesce(v.title, ''),
    'body',     coalesce(v.body, ''),
    'status',   coalesce(v.status, 'none'),
    'admin_note', coalesce(v.admin_note, ''),
    'mine',     coalesce(case when v_me_is_a then v.agreed_a else v.agreed_b end, false),
    /* 這裡跟第 32 節不同：故事的同意狀態兩邊都看得到。
       他們已經互相承認彼此是伴侶了，「要不要一起把故事貼出去」
       是一件本來就要一起討論的事，不是一句需要保護的告白。 */
    'other',    coalesce(case when v_me_is_a then v.agreed_b else v.agreed_a end, false),
    'show_name', coalesce(case when v_me_is_a then v.show_name_a else v.show_name_b end, false),
    'published_at', v.published_at);
end $$;
revoke all on function public.story_state(uuid) from public, anon;
grant execute on function public.story_state(uuid) to authenticated;

-- 33.3 訪客看到的清單 ------------------------------------------
--      只回公開需要的欄位。沒有 id 以外的內部欄位，也沒有任何計數。
create or replace function public.list_public_stories(p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'title', s.title, 'body', s.body,
      'published_at', s.published_at,
      /* 各自決定自己要不要具名。沒同意的那一邊回 null，
         前端顯示成「一位使用者」。 */
      'name_a', case when s.show_name_a then coalesce(nullif(pa.name,''), null) else null end,
      'name_b', case when s.show_name_b then coalesce(nullif(pb.name,''), null) else null end)
      /* 永遠照時間排。一旦可以照「熱門」排，寫故事就變成一件要表現的事。 */
      order by s.published_at desc), '[]'::jsonb)
    from (select * from public.companion_stories
           where status = 'published' and published_at is not null
           order by published_at desc limit greatest(1, least(p_limit, 100))) s
    join public.companion_links l on l.id = s.link_id
    left join public.match_profiles pa on pa.id = l.user_a
    left join public.match_profiles pb on pb.id = l.user_b);
end $$;
grant execute on function public.list_public_stories(int) to authenticated, anon;

-- 33.4 人工審核 ------------------------------------------------
create or replace function public.admin_story_queue()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.match_is_admin(auth.uid()) then
    raise exception '只有管理員可以審核故事';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'link_id', s.link_id, 'title', s.title, 'body', s.body,
      'status', s.status, 'admin_note', s.admin_note,
      'updated_at', s.updated_at, 'published_at', s.published_at)
      -- 待審的排前面，同一組裡最舊的排前面（誰等最久）
      order by (s.status <> 'pending'), s.updated_at), '[]'::jsonb)
    from public.companion_stories s
   where s.status in ('pending','published','rejected'));
end $$;
revoke all on function public.admin_story_queue() from public, anon;
grant execute on function public.admin_story_queue() to authenticated;

create or replace function public.admin_review_story(
  p_id uuid, p_approve boolean, p_note text default ''
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.companion_stories;
begin
  if auth.uid() is null or not public.match_is_admin(auth.uid()) then
    raise exception '只有管理員可以審核故事';
  end if;
  select * into v from public.companion_stories where id = p_id;
  if v.id is null then raise exception '找不到這則故事'; end if;
  /* 審核不能替當事人補上同意。少了這一條，一則被撤下的故事
     可以被管理員一鍵放回公開頁面。 */
  if p_approve and not (v.agreed_a and v.agreed_b) then
    raise exception '這則故事目前沒有雙方同意，不能公開';
  end if;
  update public.companion_stories
     set status = case when p_approve then 'published' else 'rejected' end,
         admin_note = left(coalesce(p_note,''), 500),
         reviewed_by = auth.uid(), reviewed_at = now(),
         published_at = case when p_approve then now() else null end,
         updated_at = now()
   where id = p_id returning * into v;
  return jsonb_build_object('id', v.id, 'status', v.status);
end $$;
revoke all on function public.admin_review_story(uuid,boolean,text) from public, anon;
grant execute on function public.admin_review_story(uuid,boolean,text) to authenticated;

-- 33.5 關係一結束或收回相互承認，故事就下架 --------------------
--      (4) 一則屬於已經分開的兩個人的「成功故事」留在公開頁面上，
--      對兩邊都是傷害。這裡不靠排程，直接做在那兩支 RPC 裡。
create or replace function public.unpublish_story_for(p_link_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.companion_stories
     set status = 'draft', published_at = null, updated_at = now()
   where link_id = p_link_id and status <> 'draft';
end $$;
revoke all on function public.unpublish_story_for(uuid) from public, anon, authenticated;

create or replace function public.end_companion_link(p_link_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links;
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status = 'ended' then return public.companion_disposition_state(p_link_id); end if;
  update public.companion_links
     set status = 'ended', ended_at = now(), purge_at = now() + interval '30 days'
   where id = p_link_id;
  perform public.unpublish_story_for(p_link_id);
  return public.companion_disposition_state(p_link_id);
end $$;
revoke all on function public.end_companion_link(uuid) from public, anon;
grant execute on function public.end_companion_link(uuid) to authenticated;

create or replace function public.set_companion_partner(p_link_id uuid, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_link public.companion_links; v_me_is_a boolean;
begin
  v_link := public.companion_link_for(p_link_id);
  if v_link.status <> 'active' then
    raise exception '陪伴紀錄要在進行中才能做這件事';
  end if;
  v_me_is_a := (auth.uid() = v_link.user_a);
  if v_me_is_a then update public.companion_links set partner_a = coalesce(p_on,false) where id = p_link_id;
  else               update public.companion_links set partner_b = coalesce(p_on,false) where id = p_link_id; end if;

  update public.companion_links
     set partnered_at = case when partner_a and partner_b and partnered_at is null
                             then now() else partnered_at end
   where id = p_link_id;

  -- 收回相互承認 → 故事也跟著下架（寫故事的前提沒有了）
  select * into v_link from public.companion_links where id = p_link_id;
  if not (v_link.partner_a and v_link.partner_b) then
    perform public.unpublish_story_for(p_link_id);
  end if;
  return public.companion_partner_state(p_link_id);
end $$;
revoke all on function public.set_companion_partner(uuid, boolean) from public, anon;
grant execute on function public.set_companion_partner(uuid, boolean) to authenticated;
