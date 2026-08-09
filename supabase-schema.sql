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
      'income','living','kids_plan','work_hours','debt','debt_when'
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
      -- 第 2 層
      'income',      case when rel.stage >= 2 then p.income else null end,
      'living',      case when rel.stage >= 2 then p.living else null end,
      'kids_plan',   case when rel.stage >= 2 then p.kids_plan else null end,
      'work_hours',  case when rel.stage >= 2 then p.work_hours else null end,
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
