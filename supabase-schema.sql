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
-- 1) profiles：每個帳號一筆，公開登記資料
-- ============================================================
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default '',
  kind        text not null default '' check (kind in ('', 'pet', 'keeper')),
  species     text not null default '',   -- 13 種動物，見 index.html 的 SPECIES 清單
  gender      text not null default 'f',  -- f 女生／m 男生／x 不透露（與物種脫鉤）
  age         text default '',
  area        text default '',
  job         text default '',
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
  verify_status text not null default 'none' check (verify_status in ('none','pending','approved','rejected')),
  verify_reason text default '',
  verify_task jsonb,                   -- {gesture, code}：驗證照要比的手勢與紙條代碼
  verify_deleted_at timestamptz,
  consent     boolean not null default false,
  consent_at  timestamptz,
  bonus_given boolean not null default false,  -- 完成登記＋照片審核通過的獎勵點數是否已發過
  is_admin    boolean not null default false,  -- 審核台權限；只能自己去 Table Editor 手動打勾給信任帳號
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
alter table public.profiles add column if not exists name text not null default '';
alter table public.profiles add column if not exists kind text not null default '';
alter table public.profiles add column if not exists species text not null default '';
alter table public.profiles add column if not exists age text default '';
alter table public.profiles add column if not exists area text default '';
alter table public.profiles add column if not exists job text default '';
alter table public.profiles add column if not exists bio text default '';
alter table public.profiles add column if not exists wants text default '';
alter table public.profiles add column if not exists locked text default '';
alter table public.profiles add column if not exists q1 jsonb;
alter table public.profiles add column if not exists q2_bank jsonb;
alter table public.profiles add column if not exists canned jsonb;
alter table public.profiles add column if not exists created_at timestamptz default now();
alter table public.profiles add column if not exists updated_at timestamptz default now();
alter table public.profiles add column if not exists credits int not null default 5;
alter table public.profiles add column if not exists credit_log jsonb not null default '[]'::jsonb;
alter table public.profiles alter column credits set default 5;
alter table public.profiles add column if not exists photo_status text not null default 'none';
alter table public.profiles add column if not exists photo_reason text default '';
alter table public.profiles add column if not exists verify_status text not null default 'none';
alter table public.profiles add column if not exists verify_reason text default '';
alter table public.profiles add column if not exists verify_task jsonb;
alter table public.profiles add column if not exists verify_deleted_at timestamptz;
alter table public.profiles add column if not exists consent boolean not null default false;
alter table public.profiles add column if not exists consent_at timestamptz;
alter table public.profiles add column if not exists bonus_given boolean not null default false;
alter table public.profiles add column if not exists is_admin boolean not null default false;

-- 病歷卡欄位（物種擴充、性別獨立、星等評分、禁忌、健康告知、獸醫備註）
alter table public.profiles add column if not exists gender text not null default 'f';
alter table public.profiles add column if not exists birth text default '';
alter table public.profiles add column if not exists traits text default '';
alter table public.profiles add column if not exists likes text default '';
alter table public.profiles add column if not exists taboo text default '';
alter table public.profiles add column if not exists health text default '';
alter table public.profiles add column if not exists health_tags jsonb not null default '[]'::jsonb;
alter table public.profiles add column if not exists health_when text not null default 'stage2';
alter table public.profiles add column if not exists vet_note text default '';
alter table public.profiles add column if not exists stars jsonb not null default '{}'::jsonb;
-- 我的答題紀錄：申請人送出過的答案，下次遇到相似題目可以一鍵帶入再修改
alter table public.profiles add column if not exists answer_bank jsonb not null default '[]'::jsonb;

-- 加碼照片：第一階段（口罩照／側拍照）、第二階段（生活照），登記人各上傳一張，
-- 讓通過該階段審查的申請人可以看到——只是「有沒有上傳」的旗標，實際檔案存在
-- storage 的 stage-photos bucket（私有），能不能讀由 storage policy 依申請進度判斷。
alter table public.profiles add column if not exists stage1_photo boolean not null default false;
alter table public.profiles add column if not exists stage2_photo boolean not null default false;

-- 一鍵通關：登記人自己選擇要不要開放，開放後申請人可以付點數直接跳到最終解鎖，
-- 免除三個階段的問答與審核。bonus_credits 記錄「哪一筆獎勵點數、什麼時候到期」，
-- 用來在 14 天內沒花完時收回，一併鎖進下面的 guard trigger，不能自己改。
alter table public.profiles add column if not exists allow_skip boolean not null default false;
alter table public.profiles add column if not exists bonus_credits jsonb not null default '[]'::jsonb;

-- 物種從「只有貓／狗」放寬成 13 種，性別改用獨立的 gender 欄位表示。
-- 先移除舊的 check 限制，再依現有資料把 gender 補上（貓→女生、狗→男生，符合舊版的隱含規則）。
alter table public.profiles drop constraint if exists profiles_species_check;
update public.profiles set gender = case when species = 'dog' then 'm' else 'f' end
  where gender is null or gender = '';

-- 詳細資料（選填，會公開）——自介的結構化欄位
alter table public.profiles add column if not exists income text default '';
alter table public.profiles add column if not exists marital text default '';
alter table public.profiles add column if not exists has_kids text default '';
alter table public.profiles add column if not exists military text default '';
alter table public.profiles add column if not exists living text default '';
alter table public.profiles add column if not exists debt text default '';
alter table public.profiles add column if not exists relationship_goal text default '';
alter table public.profiles add column if not exists kids_plan text default '';
alter table public.profiles add column if not exists mbti text default '';
alter table public.profiles add column if not exists work_hours text default '';
alter table public.profiles add column if not exists interests jsonb not null default '[]'::jsonb;
alter table public.profiles add column if not exists personality jsonb not null default '[]'::jsonb;
alter table public.profiles add column if not exists habits jsonb not null default '[]'::jsonb;
alter table public.profiles add column if not exists habits_other text default '';
-- 希望對方的條件（選填，會公開）
alter table public.profiles add column if not exists req_marital text default '';
alter table public.profiles add column if not exists req_age_min text default '';
alter table public.profiles add column if not exists req_age_max text default '';
alter table public.profiles add column if not exists req_kids text default '';
alter table public.profiles add column if not exists req_habits jsonb not null default '[]'::jsonb;

alter table public.profiles enable row level security;

-- 用 security definer 函式檢查是否為管理員，避免 profiles 的 RLS policy 直接查詢自己造成遞迴
create or replace function public.is_admin(uid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = uid), false);
$$;

drop policy if exists "profiles_select_authenticated" on public.profiles;
drop policy if exists "profiles_select_visible"       on public.profiles;
drop policy if exists "profiles_insert_own"           on public.profiles;
drop policy if exists "profiles_update_own"           on public.profiles;
drop policy if exists "profiles_update_admin"         on public.profiles;
drop policy if exists "profiles_delete_own"           on public.profiles;

-- 已登入的人看得到：審核通過的公開登記、自己的那一筆、以及管理員看全部（審核用）
create policy "profiles_select_visible"
  on public.profiles for select
  to authenticated
  using (photo_status = 'approved' or auth.uid() = id or public.is_admin(auth.uid()));

-- 只能新增自己的那一筆
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- 修改自己的那一筆
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- 管理員可以修改任何一筆（審核通過/退回、發放獎勵點數）
create policy "profiles_update_admin"
  on public.profiles for update
  to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create policy "profiles_delete_own"
  on public.profiles for delete
  to authenticated
  using (auth.uid() = id);

-- 管理員可以移除任何一筆登記（例如檢舉查證屬實後下架）
drop policy if exists "profiles_delete_admin" on public.profiles;
create policy "profiles_delete_admin"
  on public.profiles for delete
  to authenticated
  using (public.is_admin(auth.uid()));

-- ============================================================
-- 2) applications：認養申請（一位申請人對一位登記對象只有一筆）
-- ============================================================
create table if not exists public.applications (
  id           uuid primary key default gen_random_uuid(),
  from_user    uuid not null references auth.users(id) on delete cascade,
  to_user      uuid not null references auth.users(id) on delete cascade,
  stage        int  not null default 1,      -- 1 書面審查 / 2 價值觀評估 / 3 日常觀察
  status       text not null default 'open' check (status in ('open','rejected')),
  -- 注意：第一／二階段的回答不放在這裡，而是放在 application_answers（見第 10 節），
  -- 因為收件方要「付費解鎖」才看得到，權限必須由資料庫控管，不能只靠前端遮住。
  a2_questions jsonb,                        -- 這次實際出的第二階段題目（由 pet 從題庫挑選）
  a1_unlocked  boolean not null default false, -- 收件方是否已付費解鎖第一階段詳細回答
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
alter table public.applications add column if not exists a1_unlocked boolean not null default false;
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
-- 一鍵通關：跳過三階段審核直接解鎖時標記，讓畫面知道這筆沒有真的作答
alter table public.applications add column if not exists skipped boolean not null default false;

alter table public.applications enable row level security;

drop policy if exists "applications_select_participant" on public.applications;
drop policy if exists "applications_insert_as_from"      on public.applications;
drop policy if exists "applications_update_participant"  on public.applications;

-- 只有申請人本人或被申請的對象看得到這筆申請
create policy "applications_select_participant"
  on public.applications for select
  to authenticated
  using (auth.uid() = from_user or auth.uid() = to_user);

-- 只能以自己的身分送出申請
create policy "applications_insert_as_from"
  on public.applications for insert
  to authenticated
  with check (auth.uid() = from_user);

-- 雙方都能更新（回答問題、通過/婉拒、同意解鎖）
create policy "applications_update_participant"
  on public.applications for update
  to authenticated
  using (auth.uid() = from_user or auth.uid() = to_user)
  with check (auth.uid() = from_user or auth.uid() = to_user);

-- 管理員移除違規登記時，一併清掉相關申請
drop policy if exists "applications_delete_admin" on public.applications;
create policy "applications_delete_admin"
  on public.applications for delete
  to authenticated
  using (public.is_admin(auth.uid()));

-- ============================================================
-- 3) updated_at 自動更新
-- ============================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_touch on public.profiles;
create trigger trg_profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_applications_touch on public.applications;
create trigger trg_applications_touch before update on public.applications
  for each row execute function public.touch_updated_at();

-- ============================================================
-- 4) 新帳號註冊時，自動建立一筆空白 profiles
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

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
  using (bucket_id = 'verify' and public.is_admin(auth.uid()));

create policy "verify_admin_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'verify' and public.is_admin(auth.uid()));

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
  using (bucket_id = 'stage-photos' and public.is_admin(auth.uid()));

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
  target_id  uuid references public.profiles(id) on delete cascade,
  by_id      uuid references public.profiles(id) on delete set null,
  why        text not null,
  done       boolean not null default false,
  created_at timestamptz default now()
);

alter table public.reports enable row level security;

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
  using (public.is_admin(auth.uid()));

create policy "reports_update_admin"
  on public.reports for update
  to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

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
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

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
comment on column public.profiles.canned is '自訂罐頭回覆庫覆蓋值（所有會員都可使用，對照 template_master 的主檔）';

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
returns trigger language plpgsql as $$
begin
  -- 只管「透過 API 用 authenticated 身分打進來」的請求；
  -- 你自己在 Supabase 後台 SQL Editor／Table Editor 用 postgres/service_role 身分
  -- 直接編輯資料列不受影響（那已經是需要登入你自己 Supabase 帳號才碰得到的層級）。
  if auth.role() = 'authenticated'
     and coalesce(current_setting('app.bypass_profile_guard', true), '') <> 'on'
     and not public.is_admin(auth.uid()) then
    new.is_admin    := old.is_admin;
    new.credits     := old.credits;
    new.credit_log  := old.credit_log;
    new.bonus_given := old.bonus_given;
    new.verify_deleted_at := old.verify_deleted_at;
    new.bonus_credits := old.bonus_credits;
    if new.photo_status = 'approved' and old.photo_status is distinct from 'approved' then
      new.photo_status := old.photo_status; new.photo_reason := old.photo_reason;
    end if;
    if new.verify_status = 'approved' and old.verify_status is distinct from 'approved' then
      new.verify_status := old.verify_status; new.verify_reason := old.verify_reason;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_profile_privileged on public.profiles;
create trigger trg_guard_profile_privileged before update on public.profiles
  for each row execute function public.guard_profile_privileged();

-- 小工具：在 credit_log 最前面加一筆紀錄，並裁到最多 50 筆
create or replace function public.credit_log_prepend(old_log jsonb, entry_obj jsonb, cap int default 50)
returns jsonb language sql immutable as $$
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
create or replace function public.spend_credits_for(p_action text, p_detail text default null)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare v_cost int; v_label text; v_bal int; v_row public.profiles;
begin
  perform public.settle_bonus_credits(auth.uid());
  case p_action
    when 'vet_review'  then v_cost := 1; v_label := '診療　主治獸醫評估';
    when 'deep_review' then v_cost := 3; v_label := '進階診斷　客製第二階段問題';
    else raise exception '未知的扣點項目：%', p_action;
  end case;

  select credits into v_bal from public.profiles where id = auth.uid() for update;
  if v_bal is null then raise exception '找不到你的帳號資料'; end if;
  if v_bal < v_cost then raise exception '點數不足'; end if;

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.profiles set
    credits = credits - v_cost,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', v_label || coalesce('　' || p_detail, ''), 'd', -v_cost))
  where id = auth.uid()
  returning * into v_row;
  perform set_config('app.bypass_profile_guard', '', true);
  return v_row;
end $$;

-- 提出認養申請：扣掛號費＋建立申請案件，包在同一個交易裡。
-- 只要有一步失敗（例如已經申請過、對方尚未審核通過），整個都會回滾，
-- 不會出現「錢扣了但申請沒送出」這種需要另外退款的中間狀態。
create or replace function public.apply_to(p_to uuid, p_answers jsonb)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_cost constant int := 1;   -- 掛號費，價格由伺服器決定，不接受前端傳金額
  v_bal int; v_app public.applications;
begin
  if p_to = auth.uid() then raise exception '不能對自己提出申請'; end if;
  if not exists (
    select 1 from public.profiles
    where id = p_to and photo_status = 'approved' and verify_status = 'approved'
  ) then
    raise exception '對方尚未通過審核，暫時無法申請';
  end if;

  select credits into v_bal from public.profiles where id = auth.uid() for update;
  if v_bal is null or v_bal < v_cost then raise exception '掛號費不足'; end if;

  insert into public.applications(from_user, to_user, stage, status, a1, paid)
  values (auth.uid(), p_to, 1, 'open', p_answers, v_cost)
  returning * into v_app;

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.profiles set
    credits = credits - v_cost,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '掛號　向 ' || (select name from public.profiles where id = p_to) || ' 提出申請', 'd', -v_cost))
  where id = auth.uid();
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;

-- 退回逾期未處理的掛號費：伺服器自己重新檢查一次天數／歸屬／是否已退過，
-- 不相信前端傳來的任何數字，前端只能傳「是哪一筆申請」。
create or replace function public.refund_application(p_app_id uuid)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare v_app public.applications; v_row public.profiles;
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
  update public.profiles set
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
create or replace function public.admin_add_credits(target uuid, amount int, reason text, ref text default null)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare v_row public.profiles;
begin
  if not (public.is_admin(auth.uid()) or auth.role() = 'service_role') then
    raise exception '只有管理員可以使用';
  end if;
  if amount = 0 then raise exception '金額不能是 0'; end if;

  if ref is not null and exists (
    select 1 from public.profiles, jsonb_array_elements(coalesce(credit_log, '[]'::jsonb)) elem
    where id = target and elem->>'ref' = ref
  ) then
    select * into v_row from public.profiles where id = target;
    return v_row;   -- 同一筆訂單重複呼叫，直接回傳目前狀態，不重複加點
  end if;

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.profiles set
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

-- 只有申請人本人可以改自己的答案
create policy "answers_update_owner"
  on public.application_answers for update
  to authenticated
  using (exists (select 1 from public.applications a where a.id = application_id and a.from_user = auth.uid()))
  with check (exists (select 1 from public.applications a where a.id = application_id and a.from_user = auth.uid()));

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
returns trigger language plpgsql as $$
begin
  if auth.role() = 'authenticated'
     and coalesce(current_setting('app.bypass_app_guard', true), '') <> 'on'
     and not public.is_admin(auth.uid()) then
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
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_application on public.applications;
create trigger trg_guard_application before update on public.applications
  for each row execute function public.guard_application_privileged();

-- ── 我的答題紀錄：把送出的答案存進申請人自己的 profiles.answer_bank ──
-- 以「題目文字」去重（同一題只留最新的答案），最多保留 100 筆。
create or replace function public.answer_bank_merge(old_bank jsonb, entries jsonb, cap int default 100)
returns jsonb language sql immutable as $$
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
create or replace function public.apply_to(p_to uuid, p_answers jsonb, p_questions jsonb default '[]'::jsonb)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_cost constant int := 1;   -- 掛號費，價格由伺服器決定
  v_bal int; v_app public.applications; v_entries jsonb;
begin
  perform public.settle_bonus_credits(auth.uid());
  if p_to = auth.uid() then raise exception '不能對自己提出申請'; end if;
  if not exists (
    select 1 from public.profiles
    where id = p_to and photo_status = 'approved' and verify_status = 'approved'
  ) then
    raise exception '對方尚未通過審核，暫時無法申請';
  end if;

  select credits into v_bal from public.profiles where id = auth.uid() for update;
  if v_bal is null or v_bal < v_cost then raise exception '掛號費不足'; end if;

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
  update public.profiles set
    credits = credits - v_cost,
    answer_bank = public.answer_bank_merge(answer_bank, coalesce(v_entries,'[]'::jsonb)),
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '掛號　向 ' || (select name from public.profiles where id = p_to) || ' 提出申請', 'd', -v_cost))
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

  select credits into v_bal from public.profiles where id = auth.uid() for update;
  if v_bal is null or v_bal < v_cost then raise exception '點數不足'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set a1_unlocked = true where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.profiles set
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
    select credits into v_bal from public.profiles where id = auth.uid() for update;
    if v_bal is null or v_bal < v_cost then raise exception '點數不足'; end if;
    perform set_config('app.bypass_profile_guard', 'on', true);
    update public.profiles set
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
create or replace function public.unlock_stage3(p_app_id uuid)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_cost constant int := 3;
  v_app public.applications; v_bal int;
begin
  perform public.settle_bonus_credits(auth.uid());
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.from_user <> auth.uid() then raise exception '這不是你送出的申請'; end if;
  if v_app.stage <> 3 then raise exception '這筆申請還沒進入第三階段'; end if;
  if v_app.unlock_from then return v_app; end if;   -- 已解鎖就不再收費

  select credits into v_bal from public.profiles where id = auth.uid() for update;
  if v_bal is null or v_bal < v_cost then raise exception '點數不足'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set unlock_from = true where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.profiles set
    credits = credits - v_cost,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '解鎖　對方的日常觀察資訊', 'd', -v_cost))
  where id = auth.uid();
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;

-- 收件方同意解鎖（免費，維持原本設計）
create or replace function public.consent_unlock_to(p_app_id uuid)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare v_app public.applications;
begin
  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.to_user <> auth.uid() then raise exception '這不是你收到的申請'; end if;
  if v_app.stage <> 3 then raise exception '這筆申請還沒進入第三階段'; end if;

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
begin
  if p_uid is null then return; end if;
  select bonus_credits, credits into v_bank, v_credits from public.profiles where id = p_uid for update;
  if v_bank is null or jsonb_array_length(v_bank) = 0 then return; end if;

  v_remaining := coalesce(v_credits, 0);
  for v_entry in select * from jsonb_array_elements(v_bank) loop
    if (v_entry->>'expires_at')::timestamptz <= now() then
      v_deduct := least(v_remaining, (v_entry->>'amount')::int);
      v_remaining := v_remaining - v_deduct;
      v_total_deduct := v_total_deduct + v_deduct;
    else
      v_keep := v_keep || jsonb_build_array(v_entry);
    end if;
  end loop;

  if jsonb_array_length(v_keep) < jsonb_array_length(v_bank) then
    perform set_config('app.bypass_profile_guard', 'on', true);
    update public.profiles set
      bonus_credits = v_keep,
      credits = credits - v_total_deduct,
      credit_log = case when v_total_deduct > 0
        then public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '一鍵通關獎勵點數逾期收回', 'd', -v_total_deduct))
        else credit_log end
    where id = p_uid;
    perform set_config('app.bypass_profile_guard', '', true);
  end if;
end $$;

-- 一鍵通關：對方開放的話，申請人可以付 10 點直接跳到第三階段、雙方互相解鎖，
-- 不用照走問卷與人工審核。這 10 點會加進登記人的帳上，但標記 14 天後到期，
-- 到期沒花完的部分會被上面的 settle_bonus_credits 收回。
create or replace function public.skip_to_unlock(p_app_id uuid)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare
  v_cost constant int := 10;
  v_app public.applications; v_owner public.profiles; v_bal int;
begin
  perform public.settle_bonus_credits(auth.uid());

  select * into v_app from public.applications where id = p_app_id for update;
  if v_app is null then raise exception '找不到這筆申請'; end if;
  if v_app.from_user <> auth.uid() then raise exception '這不是你送出的申請'; end if;
  if v_app.status <> 'open' then raise exception '這筆申請已經結束了'; end if;
  if v_app.stage >= 3 then raise exception '這筆申請已經在第三階段了'; end if;

  select * into v_owner from public.profiles where id = v_app.to_user for update;
  if v_owner is null or not coalesce(v_owner.allow_skip, false) then
    raise exception '對方沒有開放一鍵通關';
  end if;

  select credits into v_bal from public.profiles where id = auth.uid();
  if v_bal is null or v_bal < v_cost then raise exception '點數不足'; end if;

  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set
    stage = 3, a1_unlocked = true, stage2_paid = true,
    unlock_from = true, unlock_to = true,
    consent_at = coalesce(consent_at, now()),
    skipped = true
  where id = p_app_id returning * into v_app;
  perform set_config('app.bypass_app_guard', '', true);

  perform set_config('app.bypass_profile_guard', 'on', true);
  update public.profiles set
    credits = credits - v_cost,
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '一鍵通關　跳過審查流程', 'd', -v_cost))
  where id = auth.uid();

  update public.profiles set
    credits = credits + v_cost,
    bonus_credits = coalesce(bonus_credits, '[]'::jsonb)
      || jsonb_build_array(jsonb_build_object('amount', v_cost, 'granted_at', now(), 'expires_at', now() + interval '14 days')),
    credit_log = public.credit_log_prepend(credit_log, jsonb_build_object('at', now(), 't', '有人使用一鍵通關　獎勵點數（14 天內要花完）', 'd', v_cost))
  where id = v_app.to_user;
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;

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
  update public.profiles
    set answer_bank = public.answer_bank_merge(answer_bank, coalesce(v_entries,'[]'::jsonb))
    where id = auth.uid();
  perform set_config('app.bypass_profile_guard', '', true);

  return v_app;
end $$;

-- ============================================================
-- 11) 把自己設成管理員（審核台權限）
--    這行不會自動執行——執行完上面全部之後，自己先用這個帳號登入一次，
--    再回到 SQL Editor，把 <你的帳號 email> 換成自己的 email，單獨執行這一段：
--
--    update public.profiles set is_admin = true
--    where id = (select id from auth.users where email = '<你的帳號 email>');
-- ============================================================
