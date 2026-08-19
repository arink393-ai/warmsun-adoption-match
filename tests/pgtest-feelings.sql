-- 😊 對話後的感受紀錄（私人自我回報）
--
-- 這一份守四件事：
--   (1) **白名單與必須至少選一個。** 不在選項表裡的字直接被濾掉，
--       全部被濾掉的話要報錯，不能默默存一列空的。
--   (2) **同一天在同一段對話裡重覆紀錄，是更新，不是疊加。**
--       不然「最近 5 次有 4 次標記有壓力」這種統計會被手癢多點幾下弄假。
--   (3) **只有自己看得到——包括站方帳號在內。** 這是 RLS 層級的保證，
--       不是前端不顯示。
--   (4) **只有第二階段之後的對話才能記，而且要是對話的當事人。**
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
-- 一、白名單、至少選一個、格式錯誤
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f3a01';
  b uuid := '00000000-0000-0000-0000-0000000f3a02';
  app_row public.applications; r jsonb;
begin
  raise notice '=== 白名單與必填 ===';
  perform pg_temp.mkuser(a, '甲'); perform pg_temp.mkuser(b, '乙');
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 2 where id = app_row.id;

  -- 混合合法與不合法的 key：不合法的被濾掉，合法的留著
  r := public.log_chat_feeling(app_row.id, '["respected","not_a_real_chip","stressed"]'::jsonb);
  perform pg_temp.ok((r->'chips') @> '"respected"' and (r->'chips') @> '"stressed"'
    and jsonb_array_length(r->'chips') = 2,
    '不合法的 key 被濾掉，合法的兩個留著', r::text);

  -- 全部都不合法：報錯，不會默默存一列空的
  begin
    perform public.log_chat_feeling(app_row.id, '["not_real","also_fake"]'::jsonb);
    perform pg_temp.ok(false, '全部都不合法時會報錯');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%請至少選一個感受%', '全部都不合法時會報錯', sqlerrm);
  end;

  -- 空陣列：一樣報錯
  begin
    perform public.log_chat_feeling(app_row.id, '[]'::jsonb);
    perform pg_temp.ok(false, '沒選任何一個會報錯');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%請至少選一個感受%', '沒選任何一個會報錯', sqlerrm);
  end;

  -- 格式不是陣列：報錯
  begin
    perform public.log_chat_feeling(app_row.id, '{"k":"v"}'::jsonb);
    perform pg_temp.ok(false, '不是陣列格式會報錯');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%chips 格式不正確%', '不是陣列格式會報錯', sqlerrm);
  end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、同一天重覆紀錄是更新，不是疊加
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f3b01';
  b uuid := '00000000-0000-0000-0000-0000000f3b02';
  app_row public.applications; n int;
begin
  raise notice '=== 同一天重覆紀錄 ===';
  perform pg_temp.mkuser(a, '丙'); perform pg_temp.mkuser(b, '丁');
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 2 where id = app_row.id;

  perform public.log_chat_feeling(app_row.id, '["stressed"]'::jsonb);
  perform public.log_chat_feeling(app_row.id, '["respected","myself"]'::jsonb);

  select count(*) into n from public.chat_feelings
   where application_id = app_row.id and user_id = a;
  perform pg_temp.ok(n = 1, '同一天記兩次，資料庫裡只有一列', n::text);

  perform pg_temp.ok(
    (select chips from public.chat_feelings
      where application_id = app_row.id and user_id = a) = '["myself","respected"]'::jsonb
    or (select chips @> '"respected"'::jsonb and chips @> '"myself"'::jsonb and not (chips @> '"stressed"'::jsonb)
          from public.chat_feelings where application_id = app_row.id and user_id = a),
    '而且內容是最後一次紀錄的（更新，不是疊加）');
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、隱私：只有自己看得到，包括站方帳號在內
-- ════════════════════════════════════════════════════════════
--   log_chat_feeling／chat_feeling_summary 是 security definer，這裡測的
--   是「萬一哪天前端改成直接 select」那條路：postgres 這個角色本身是
--   RLS 的例外（超級使用者與資料表擁有者預設不受 RLS 限制），所以直接
--   select 之前要先切成 authenticated 角色，RLS 政策才會真的生效——
--   跟 pgtest-companion.sql 第五節「直接讀表」用的是同一招。
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f3c01';
  b uuid := '00000000-0000-0000-0000-0000000f3c02';
  admin uuid := '00000000-0000-0000-0000-0000000f3c09';
  app_row public.applications; n int; s jsonb;
begin
  raise notice '=== 隱私 ===';
  perform pg_temp.mkuser(a, '戊'); perform pg_temp.mkuser(b, '己'); perform pg_temp.mkuser(admin, '站長');
  update public.match_profiles set is_admin = true where id = admin;

  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 2 where id = app_row.id;
  perform public.log_chat_feeling(app_row.id, '["boundary_violated"]'::jsonb);

  -- 對方呼叫摘要函式，看到的是「自己」的摘要（0，因為他自己沒記錄過），不是甲的
  perform set_config('request.jwt.claim.sub', b::text, true);
  s := public.chat_feeling_summary(app_row.id);
  perform pg_temp.ok((s->>'total')::int = 0, '對方呼叫摘要，看到的是自己的（0 筆），不是甲的紀錄', s::text);

  perform set_config('role', 'authenticated', true);

  -- 對方（同一段對話的參與者）直接查表：一列都看不到
  select count(*) into n from public.chat_feelings where application_id = app_row.id;
  perform pg_temp.ok(n = 0, '對方直接查表，一列都看不到', n::text);

  -- 站方帳號也一樣看不到——這是整節最重要的一條
  perform set_config('request.jwt.claim.sub', admin::text, true);
  select count(*) into n from public.chat_feelings where application_id = app_row.id;
  perform pg_temp.ok(n = 0, '就算是站方帳號，也看不到別人的感受紀錄', n::text);

  -- 甲自己查表看得到
  perform set_config('request.jwt.claim.sub', a::text, true);
  select count(*) into n from public.chat_feelings where application_id = app_row.id;
  perform pg_temp.ok(n = 1, '自己查表看得到自己那一列', n::text);

  perform set_config('role', 'none', true);

  -- 甲呼叫摘要函式，看得到自己的
  s := public.chat_feeling_summary(app_row.id);
  perform pg_temp.ok((s->>'total')::int = 1 and (s->'counts'->>'boundary_violated')::int = 1,
    '自己呼叫摘要，看得到自己剛記錄的那一筆', s::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、最近 5 次的統計，以及邊界情況
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f3d01';
  b uuid := '00000000-0000-0000-0000-0000000f3d02';
  x uuid := '00000000-0000-0000-0000-0000000f3d09';
  app_row public.applications; s jsonb; i int;
begin
  raise notice '=== 統計與邊界情況 ===';
  perform pg_temp.mkuser(a, '庚'); perform pg_temp.mkuser(b, '辛');
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);

  -- 第二階段之前不能記
  begin
    perform public.log_chat_feeling(app_row.id, '["respected"]'::jsonb);
    perform pg_temp.ok(false, '第二階段之前不能記錄感受');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%第二階段後才有對話室%', '第二階段之前不能記錄感受', sqlerrm);
  end;
  update public.applications set stage = 2 where id = app_row.id;

  -- 灌 7 天份的紀錄，其中「有壓力」出現在最近 4 天（含今天）
  for i in 0..6 loop
    insert into public.chat_feelings(application_id, user_id, chips, logged_date)
      values (app_row.id, a,
        case when i < 4 then '["stressed"]'::jsonb else '["respected"]'::jsonb end,
        current_date - i)
      on conflict (application_id, user_id, logged_date)
      do update set chips = excluded.chips;
  end loop;

  s := public.chat_feeling_summary(app_row.id);
  perform pg_temp.ok((s->>'total')::int = 5, '摘要只看最近 5 次，不是全部 7 次', s::text);
  perform pg_temp.ok((s->'counts'->>'stressed')::int = 4,
    '最近 5 次對話中，有 4 次標記「有壓力」——跟灌入的資料一致', s::text);
  perform pg_temp.ok(coalesce((s->'counts'->>'respected')::int, 0) = 1,
    '最近 5 次裡有 1 次是「被尊重」', s::text);

  -- 不是對話的參與者：不能記錄，也不能看摘要
  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.log_chat_feeling(app_row.id, '["respected"]'::jsonb);
    perform pg_temp.ok(false, '不是這段對話的人不能記錄');
  exception when others then perform pg_temp.ok(true, '不是這段對話的人不能記錄'); end;
  begin
    perform public.chat_feeling_summary(app_row.id);
    perform pg_temp.ok(false, '不是這段對話的人也看不到摘要');
  exception when others then perform pg_temp.ok(true, '不是這段對話的人也看不到摘要'); end;

  raise notice '=== 感受紀錄測試結束 ===';
end $$;
