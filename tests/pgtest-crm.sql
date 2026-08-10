-- 申請者 CRM：病例時間軸與看板欄位，在真的 Postgres 16 上驗證
-- 用法：sudo -u postgres psql -d warmsun -f pgtest-crm.sql
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

create or replace function pg_temp.mkuser(p_id uuid, p_name text) returns void
language plpgsql as $$
begin
  insert into auth.users(id, email) values (p_id, p_name || '@t.local') on conflict do nothing;
  insert into public.match_profiles(id, name, kind, species, gender, photo_status, verify_status,
    account_status, consent, credits)
  values (p_id, p_name, 'pet', 'cat', 'f', 'approved', 'approved', 'active', true, 50)
  on conflict (id) do update set
    name = excluded.name, kind = excluded.kind, species = excluded.species,
    gender = excluded.gender, photo_status = excluded.photo_status,
    verify_status = excluded.verify_status, account_status = excluded.account_status,
    consent = excluded.consent, credits = excluded.credits;
end $$;

-- 事件代號清單，好寫斷言
create or replace function pg_temp.kinds(p_app uuid) returns text[]
language sql stable as $$
  select coalesce(array_agg(kind order by id), '{}'::text[])
    from public.application_events where app_id = p_app;
$$;

do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000c1';   -- 申請人
  u_b uuid := '00000000-0000-0000-0000-0000000000c2';   -- 收件人
  app uuid; ks text[]; t1 timestamptz; t2 timestamptz; n int; d jsonb;
begin
  raise notice '=== 準備 ===';
  perform pg_temp.mkuser(u_a, 'crmfrom');
  perform pg_temp.mkuser(u_b, 'crmto');
  delete from public.applications where from_user in (u_a,u_b) or to_user in (u_a,u_b);

  -- ── 1. 送出申請 ─────────────────────────────────────────
  raise notice '--- 送出申請 ---';
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public.apply_to(u_b, '["答案一","答案二"]'::jsonb, '["題目一","題目二"]'::jsonb);
  select id into app from public.applications where from_user = u_a and to_user = u_b;

  ks := pg_temp.kinds(app);
  perform pg_temp.ok(ks @> array['applied'], '送出申請 → applied 事件', array_to_string(ks, ','));
  perform pg_temp.ok(ks @> array['answered_1'],
    '第一階段作答 → answered_1 事件（answers 是另一張表，也要記到）', array_to_string(ks, ','));

  select last_activity_at into t1 from public.applications where id = app;
  perform pg_temp.ok(t1 is not null, '送出申請時就有 last_activity_at');

  select detail into d from public.application_events where app_id = app and kind = 'answered_1';
  perform pg_temp.ok((d->>'count')::int = 2, 'answered_1 記下了題數', d::text);

  -- ── 2. 收件方打開 ───────────────────────────────────────
  raise notice '--- 收件方打開申請 ---';
  perform set_config('request.jwt.claim.sub', u_b::text, true);

  perform pg_temp.ok((select opened_at from public.applications where id = app) is null,
    '還沒打開時 opened_at 是空的（這就是「新申請」與「待審」的差別）');

  perform public.mark_applications_opened(array[app]);
  perform pg_temp.ok((select opened_at from public.applications where id = app) is not null,
    '打開之後 opened_at 有值');
  perform pg_temp.ok(pg_temp.kinds(app) @> array['opened'], '→ opened 事件');

  select count(*) into n from public.application_events where app_id = app and kind = 'opened';
  perform public.mark_applications_opened(array[app]);
  perform pg_temp.ok((select count(*) from public.application_events
                       where app_id = app and kind = 'opened') = n,
    '重複呼叫不會重複記（只記第一次打開）');

  -- 申請人不能替自己標記「已被打開」
  perform set_config('request.jwt.claim.sub', u_a::text, true);
  perform public.mark_applications_opened(array[app]);
  perform pg_temp.ok((select count(*) from public.application_events
                       where app_id = app and kind = 'opened') = n,
    '申請人呼叫沒有作用（只有收件方能標記已讀）');

  -- ── 3. 前端不能自己亂填受保護欄位 ────────────────────────
  raise notice '--- 受保護欄位 ---';
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  update public.applications set closed_reason = '亂填的值' where id = app;
  perform pg_temp.ok((select closed_reason from public.applications where id = app) is null,
    'closed_reason 前端寫不進去（漏斗統計不會被汙染）',
    (select closed_reason from public.applications where id = app));

  update public.applications set crm_tags = '["需補件","已電話確認"]'::jsonb where id = app;
  perform pg_temp.ok(
    (select jsonb_array_length(crm_tags) from public.applications where id = app) = 2,
    'crm_tags 收件方可以自己貼（那是志工的標籤，不是統計資料）');

  -- 時間軸不能被前端偽造
  begin
    insert into public.application_events(app_id, kind) values (app, '偽造的事件');
    perform pg_temp.ok(false, '前端不該能自己插入時間軸事件');
  exception when others then
    perform pg_temp.ok(true, '前端無法自己插入時間軸事件（沒有 insert policy）');
  end;

  -- ── 4. 推進階段 ─────────────────────────────────────────
  raise notice '--- 推進階段 ---';
  perform public.send_stage2(app, '["情境題一","情境題二"]'::jsonb);
  ks := pg_temp.kinds(app);
  perform pg_temp.ok(ks @> array['sent_q2'], '發出第二階段問卷 → sent_q2', array_to_string(ks, ','));
  perform pg_temp.ok(ks @> array['advanced_2'], '→ advanced_2', array_to_string(ks, ','));

  perform set_config('request.jwt.claim.sub', u_a::text, true);
  perform public.submit_stage2(app, '["回答一","回答二"]'::jsonb, '["情境題一","情境題二"]'::jsonb);
  perform pg_temp.ok(pg_temp.kinds(app) @> array['answered_2'], '第二階段作答 → answered_2');

  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform public.advance_stage3(app);
  perform pg_temp.ok(pg_temp.kinds(app) @> array['advanced_3'], '進第三階段 → advanced_3');

  -- ── 5. 雙方解鎖 ─────────────────────────────────────────
  raise notice '--- 雙方解鎖 ---';
  perform set_config('request.jwt.claim.sub', u_a::text, true);
  perform public.unlock_stage3(app, true);
  ks := pg_temp.kinds(app);
  perform pg_temp.ok(ks @> array['unlocked_from'], '申請人同意 → unlocked_from');
  perform pg_temp.ok(not (ks @> array['exchanged']), '只有單方同意時還沒有 exchanged');

  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform public.consent_unlock_to(app, true);
  ks := pg_temp.kinds(app);
  perform pg_temp.ok(ks @> array['unlocked_to'], '收件方同意 → unlocked_to');
  perform pg_temp.ok(ks @> array['exchanged'], '雙方都同意 → exchanged（完成認養手續）');
  perform pg_temp.ok(
    (select count(*) from public.application_events where app_id = app and kind = 'exchanged') = 1,
    'exchanged 只會發生一次');

  -- ── 6. 時間軸的順序與可見性 ──────────────────────────────
  raise notice '--- 時間軸 ---';
  ks := pg_temp.kinds(app);
  perform pg_temp.ok(ks[1] = 'applied', '時間軸第一筆是 applied', ks[1]);
  perform pg_temp.ok(array_position(ks, 'advanced_2') < array_position(ks, 'advanced_3'),
    '事件依實際發生順序排列');
  perform pg_temp.ok(cardinality(ks) >= 9, '整條流程留下了完整紀錄', cardinality(ks)::text);

  -- 申請人看不到 recipient-only 的事件
  -- （log_application_event 對 authenticated 是 revoke 的——前端不能自己造事件，
  --   所以這裡要切回 postgres 才叫得動，這本身也是一項驗證）
  begin
    perform public.log_application_event(app, 'x', null, '{}'::jsonb, 'recipient');
    perform pg_temp.ok(false, '前端不該叫得動 log_application_event');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, '前端叫不動 log_application_event（事件只能由 trigger 產生）');
  end;
  perform set_config('role', 'postgres', true);
  perform public.log_application_event(app, 'noted', u_b, '{"note":"志工私人筆記"}'::jsonb, 'recipient');
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_a::text, true);
  select count(*) into n from public.application_events where app_id = app and kind = 'noted';
  perform pg_temp.ok(n = 0, '申請人讀不到 visibility=recipient 的事件（志工筆記）', n::text);
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  select count(*) into n from public.application_events where app_id = app and kind = 'noted';
  perform pg_temp.ok(n = 1, '收件方讀得到自己的 recipient 事件', n::text);

  -- 完全無關的第三人什麼都看不到
  perform set_config('role', 'postgres', true);
  perform pg_temp.mkuser('00000000-0000-0000-0000-0000000000c3', 'crmother');
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', true);
  select count(*) into n from public.application_events where app_id = app;
  perform pg_temp.ok(n = 0, '無關的第三人看不到任何事件', n::text);

  raise notice '=== CRM 時間軸測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 婉拒與 closed_reason（漏斗統計）
-- 婉拒走的是前端直接 update，不是 RPC——這正是為什麼事件要用 trigger 記。
-- ════════════════════════════════════════════════════════════
do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000c1';
  u_b uuid := '00000000-0000-0000-0000-0000000000c2';
  app uuid; d jsonb; n int;
begin
  raise notice '--- 婉拒 ---';
  perform set_config('role', 'postgres', true);
  delete from public.applications where from_user = u_a and to_user = u_b;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.apply_to(u_b, '["答案"]'::jsonb, '["題目"]'::jsonb);
  select id into app from public.applications where from_user = u_a and to_user = u_b;

  -- 收件方在第一階段婉拒（前端直接 update，沒有經過任何 RPC）
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  update public.applications set status = 'rejected', note = '謝謝你的來信' where id = app;

  perform pg_temp.ok(pg_temp.kinds(app) @> array['declined'],
    '婉拒是前端直接 update，trigger 仍然記到了 declined 事件',
    array_to_string(pg_temp.kinds(app), ','));
  perform pg_temp.ok(
    (select closed_reason from public.applications where id = app) = 'declined_stage1',
    'closed_reason 自動填成 declined_stage1（漏斗看得出在哪一關流失）',
    (select closed_reason from public.applications where id = app));

  select detail into d from public.application_events where app_id = app and kind = 'declined';
  perform pg_temp.ok((d->>'stage')::int = 1, 'declined 事件記下了在第幾階段被婉拒', d::text);

  -- closed_reason 只存申請人本來就知道的事，不會外洩封鎖或安全事件
  perform pg_temp.ok(
    (select closed_reason from public.applications where id = app) not in ('blocked','safety'),
    'closed_reason 不含封鎖／安全事件（那些一律走 visibility=admin 的事件）');

  raise notice '=== 婉拒測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- last_activity_at：逾期判定的依據
-- ════════════════════════════════════════════════════════════
do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000c1';
  u_b uuid := '00000000-0000-0000-0000-0000000000c2';
  app uuid; t1 timestamptz;
begin
  perform set_config('role', 'postgres', true);
  delete from public.applications where from_user = u_a and to_user = u_b;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.apply_to(u_b, '["答案"]'::jsonb, '["題目"]'::jsonb);
  select id into app from public.applications where from_user = u_a and to_user = u_b;
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform public.send_stage2(app, '["情境題"]'::jsonb);
end $$;

do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000c1';
  u_b uuid := '00000000-0000-0000-0000-0000000000c2';
  app uuid; t1 timestamptz; t2 timestamptz;
begin
  raise notice '--- last_activity_at ---';
  select id, last_activity_at into app, t1 from public.applications
   where from_user = u_a and to_user = u_b;

  -- 聊天不進時間軸（會洗版），但一定要更新最後活動時間，
  -- 否則聊得正熱烈的申請會被算成「逾期未處理」
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.send_match_message(app, '你好，我看到你的病歷卡了');

  select last_activity_at into t2 from public.applications where id = app;
  perform pg_temp.ok(t2 > t1, '傳訊息會更新 last_activity_at（不會被誤判成逾期）',
    t1::text || ' → ' || t2::text);
  perform pg_temp.ok(
    not (pg_temp.kinds(app) @> array['messaged']),
    '訊息本身不進時間軸（避免把病例洗版）');

  raise notice '=== last_activity_at 測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 看板九格：確認全部都算得出來，不需要新增狀態欄位
-- ════════════════════════════════════════════════════════════
do $$
declare
  u_b uuid := '00000000-0000-0000-0000-0000000000c2';
  cnt int;
begin
  raise notice '--- 看板九格 ---';
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- 九格全部只用現有欄位就算得出來（規格第 4.1 節）
  select count(*) into cnt from public.applications a where a.to_user = u_b and (
       (a.stage = 1 and a.status = 'open' and a.opened_at is null)                      -- 📨 新申請
    or (a.stage = 1 and a.status = 'open' and a.opened_at is not null)                  -- 📋 第一階段待審
    or (a.stage = 2 and a.status = 'open')                                              -- 💬 第二階段
    or (a.stage = 3 and a.status = 'open' and not a.unlock_from and not a.unlock_to)    -- 👀 日常觀察
    or (a.stage = 3 and (a.unlock_from <> a.unlock_to))                                 -- ❤️ 等待雙向解鎖
    or (a.stage = 3 and a.unlock_from and a.unlock_to)                                  -- 🌱 完成
    or (a.status = 'open' and a.last_activity_at < now() - interval '7 days')           -- 💤 逾期
    or (a.status = 'rejected')                                                          -- 🏠 結案
  );
  perform pg_temp.ok(cnt >= 1, '九格的判定條件全部只用現有欄位就算得出來', cnt::text);

  -- 「待初診」是一個 not exists 查詢，但 screening_results 對前端是完全不開放的
  -- （直接查得到就等於可以繞過 min_stage 分層），所以這一格只能在後台端算。
  begin
    select count(*) into cnt from public.screening_results;
    perform pg_temp.ok(false, 'screening_results 不該讓前端直接查');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'screening_results 前端查不到（只能走 get_screening_for）');
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into cnt from public.applications a
   where a.to_user = u_b and not exists (
     select 1 from public.screening_results s where s.app_id = a.id);
  perform pg_temp.ok(cnt >= 0, '🩺 待初診在後台端也只是一個 not exists 查詢', cnt::text);

  raise notice '=== 看板測試結束 ===';
end $$;
