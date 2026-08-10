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
alter table public.applications add column if not exists vet_scores jsonb;
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
-- 8) owner_kv：私人工具（暖陽動物之家回覆助手）專用的個人儲存空間
--    只給你自己的帳號使用，其他人完全存取不到
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
    'area',                   nullif(p.area, ''),
    'dealbreakers',      coalesce(p.dealbreakers, '{}'::jsonb)
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

  -- 同一個題組只報最嚴重的那一層。
  -- 例：關係期待同時命中 R007（🔴 雙方都不可妥協）與 R006（🟡 方向不同）時，
  -- 兩個一起顯示等於把同一件事講兩次，而且會讓「🟡 N 項」變得沒有意義。
  select coalesce(jsonb_agg(h order by (h->>'priority')::int, h->>'code'), '[]'::jsonb)
    into findings
    from jsonb_array_elements(hits) h
   where public.screening_severity(h->>'outcome') = (
     select min(public.screening_severity(k->>'outcome'))
       from jsonb_array_elements(hits) k where k->>'topic' = h->>'topic');

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
   '{applicant.family_visit_freq,recipient.family_visit_freq}',
   'R_FAMILY_INVOLVE','一方期待伴侶每週參與家庭活動，另一方很少回原生家庭',
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
