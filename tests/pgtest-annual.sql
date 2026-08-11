-- 🌱 伴侶關係的相互承認，與年度回顧（規格第 7 節第 3 題的答案）
--
-- 這一份守兩件事：
--   (1) **單方面按下不會讓對方看到，連「對方按了沒有」都不會。**
--       承認彼此是伴侶不是邀請，是一句告白。把「某某已經認定你是他的伴侶」
--       推到另一個人面前，他接下來按或不按都不再是自由的。
--   (2) **保留超過一年不是預設，是兩個人一起按出來的。**
--       沒有互相承認的關係不做年度回顧，也就不需要為了它多留東西。
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
-- 一、按了對方不會知道
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e4a01';
  b uuid := '00000000-0000-0000-0000-0000000e4a02';
  lk uuid; st jsonb; ls jsonb; t0 timestamptz; lnk public.companion_links;
begin
  raise notice '=== 相互承認 ===';
  lk := pg_temp.mklink(a, b);

  perform set_config('request.jwt.claim.sub', a::text, true);
  st := public.companion_partner_state(lk);
  perform pg_temp.ok(not (st->>'mine')::boolean and not (st->>'both')::boolean,
    '一開始兩邊都沒有按', st::text);
  perform pg_temp.ok((st->>'eligible')::boolean, '陪伴紀錄進行中就可以按', st::text);

  st := public.set_companion_partner(lk, true);
  perform pg_temp.ok((st->>'mine')::boolean, '自己按下去了', st::text);
  perform pg_temp.ok(not (st->>'both')::boolean, '單方面按下不算成立', st::text);
  perform pg_temp.ok((st->>'partnered_at') is null, '還沒成立就沒有日期', st::text);

  /* 這是整節最重要的一條。
     連「對方按了沒有」這件事本身都不該讓人知道——
     知道了之後，他按或不按都不再是自由的。 */
  raise notice '--- 對方那一邊看到什麼 ---';
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.companion_partner_state(lk);
  perform pg_temp.ok(not (st->>'other')::boolean,
    '甲按了，但乙這邊完全看不出來（other 不是「對方按了沒有」）', st::text);
  perform pg_temp.ok(not (st->>'mine')::boolean, '乙自己也還沒按', st::text);
  ls := public.my_companion_links();
  perform pg_temp.ok(not (ls->0->>'partnered')::boolean, '清單上也看不出來', ls::text);
  perform pg_temp.ok(ls::text not like '%partner_other%',
    '清單根本沒有一個欄位在講對方按了沒有', ls::text);

  raise notice '--- 兩個人都按下 ---';
  st := public.set_companion_partner(lk, true);
  perform pg_temp.ok((st->>'both')::boolean, '兩個人都按下才成立', st::text);
  perform pg_temp.ok((st->>'other')::boolean, '成立之後才看得到對方也按了', st::text);
  perform pg_temp.ok((st->>'partnered_at') is not null, '成立時記下日期', st::text);
  select * into lnk from public.companion_links where id = lk;
  t0 := lnk.partnered_at;

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform pg_temp.ok((public.companion_partner_state(lk)->>'both')::boolean,
    '另一邊看到的也是成立');

  raise notice '--- 收回 ---';
  st := public.set_companion_partner(lk, false);
  perform pg_temp.ok(not (st->>'both')::boolean, '任一方都可以收回', st::text);
  perform pg_temp.ok(not (st->>'other')::boolean,
    '收回之後又回到看不出對方按了沒有的狀態（收回一樣安靜）', st::text);

  st := public.set_companion_partner(lk, true);
  select * into lnk from public.companion_links where id = lk;
  perform pg_temp.ok(lnk.partnered_at = t0,
    '收回再按回來不重算日期（跟起算日同一個理由）',
    lnk.partnered_at::text || ' vs ' || t0::text);

  -- 只動自己那一格
  perform pg_temp.ok(lnk.partner_a and lnk.partner_b,
    '一個人收回再按回來，不會把對方那一格也動掉');
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、這不是等級，也不是成就
-- ════════════════════════════════════════════════════════════
do $$
declare cols text; def text; n int;
begin
  raise notice '=== 不是成就 ===';
  select string_agg(column_name, ',') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'companion_links';
  perform pg_temp.ok(cols !~* 'score|rating|streak|points|level|badge|rank',
    'companion_links 仍然沒有任何分數／等級／徽章欄位', cols);

  /* 伴侶狀態不能外流到佈告欄。第 0 層是所有人都看得到的地方，
     「已配對成功」出現在那裡，就變成一個公開的身分標籤。 */
  select pg_get_functiondef(p.oid) into def from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'get_visible_match_profiles';
  /* 要用字界，不然 partner_alone_time_acceptance（第 23 節的生活場景欄位）
     會被 partner_a 這個 pattern 掃到，變成一條永遠紅的假警報。 */
  perform pg_temp.ok(def !~* '\ypartner_[ab]\y|\ypartnered\y',
    '佈告欄的資料裡完全沒有伴侶狀態（那不是拿來給別人看的）',
    (select string_agg(distinct m[1], ',')
       from regexp_matches(def, '(\ypartner_[ab]\y|\ypartnered\y)', 'g') m));
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、年度回顧只給互相承認的兩個人
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e4b01';
  b uuid := '00000000-0000-0000-0000-0000000e4b02';
  x uuid := '00000000-0000-0000-0000-0000000e4b09';
  lk uuid; app uuid; mid bigint; r jsonb; ps jsonb;
begin
  raise notice '=== 年度回顧 ===';
  lk := pg_temp.mklink(a, b);
  insert into auth.users(id,email) values (x,'x4@t.local') on conflict do nothing;
  select id into app from public.applications
   where least(from_user,to_user) = least(a,b) and greatest(from_user,to_user) = greatest(a,b);

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform pg_temp.ok(not public.companion_keeps_history(lk),
    '還沒互相承認之前，這段關係不需要為了年度回顧多留東西');
  begin
    perform public.companion_annual_review(lk);
    perform pg_temp.ok(false, '沒有互相承認就沒有年度回顧');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%都承認彼此是伴侶%',
      '沒有互相承認就沒有年度回顧，而且說得出條件', sqlerrm);
  end;
  perform pg_temp.ok(public.companion_annual_periods(lk) = '[]'::jsonb,
    '連可以看哪幾年都不會列出來', public.companion_annual_periods(lk)::text);

  -- 只有一邊按也一樣沒有
  perform public.set_companion_partner(lk, true);
  begin
    perform public.companion_annual_review(lk);
    perform pg_temp.ok(false, '只有一邊承認還是沒有');
  exception when others then perform pg_temp.ok(true, '只有一邊承認還是沒有'); end;

  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_companion_partner(lk, true);

  -- 放一些內容進去
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.add_companion_memory(lk, '今年一起去的那個地方', '天氣很好。',
                                      'together', current_date - 30);
  perform public.add_companion_memory(lk, '只有我知道的那件事', '', 'feeling',
                                      current_date - 20, 'private');
  perform public.add_companion_memory(lk, '兩年前的事', '', 'moment', current_date - 700);
  perform public.add_companion_milestone(lk, 'first_trip', '第一次一起出遠門', current_date - 100);
  perform public.add_companion_goal(lk, '把陽台整理好', 'home');
  perform public.set_companion_goal_status(
    (select id from public.companion_goals where link_id = lk limit 1), 'done');
  insert into public.match_messages(application_id, sender_id, body)
    values (app, b, '等你考完試，我們去吃那間拉麵') returning id into mid;
  perform public.toggle_message_bookmark(mid, 'promise');

  perform pg_temp.ok(public.companion_keeps_history(lk),
    '互相承認之後，這段紀錄才會跟著關係一起留著');

  r := public.companion_annual_review(lk);
  perform pg_temp.ok(r::text like '%今年一起去的那個地方%', '今年的回憶在裡面', r::text);
  perform pg_temp.ok(r::text like '%只有我知道的那件事%',
    '自己寫的私人回憶自己看得到', r::text);
  perform pg_temp.ok(r::text not like '%兩年前的事%',
    '超出這一年的不會被算進來', r::text);
  perform pg_temp.ok(r::text like '%第一次一起出遠門%', '里程碑在裡面', r::text);
  perform pg_temp.ok(r::text like '%拉麵%', '對話書籤也在裡面', r::text);
  perform pg_temp.ok(r::text like '%把陽台整理好%', '目標在裡面', r::text);

  /* 一個數字放在那裡，遲早會被畫成一個數字。 */
  perform pg_temp.ok(not (r ? 'count') and r::text !~ '"(count|total|n_|score)',
    '回顧裡沒有任何 count／total／score 欄位（不然「今年記了 12 則」會變成一個要衝的數字）',
    r::text);
  perform pg_temp.ok(not (r ? 'summary') and not (r ? 'ai_summary'),
    '回顧裡沒有 AI 講評欄位（年度回顧不是年度評鑑）', r::text);

  ps := public.companion_annual_periods(lk);
  perform pg_temp.ok(jsonb_array_length(ps) >= 1, '列得出可以看哪幾年', ps::text);

  -- 對方的私人回憶不會出現在我的回顧裡
  perform set_config('request.jwt.claim.sub', b::text, true);
  r := public.companion_annual_review(lk);
  perform pg_temp.ok(r::text not like '%只有我知道的那件事%',
    '對方設成私人的回憶不會出現在我的年度回顧裡', r::text);
  perform pg_temp.ok(r::text like '%今年一起去的那個地方%', '共同的還是看得到', r::text);

  -- 局外人
  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.companion_annual_review(lk);
    perform pg_temp.ok(false, '局外人讀不到年度回顧');
  exception when others then perform pg_temp.ok(true, '局外人讀不到年度回顧'); end;
  begin
    perform public.set_companion_partner(lk, true);
    perform pg_temp.ok(false, '局外人不能替別人按');
  exception when others then perform pg_temp.ok(true, '局外人不能替別人按'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、關係暫停或結束時
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e4c01';
  b uuid := '00000000-0000-0000-0000-0000000e4c02';
  lk uuid; r jsonb; n int;
begin
  raise notice '=== 暫停與結束 ===';
  lk := pg_temp.mklink(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_partner(lk, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_companion_partner(lk, true);
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.add_companion_memory(lk, '成立之後寫的', '');

  update public.companion_links set status = 'paused' where id = lk;
  begin
    perform public.set_companion_partner(lk, true);
    perform pg_temp.ok(false, '暫停期間不能改這件事');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%進行中%',
      '暫停期間不能改這件事（那是一句要在關係裡說的話）', sqlerrm);
  end;
  /* 但已經成立的事實不會因為暫停就消失，年度回顧也還在。
     暫停不是分手。 */
  r := public.companion_annual_review(lk);
  perform pg_temp.ok(r::text like '%成立之後寫的%',
    '暫停期間年度回顧還讀得到（暫停不是分手）', r::text);

  raise notice '--- 結束之後 ---';
  update public.companion_links set status = 'ended', ended_at = now(),
         purge_at = now() + interval '30 days' where id = lk;
  r := public.companion_annual_review(lk);
  perform pg_temp.ok(r::text like '%成立之後寫的%',
    '結束之後也還讀得到，等處置方式決定（不會先一步消失）', r::text);

  -- 選了刪除之後就真的沒了
  perform public.set_companion_disposition(lk, 'delete');
  r := public.companion_annual_review(lk);
  perform pg_temp.ok(r::text not like '%成立之後寫的%',
    '選了全部刪除之後，年度回顧裡也跟著空了（不會留一份備份）', r::text);
  perform pg_temp.ok((r->>'empty')::boolean, '而且會標成空的', r::text);

  raise notice '=== 年度回顧測試結束 ===';
end $$;
