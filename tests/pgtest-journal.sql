-- 🌱 陪伴紀錄第 3、4 步：回憶、里程碑、共同目標、時間線
--
-- 這一份守的重點：
--   (1) **共同不等於可以改寫對方寫下的東西。** 讀得到 ≠ 改得動。
--   (2) **暫停之後共同的那本唯讀，但自己的筆記還能寫。**
--       一方撤回同意就繼續往共同的本子寫，等於當作沒看到；
--       但把人鎖在自己的筆記外面，那本來就是他自己的。
--   (3) **里程碑沒有順序、目標沒有進度分數。** 關係不是一條該照走的階梯，
--       也不是專案管理。
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

-- 建一段已經成立的陪伴紀錄，回傳 link_id
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
-- 一、結構上就不該存在的東西
-- ════════════════════════════════════════════════════════════
do $$
declare cols text; def text;
begin
  raise notice '=== 結構 ===';
  select string_agg(column_name, ',') into cols from information_schema.columns
   where table_schema='public' and table_name='companion_milestones';
  /* 里程碑一旦有了順序，畫面上遲早會長出「你們完成了 3/8」。
     關係不是一條大家都該照走的階梯。 */
  perform pg_temp.ok(cols !~* 'order|step|seq|level|progress',
    '里程碑沒有順序／階段／進度欄位（不預設一套關係該怎麼進展）', cols);

  select string_agg(column_name, ',') into cols from information_schema.columns
   where table_schema='public' and table_name='companion_goals';
  perform pg_temp.ok(cols !~* 'score|rating|percent|streak',
    '共同目標沒有分數／完成率欄位（關係不是專案管理）', cols);

  select pg_get_constraintdef(oid) into def from pg_constraint
   where conname = 'companion_goals_status_check';
  perform pg_temp.ok(def like '%paused%',
    'status 一定有 paused（沒有它，「現在不想推」只能留在未開始裡看起來像拖延）', def);

  select string_agg(column_name, ',') into cols from information_schema.columns
   where table_schema='public' and table_name='companion_memories';
  perform pg_temp.ok(cols like '%photo_path%',
    '回憶留了 photo_path 欄位（照片本身還沒開放，等私密 bucket 的決定）', cols);
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、寫、讀、改、刪
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e0a01';
  b uuid := '00000000-0000-0000-0000-0000000e0a02';
  x uuid := '00000000-0000-0000-0000-0000000e0a09';
  lk uuid; m public.companion_memories; mp public.companion_memories;
  g public.companion_goals; s public.companion_milestones; n int; j jsonb;
begin
  raise notice '=== 回憶 ===';
  lk := pg_temp.mklink(a, b);
  insert into auth.users(id,email) values (x,'ex@t.local') on conflict do nothing;

  perform set_config('request.jwt.claim.sub', a::text, true);
  m := public.add_companion_memory(lk, '第一次一起吃拉麵', '排了四十分鐘，值得。');
  perform pg_temp.ok(m.id is not null, '寫得進去');
  perform pg_temp.ok(m.visibility = 'both',
    '共同的那本預設是兩個人都看得到（這裡跟書籤刻意不同：書籤是收藏對方的話，'
    || '這裡是兩個人一起開的本子）', m.visibility);
  perform pg_temp.ok(m.at = current_date, '沒給日期就用今天', m.at::text);

  mp := public.add_companion_memory(lk, '只有我知道的那件事', '先不想講。',
                                    'feeling', null, 'private');
  perform pg_temp.ok(mp.visibility = 'private', '也可以寫只有自己看得到的', mp.visibility);

  -- 空白的擋下來
  begin
    perform public.add_companion_memory(lk, '   ', '  ');
    perform pg_temp.ok(false, '完全空白的存不進去');
  exception when others then perform pg_temp.ok(true, '完全空白的存不進去'); end;

  raise notice '--- 對方讀得到什麼 ---';
  perform set_config('request.jwt.claim.sub', b::text, true);
  j := public.companion_timeline(lk);
  perform pg_temp.ok(
    (select count(*) from jsonb_array_elements(j) e where e->>'id' = m.id::text) = 1,
    '共同的那則對方讀得到', j::text);
  perform pg_temp.ok(
    (select count(*) from jsonb_array_elements(j) e where e->>'id' = mp.id::text) = 0,
    '只有自己看得到的那則對方讀不到', j::text);

  /* 讀得到 ≠ 改得動。共同不等於可以改寫對方寫下的東西。 */
  begin
    perform public.update_companion_memory(m.id, '我改一下對方寫的');
    perform pg_temp.ok(false, '不能修改對方寫的回憶');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%只有寫下它的人%',
      '不能修改對方寫的回憶，而且說得出原因', sqlerrm);
  end;
  begin
    perform public.delete_companion_memory(m.id);
    perform pg_temp.ok(false, '不能刪掉對方寫的回憶');
  exception when others then perform pg_temp.ok(true, '不能刪掉對方寫的回憶'); end;

  raise notice '--- 作者自己改 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  m := public.update_companion_memory(m.id, null, '排了四十分鐘，湯頭很好。');
  perform pg_temp.ok(m.body like '%湯頭%', '作者改得動自己的', m.body);
  perform pg_temp.ok(m.title = '第一次一起吃拉麵', '沒傳的欄位不會被清空', m.title);
  m := public.update_companion_memory(m.id, null, null, 'private');
  perform pg_temp.ok(m.visibility = 'private', '寫完之後還可以收回成只有自己看得到', m.visibility);
  m := public.update_companion_memory(m.id, null, null, 'both');

  raise notice '=== 里程碑 ===';
  perform set_config('request.jwt.claim.sub', b::text, true);
  s := public.add_companion_milestone(lk, 'first_meet', '在那家咖啡店');
  perform pg_temp.ok(s.id is not null, '兩個人都可以記里程碑（不是只有建立的人）');
  begin
    perform public.add_companion_milestone(lk, 'level_up');
    perform pg_temp.ok(false, '沒有這種里程碑類型');
  exception when others then perform pg_temp.ok(true, '沒有這種里程碑類型'); end;
  s := public.add_companion_milestone(lk, 'custom', '一起把陽台整理好了');
  perform pg_temp.ok(s.milestone_type = 'custom',
    '自己寫的里程碑一樣存得進去（預設清單只是提示詞）', s.milestone_type);

  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.delete_companion_milestone(s.id);
    perform pg_temp.ok(false, '不能刪掉對方記下的里程碑');
  exception when others then perform pg_temp.ok(true, '不能刪掉對方記下的里程碑'); end;

  raise notice '=== 共同目標 ===';
  g := public.add_companion_goal(lk, '存一筆一起去日本的錢', 'travel');
  perform pg_temp.ok(g.status = 'idle', '新目標從 idle 開始', g.status);

  -- 狀態兩個人都能改
  perform set_config('request.jwt.claim.sub', b::text, true);
  g := public.set_companion_goal_status(g.id, 'paused');
  perform pg_temp.ok(g.status = 'paused',
    '「我們現在不想推這件事」不是只有提出的人能說', g.status);
  g := public.set_companion_goal_status(g.id, 'done');
  perform pg_temp.ok(g.completed_at is not null, '完成時記下完成時間');
  g := public.set_companion_goal_status(g.id, 'doing');
  perform pg_temp.ok(g.completed_at is null,
    '改回進行中時完成時間要清掉（不然會留下一個假的完成紀錄）', coalesce(g.completed_at::text,'null'));

  -- 但刪除只有提出的人
  begin
    perform public.delete_companion_goal(g.id);
    perform pg_temp.ok(false, '不能刪掉對方提出的目標');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%只有提出它的人%',
      '不能刪掉對方提出的目標（那是把別人提過的事整個抹掉）', sqlerrm);
  end;

  begin
    perform public.set_companion_goal_status(g.id, 'blocked');
    perform pg_temp.ok(false, '沒有這種狀態');
  exception when others then perform pg_temp.ok(true, '沒有這種狀態'); end;

  raise notice '=== 局外人 ===';
  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.companion_timeline(lk);
    perform pg_temp.ok(false, '局外人讀不到時間線');
  exception when others then perform pg_temp.ok(true, '局外人讀不到時間線'); end;
  begin
    perform public.add_companion_memory(lk, '我要插一句');
    perform pg_temp.ok(false, '局外人寫不進去');
  exception when others then perform pg_temp.ok(true, '局外人寫不進去'); end;
  begin
    perform public.companion_goals_list(lk);
    perform pg_temp.ok(false, '局外人讀不到共同目標');
  exception when others then perform pg_temp.ok(true, '局外人讀不到共同目標'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、暫停與結束之後
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e0b01';
  b uuid := '00000000-0000-0000-0000-0000000e0b02';
  lk uuid; m public.companion_memories; j jsonb;
begin
  raise notice '=== 暫停之後 ===';
  lk := pg_temp.mklink(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);
  m := public.add_companion_memory(lk, '暫停之前寫的');

  -- 乙撤回同意 → paused
  update public.companion_links set status = 'paused', agreed_b = false where id = lk;

  begin
    perform public.add_companion_memory(lk, '暫停之後想往共同的本子寫');
    perform pg_temp.ok(false, '暫停之後共同的那本寫不進去');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%暫停%',
      '暫停之後共同的那本寫不進去，而且說得出原因', sqlerrm);
  end;

  /* 但不能把人鎖在自己的筆記外面——那本來就是他自己的。 */
  m := public.add_companion_memory(lk, '這段時間我自己的心情', '', 'feeling', null, 'private');
  perform pg_temp.ok(m.id is not null, '暫停期間還是可以寫只有自己看得到的');

  begin
    perform public.add_companion_milestone(lk, 'anniversary');
    perform pg_temp.ok(false, '暫停期間不能加共同的里程碑');
  exception when others then perform pg_temp.ok(true, '暫停期間不能加共同的里程碑'); end;
  begin
    perform public.add_companion_goal(lk, '暫停期間的新目標');
    perform pg_temp.ok(false, '暫停期間不能加共同目標');
  exception when others then perform pg_temp.ok(true, '暫停期間不能加共同目標'); end;

  -- 讀還是讀得到
  j := public.companion_timeline(lk);
  perform pg_temp.ok(jsonb_array_length(j) >= 2, '暫停不影響閱讀（唯讀，不是關門）',
    jsonb_array_length(j)::text);

  raise notice '--- 結束之後 ---';
  update public.companion_links set status = 'ended', ended_at = now() where id = lk;
  begin
    perform public.add_companion_memory(lk, '結束之後', '', 'feeling', null, 'private');
    perform pg_temp.ok(false, '結束之後連自己的筆記也不能再新增');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%只能閱讀%',
      '結束之後全部唯讀，等處置方式（規格 6.1）', sqlerrm);
  end;
  j := public.companion_timeline(lk);
  perform pg_temp.ok(jsonb_array_length(j) >= 2, '結束之後仍然讀得到（處置前不會先消失）',
    jsonb_array_length(j)::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、時間線
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e0c01';
  b uuid := '00000000-0000-0000-0000-0000000e0c02';
  lk uuid; app uuid; mid bigint; j jsonb; kinds text;
begin
  raise notice '=== 時間線 ===';
  lk := pg_temp.mklink(a, b);
  select id into app from public.applications
   where least(from_user,to_user) = least(a,b) and greatest(from_user,to_user) = greatest(a,b);

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.add_companion_memory(lk, '三天前的事', '', 'moment', current_date - 3);
  perform public.add_companion_memory(lk, '今天的事', '', 'moment', current_date);
  perform public.add_companion_milestone(lk, 'first_meet', '', current_date - 10);

  insert into public.match_messages(application_id, sender_id, body)
    values (app, b, '等你考完試，我們去吃那間拉麵') returning id into mid;
  perform public.toggle_message_bookmark(mid, 'promise');

  j := public.companion_timeline(lk);
  select string_agg(distinct e->>'kind', ',' order by e->>'kind') into kinds
    from jsonb_array_elements(j) e;
  perform pg_temp.ok(kinds = 'bookmark,memory,milestone',
    '時間線是回憶、里程碑、對話書籤三種合在一起（書籤是聊天與紀錄之間的橋）', kinds);

  perform pg_temp.ok(j->0->>'title' = '今天的事', '最新的排最前面', j->0->>'title');
  perform pg_temp.ok(
    (select e->>'title' from jsonb_array_elements(j) e where e->>'kind' = 'bookmark')
      like '%拉麵%',
    '書籤帶著原來那句話一起出現（不然時間線上會是一個看不懂的項目）', j::text);

  -- 對方的私人書籤不會混進來
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.toggle_message_bookmark(mid, 'love', '我自己偷偷記的');
  perform set_config('request.jwt.claim.sub', a::text, true);
  j := public.companion_timeline(lk);
  perform pg_temp.ok(j::text not like '%偷偷記%',
    '對方設成私人的書籤不會出現在共同的時間線上', j::text);

  -- 刪掉整段關係時全部跟著走
  perform set_config('request.jwt.claim.sub', a::text, true);
  delete from public.companion_links where id = lk;
  perform pg_temp.ok(
    (select count(*) from public.companion_memories where link_id = lk) = 0
    and (select count(*) from public.companion_milestones where link_id = lk) = 0
    and (select count(*) from public.companion_goals where link_id = lk) = 0,
    '刪掉整段關係時回憶、里程碑、目標都跟著走（不留孤兒）');

  raise notice '=== 陪伴紀錄第 3、4 步測試結束 ===';
end $$;
