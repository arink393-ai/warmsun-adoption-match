-- 📝 Reality Check：約會後的私人日記
--
-- 這一份守五件事：
--   (1) **完全私人，沒有分享開關。** RLS 只認 user_id = auth.uid()，
--       沒有例外——包括站方帳號在內都看不到，連「有沒有寫過」都不會透露。
--   (2) **一段關係可以寫很多篇。** 不像第 38 節的 chat_feelings 同一天
--       會更新，這裡見幾次面就能寫幾篇，沒有去重。
--   (3) **只收白名單裡的 key，每題有長度上限。**
--   (4) **可以刪除自己寫的，刪不到別人的。**
--   (5) **要通過第二階段、而且是對話的當事人才能寫。**
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

create or replace function pg_temp.mkuser(uid uuid, nm text) returns void
language plpgsql as $$
begin
  insert into auth.users(id, email) values (uid, uid::text || '@t.local') on conflict do nothing;
  insert into public.match_profiles(id, name, kind, species, gender, consent, account_status,
      photo_status, verify_status)
    values (uid, nm, 'pet', 'cat', 'f', true, 'active', 'approved', 'approved')
    on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      species = excluded.species, gender = excluded.gender, consent = excluded.consent,
      account_status = 'active',
      photo_status = 'approved', verify_status = 'approved', posting_locked = false;
end $$;

-- ════════════════════════════════════════════════════════════
-- 一、寫一篇：白名單、修剪、長度上限
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f4a01';
  b uuid := '00000000-0000-0000-0000-0000000f4a02';
  app_row public.applications; r jsonb;
begin
  raise notice '=== 寫一篇 ===';
  perform pg_temp.mkuser(a, '甲'); perform pg_temp.mkuser(b, '乙');
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 2 where id = app_row.id;

  r := public.submit_reality_check(app_row.id, '2026-08-10'::date, jsonb_build_object(
    'matched_profile', '  幾乎一致  ',
    'not_a_real_key', '這個不該被存進去',
    'boundary_moments', ''
  ));
  perform pg_temp.ok((r->'answers'->>'matched_profile') = '幾乎一致',
    '合法的回答存得進去，而且前後空白被修剪', r::text);
  perform pg_temp.ok(not (r->'answers' ? 'not_a_real_key'),
    '不在白名單裡的 key 被濾掉', r::text);
  perform pg_temp.ok(not (r->'answers' ? 'boundary_moments'),
    '只有空白的回答不會存進去（等於沒填）', r::text);
  perform pg_temp.ok((r->>'met_on') = '2026-08-10', '見面日期存得對', r::text);

  -- 超長內容：截斷到 500 字，不是報錯（私人日記，不用逼使用者精簡）
  r := public.submit_reality_check(app_row.id, current_date, jsonb_build_object('note', repeat('字', 600)));
  perform pg_temp.ok(char_length(r->'answers'->>'note') = 500,
    '超過 500 字的內容會被截斷到 500 字，不是報錯', char_length(r->'answers'->>'note')::text);

  -- 未來日期：報錯
  begin
    perform public.submit_reality_check(app_row.id, current_date + 1, '{}'::jsonb);
    perform pg_temp.ok(false, '見面日期不能是未來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%不能是未來%', '見面日期不能是未來', sqlerrm);
  end;

  -- 沒給日期：預設今天
  r := public.submit_reality_check(app_row.id, null, '{}'::jsonb);
  perform pg_temp.ok((r->>'met_on') = current_date::text, '沒給日期時預設今天', r::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、一段關係可以寫很多篇，不會互相覆蓋
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f4b01';
  b uuid := '00000000-0000-0000-0000-0000000f4b02';
  app_row public.applications; n int; rows public.reality_checks[];
begin
  raise notice '=== 可以寫很多篇 ===';
  perform pg_temp.mkuser(a, '丙'); perform pg_temp.mkuser(b, '丁');
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 2 where id = app_row.id;

  perform public.submit_reality_check(app_row.id, '2026-08-01'::date,
    jsonb_build_object('next_step', '繼續認識下去'));
  perform public.submit_reality_check(app_row.id, '2026-08-15'::date,
    jsonb_build_object('next_step', '再觀察看看'));

  select count(*) into n from public.reality_checks
   where application_id = app_row.id and user_id = a;
  perform pg_temp.ok(n = 2, '同一段關係寫兩篇，資料庫裡就是兩列，不會互相覆蓋', n::text);

  select array_agg(x order by x.met_on desc) into rows from public.list_reality_checks(app_row.id) x;
  perform pg_temp.ok(rows[1].met_on::text = '2026-08-15' and rows[2].met_on::text = '2026-08-01',
    'list_reality_checks 依見面日期新到舊排序',
    rows[1].met_on::text || ' / ' || rows[2].met_on::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、隱私：只有自己看得到，包括站方帳號在內
-- ════════════════════════════════════════════════════════════
--   跟 pgtest-feelings.sql 第三節同一招：postgres 這個角色本身不受 RLS
--   限制，直接 select 之前要先切成 authenticated，RLS 政策才會真的生效。
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f4c01';
  b uuid := '00000000-0000-0000-0000-0000000f4c02';
  admin uuid := '00000000-0000-0000-0000-0000000f4c09';
  app_row public.applications; n int; rows public.reality_checks[];
begin
  raise notice '=== 隱私 ===';
  perform pg_temp.mkuser(a, '戊'); perform pg_temp.mkuser(b, '己'); perform pg_temp.mkuser(admin, '站長');
  update public.match_profiles set is_admin = true where id = admin;

  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 2 where id = app_row.id;
  perform public.submit_reality_check(app_row.id, current_date,
    jsonb_build_object('boundary_moments', '有一次我說想先回家，對方馬上就答應了'));

  -- 對方呼叫 list_reality_checks，看到的是自己的（空），不是甲的
  perform set_config('request.jwt.claim.sub', b::text, true);
  select array_agg(x) into rows from public.list_reality_checks(app_row.id) x;
  perform pg_temp.ok(rows is null, '對方呼叫 list，看到的是自己的（沒寫過，所以是空的），不是甲的紀錄');

  perform set_config('role', 'authenticated', true);

  -- 對方直接查表：一列都看不到
  select count(*) into n from public.reality_checks where application_id = app_row.id;
  perform pg_temp.ok(n = 0, '對方直接查表，一列都看不到', n::text);

  -- 站方帳號也一樣看不到
  perform set_config('request.jwt.claim.sub', admin::text, true);
  select count(*) into n from public.reality_checks where application_id = app_row.id;
  perform pg_temp.ok(n = 0, '就算是站方帳號，也看不到別人寫的日記', n::text);

  -- 甲自己查表看得到
  perform set_config('request.jwt.claim.sub', a::text, true);
  select count(*) into n from public.reality_checks where application_id = app_row.id;
  perform pg_temp.ok(n = 1, '自己查表看得到自己那一篇', n::text);

  perform set_config('role', 'none', true);

  select array_agg(x) into rows from public.list_reality_checks(app_row.id) x;
  perform pg_temp.ok(array_length(rows,1) = 1 and rows[1].answers->>'boundary_moments' is not null,
    '自己呼叫 list，看得到自己剛寫的那一篇');
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、刪除：只能刪自己寫的
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f4d01';
  b uuid := '00000000-0000-0000-0000-0000000f4d02';
  app_row public.applications; r jsonb; rid uuid; n int;
begin
  raise notice '=== 刪除 ===';
  perform pg_temp.mkuser(a, '庚'); perform pg_temp.mkuser(b, '辛');
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 2 where id = app_row.id;
  r := public.submit_reality_check(app_row.id, current_date, jsonb_build_object('note', '測試用'));
  rid := (r->>'id')::uuid;

  -- 對方想刪甲寫的那一篇：刪不到
  perform set_config('request.jwt.claim.sub', b::text, true);
  begin
    perform public.delete_reality_check(rid);
    perform pg_temp.ok(false, '對方刪不到甲寫的日記');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%不是你寫的%', '對方刪不到甲寫的日記', sqlerrm);
  end;
  select count(*) into n from public.reality_checks where id = rid;
  perform pg_temp.ok(n = 1, '刪除失敗，那一篇還在', n::text);

  -- 甲自己刪：刪得到
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.delete_reality_check(rid);
  select count(*) into n from public.reality_checks where id = rid;
  perform pg_temp.ok(n = 0, '本人可以刪掉自己寫的那一篇', n::text);

  -- 刪不存在的 id：報錯
  begin
    perform public.delete_reality_check(rid);
    perform pg_temp.ok(false, '刪一篇已經不存在的日記會報錯');
  exception when others then perform pg_temp.ok(true, '刪一篇已經不存在的日記會報錯'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 五、邊界情況：階段與當事人身分
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f4e01';
  b uuid := '00000000-0000-0000-0000-0000000f4e02';
  x uuid := '00000000-0000-0000-0000-0000000f4e09';
  app_row public.applications;
begin
  raise notice '=== 邊界情況 ===';
  perform pg_temp.mkuser(a, '壬'); perform pg_temp.mkuser(b, '癸');
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);

  begin
    perform public.submit_reality_check(app_row.id, current_date, '{}'::jsonb);
    perform pg_temp.ok(false, '第二階段之前不能寫');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%第二階段後才能寫%', '第二階段之前不能寫', sqlerrm);
  end;
  update public.applications set stage = 2 where id = app_row.id;

  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.submit_reality_check(app_row.id, current_date, '{}'::jsonb);
    perform pg_temp.ok(false, '不是這段對話的人不能寫');
  exception when others then perform pg_temp.ok(true, '不是這段對話的人不能寫'); end;
  begin
    perform public.list_reality_checks(app_row.id);
    perform pg_temp.ok(false, '不是這段對話的人也讀不到（回傳空集合而不是報錯也算通過）');
  exception when others then perform pg_temp.ok(true, '不是這段對話的人也讀不到'); end;

  raise notice '=== Reality Check 測試結束 ===';
end $$;
