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
  species     text not null default '' check (species in ('', 'cat', 'dog')),
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
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- 若資料表已存在（舊版本先執行過這份腳本），補上新欄位
alter table public.profiles add column if not exists credits int not null default 5;
alter table public.profiles add column if not exists credit_log jsonb not null default '[]'::jsonb;
alter table public.profiles alter column credits set default 5;

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_authenticated" on public.profiles;
drop policy if exists "profiles_insert_own"           on public.profiles;
drop policy if exists "profiles_update_own"           on public.profiles;
drop policy if exists "profiles_delete_own"           on public.profiles;

-- 已登入的人都能看佈告欄（未登入者一律看不到，anon 沒有任何 policy）
create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

-- 只能新增/修改/刪除自己的那一筆
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "profiles_delete_own"
  on public.profiles for delete
  to authenticated
  using (auth.uid() = id);

-- ============================================================
-- 2) applications：認養申請（一位申請人對一位登記對象只有一筆）
-- ============================================================
create table if not exists public.applications (
  id           uuid primary key default gen_random_uuid(),
  from_user    uuid not null references auth.users(id) on delete cascade,
  to_user      uuid not null references auth.users(id) on delete cascade,
  stage        int  not null default 1,      -- 1 書面審查 / 2 價值觀評估 / 3 日常觀察
  status       text not null default 'open' check (status in ('open','rejected')),
  a1           jsonb,                        -- 第一階段回答
  a2           jsonb,                        -- 第二階段回答
  a2_questions jsonb,                        -- 這次實際出的第二階段題目（由 pet 從題庫挑選）
  unlock_from  boolean not null default false,
  unlock_to    boolean not null default false,
  note         text,                         -- 被申請方寫給申請人看的話（例如婉拒理由）
  keeper_note  text,                         -- 申請人自己的私人筆記，只有申請人看得到
  vet          text,                         -- 主治獸醫（AI）評估結果，快取起來避免重複收費
  vet_at       timestamptz,
  paid         int not null default 0,       -- 送出申請時付的掛號費點數
  refunded     boolean not null default false, -- 掛號費是否已退回申請人
  created_at   timestamptz default now(),
  updated_at   timestamptz default now(),
  unique (from_user, to_user),
  check (from_user <> to_user)
);

-- 若資料表已存在，補上新欄位
alter table public.applications add column if not exists keeper_note text;
alter table public.applications add column if not exists vet text;
alter table public.applications add column if not exists vet_at timestamptz;
alter table public.applications add column if not exists paid int not null default 0;
alter table public.applications add column if not exists refunded boolean not null default false;

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
