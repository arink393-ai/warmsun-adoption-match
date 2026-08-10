-- 🌱 陪伴紀錄第 8 步（一半）：回憶膠囊，以及關係結束之後的處置
--
-- 規格 6.1 那一句最容易寫反：
--   **30 天是「選擇的期限」，不是「保留的期限」。**
--   期限內選了 → 立刻照選的做；期限內沒選 → 到期時自動**刪除**。
--   沒有回應不能被當成「同意永久保留」——分手之後最可能發生的事就是
--   再也不登入，而那不是同意。
--
-- 規格 6.2：半年後自動跳出來的那封信，如果那時候兩個人已經分開了，
--   它會變成傷害。所以到期只代表「可以開」，不代表自動打開。
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

create or replace function pg_temp.mklink(a uuid, b uuid) returns uuid
language plpgsql as $$
declare app uuid; st jsonb;
begin
  insert into auth.users(id,email) values (a, a::text || '@t.local'), (b, b::text || '@t.local')
    on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'甲','pet','cat',true,'active'), (b,'乙','keeper','dog',true,'active')
    on conflict (id) do update set account_status='active', posting_locked=false;
  insert into public.applications(from_user,to_user,stage,status,unlock_from,unlock_to)
    values (b,a,3,'open',true,true) returning id into app;
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_agree(app, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.set_companion_agree(app, true);
  return (st->>'link_id')::uuid;
end $$;

-- ════════════════════════════════════════════════════════════
-- 一、回憶膠囊
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e3a01';
  b uuid := '00000000-0000-0000-0000-0000000e3a02';
  lk uuid; c jsonb; j jsonb; n int;
begin
  raise notice '=== 回憶膠囊 ===';
  lk := pg_temp.mklink(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);

  c := public.write_capsule(lk, current_date + 180, '半年後的我，希望你還記得今天。', '寫給半年後');
  perform pg_temp.ok(c->>'id' is not null, '封得起來');

  begin
    perform public.write_capsule(lk, current_date, '今天就開');
    perform pg_temp.ok(false, '日期要在未來');
  exception when others then perform pg_temp.ok(true, '日期要在未來，膠囊才有意義'); end;

  -- 沒到期就拿不到內容，而且是擋在資料庫，不是擋在畫面上
  j := public.list_capsules(lk);
  perform pg_temp.ok(j::text not like '%還記得今天%',
    '清單裡不含內容（不然「還沒到期」就只是畫面上不顯示而已）', j::text);
  perform pg_temp.ok(not (j->0->>'due')::boolean, '還沒到期', j::text);
  begin
    perform public.open_capsule((c->>'id')::uuid);
    perform pg_temp.ok(false, '沒到期打不開');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%才能打開%', '沒到期打不開，而且說得出是哪一天', sqlerrm);
  end;

  -- 對方永遠讀不到：膠囊是本人寫給自己的
  perform set_config('request.jwt.claim.sub', b::text, true);
  j := public.list_capsules(lk);
  perform pg_temp.ok(jsonb_array_length(j) = 0, '對方連「有一封信」都看不到（那是寫給自己的）', j::text);
  begin
    perform public.open_capsule((c->>'id')::uuid);
    perform pg_temp.ok(false, '對方打不開');
  exception when others then perform pg_temp.ok(true, '對方打不開'); end;

  raise notice '--- 到期了 ---';
  update public.companion_capsules set open_at = current_date - 1 where link_id = lk;
  perform set_config('request.jwt.claim.sub', a::text, true);
  j := public.list_capsules(lk);
  perform pg_temp.ok((j->0->>'due')::boolean, '到期了', j::text);
  perform pg_temp.ok((j->0->>'auto_open')::boolean,
    '關係還在進行中 → 到期自動顯示', j::text);
  perform pg_temp.ok(not (j->0->>'opened')::boolean, '但「到期」不等於「已經打開」', j::text);

  /* 這是 6.2 的整個重點：
     半年後自動跳出來的那封信，如果那時候兩個人已經分開了，它會變成傷害。 */
  update public.companion_links set status = 'paused' where id = lk;
  j := public.list_capsules(lk);
  perform pg_temp.ok(not (j->0->>'auto_open')::boolean,
    '關係非 active 就不自動開，只靜靜列一行（點了才開，而且點之前先問一次）', j::text);
  perform pg_temp.ok((j->0->>'due')::boolean, '但它還在，沒有因為關係暫停就消失', j::text);

  -- 本人自己點開還是打得開
  c := public.open_capsule((j->0->>'id')::uuid);
  perform pg_temp.ok(c->>'body' like '%還記得今天%', '本人自己決定要看，就看得到', c::text);
  j := public.list_capsules(lk);
  perform pg_temp.ok((j->0->>'opened')::boolean, '開過之後記下來了', j::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、結束與處置
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e3b01';
  b uuid := '00000000-0000-0000-0000-0000000e3b02';
  lk uuid; app uuid; mid bigint; st jsonb; j jsonb; n int; lnk public.companion_links;
begin
  raise notice '=== 結束與處置 ===';
  lk := pg_temp.mklink(a, b);
  select id into app from public.applications
   where least(from_user,to_user) = least(a,b) and greatest(from_user,to_user) = greatest(a,b);
  insert into public.match_messages(application_id, sender_id, body)
    values (app, b, '等你考完試，我們去吃那間拉麵') returning id into mid;

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.add_companion_memory(lk, '甲寫的回憶一', '');
  perform public.add_companion_memory(lk, '甲寫的回憶二', '');
  perform public.add_companion_milestone(lk, 'first_meet', '甲記的');
  perform public.toggle_message_bookmark(mid, 'promise');
  perform public.write_capsule(lk, current_date + 30, '甲寫給自己的');
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.add_companion_memory(lk, '乙寫的回憶', '');

  perform set_config('request.jwt.claim.sub', a::text, true);
  st := public.end_companion_link(lk);
  perform pg_temp.ok(st->>'status' = 'ended', '結束了', st->>'status');
  select * into lnk from public.companion_links where id = lk;
  perform pg_temp.ok(lnk.purge_at::date = (now() + interval '30 days')::date,
    'purge_at 是 30 天後', lnk.purge_at::text);
  perform pg_temp.ok(st->>'mine' is null, '一開始還沒選處置方式', coalesce(st->>'mine','null'));

  /* 對方選了什麼不揭露。那是他自己的決定，知道了也改變不了什麼，
     只會變成分手之後多一件可以拿來想的事。 */
  perform pg_temp.ok(st::text not like '%disposition_b%' and not (st ? 'other'),
    '看不到對方選了什麼', st::text);

  raise notice '--- 選了就立刻做 ---';
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.set_companion_disposition(lk, 'delete');
  select count(*) into n from public.companion_memories where link_id = lk and created_by = b;
  perform pg_temp.ok(n = 0, '選刪除就立刻刪（不用等 30 天：30 天是選擇的期限）', n::text);
  select count(*) into n from public.companion_memories where link_id = lk and created_by = a;
  perform pg_temp.ok(n = 2, '而且只刪自己寫的，對方的留著', n::text);

  -- 留下痕跡
  perform set_config('request.jwt.claim.sub', a::text, true);
  st := public.companion_disposition_state(lk);
  perform pg_temp.ok(st->>'tombstones' like '%memory%',
    '封存本裡留下「這裡原本有 N 則已被作者刪除」的痕跡', st->>'tombstones');
  /* 不留痕跡的話，另一方會以為自己記錯了。 */
  perform pg_temp.ok(
    (select (e->>'n')::int from jsonb_array_elements(st->'tombstones') e
      where e->>'kind' = 'memory') = 1,
    '痕跡上寫得出少了幾則', st->>'tombstones');

  raise notice '--- 只留我自己寫的 ---';
  st := public.set_companion_disposition(lk, 'mine_only');
  j := public.companion_timeline(lk);
  perform pg_temp.ok(
    (select count(*) from jsonb_array_elements(j) e where not (e->>'mine')::boolean) = 0,
    '選了「只留我自己寫的」之後，時間線上只剩自己寫的', j::text);
  perform pg_temp.ok(jsonb_array_length(j) >= 3,
    '自己寫的都還在（回憶兩則、里程碑、書籤）', jsonb_array_length(j)::text);
  -- 而且是從我這邊移除，不是把對方的東西刪掉
  select count(*) into n from public.companion_milestones where link_id = lk and created_by = a;
  perform pg_temp.ok(n = 1, '「只留我自己寫的」是從我這邊移除，不是替對方刪資料', n::text);

  raise notice '--- 結束之後就不能再寫 ---';
  begin
    perform public.add_companion_memory(lk, '結束之後還想寫');
    perform pg_temp.ok(false, '結束之後寫不進去');
  exception when others then perform pg_temp.ok(true, '結束之後寫不進去'); end;
  begin
    perform public.write_capsule(lk, current_date + 10, '結束之後還想封一封');
    perform pg_temp.ok(false, '結束之後封不了新的膠囊');
  exception when others then perform pg_temp.ok(true, '結束之後封不了新的膠囊'); end;
  begin
    perform public.submit_checkin(lk, '{"connected":"有點遠"}'::jsonb);
    perform pg_temp.ok(false, '結束之後不能再做健康檢查');
  exception when others then perform pg_temp.ok(true, '結束之後不能再做健康檢查'); end;

  begin
    perform public.set_companion_disposition(lk, 'burn_everything');
    perform pg_temp.ok(false, '沒有第四種處置方式');
  exception when others then perform pg_temp.ok(true, '沒有第四種處置方式'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、到期沒選的那一邊
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e3c01';
  b uuid := '00000000-0000-0000-0000-0000000e3c02';
  lk uuid; n int; lnk public.companion_links; d text;
begin
  raise notice '=== 到期 ===';
  lk := pg_temp.mklink(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.add_companion_memory(lk, '甲寫的', '');
  perform public.write_capsule(lk, current_date + 200, '甲的膠囊');
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.add_companion_memory(lk, '乙寫的', '');
  perform public.end_companion_link(lk);
  perform public.set_companion_disposition(lk, 'archive');

  -- 甲一直沒選，時間到了
  update public.companion_links set purge_at = now() - interval '1 day' where id = lk;
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.purge_due_companion_links();

  select count(*) into n from public.companion_memories where link_id = lk and created_by = a;
  /* 沒有回應不能被當成「同意永久保留」。
     分手之後最可能發生的事就是再也不登入，而那不是同意。 */
  perform pg_temp.ok(n = 0, '到期沒選的那一邊，內容被刪掉（預設站在「少留一點」那邊）', n::text);
  select count(*) into n from public.companion_capsules where link_id = lk and user_id = a;
  perform pg_temp.ok(n = 0, '膠囊也跟著走', n::text);

  select count(*) into n from public.companion_memories where link_id = lk and created_by = b;
  perform pg_temp.ok(n = 1, '選了封存的那一邊不受影響（各自的內容各自處置）', n::text);

  select * into lnk from public.companion_links where id = lk;
  perform pg_temp.ok(lnk.disposition_a = 'delete',
    '到期時把沒選的那一格補成 delete（不是留白，不然下次又會再跑一次）', lnk.disposition_a);
  perform pg_temp.ok(lnk.purge_at is null, '處理完就把 purge_at 清掉', coalesce(lnk.purge_at::text,'null'));

  select count(*) into n from public.companion_tombstones where link_id = lk and deleted_by = a;
  perform pg_temp.ok(n >= 1, '到期刪除一樣留下痕跡', n::text);

  -- 一般使用者叫不動這支
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform pg_temp.ok(
    not has_function_privilege('authenticated', 'public.purge_due_companion_links()', 'execute'),
    '一般帳號叫不動到期清理（那是排程的工作，不是使用者的按鈕）');

  raise notice '=== 結束處置測試結束 ===';
end $$;
