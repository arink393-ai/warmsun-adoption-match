-- 升級路徑：把整份 schema 重貼到「已經在跑的舊資料庫」上
--
-- 為什麼需要這一份：其他每一份 SQL 測試都是先 drop schema 再載入，
-- 也就是**每次都在全新的資料庫上跑**。那剛好是唯一碰不到升級問題的跑法。
--
-- 真正炸掉的是這個：`create table if not exists` 對已經存在的表是完全的 no-op，
-- 所以表建好之後才加進 check 清單的值，在既有資料庫上永遠不會生效——
-- 不會在載入 schema 時報錯，會等到有人 insert 才炸成 23514。
-- README 一直寫著「重新貼一次整份 supabase-schema.sql 執行即可」，
-- 這一份就是去驗那句話是不是真的。
--
-- 跑法：要從 repo 根目錄跑（它會 \i supabase-schema.sql）。
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

-- ════════════════════════════════════════════════════════════
-- 一、把資料庫改回「舊版」的樣子
-- ════════════════════════════════════════════════════════════
-- 這裡重現的就是實際發生過的那一次：第 24 節先建好 chat_safety_signals，
-- 第 25 節才把 'reported' 加進 class 的清單裡。
do $$
begin
  raise notice '=== 先把資料庫改成舊版的樣子 ===';
end $$;

-- 之後每加一個新 class，這一行也要跟著加，才回得去「舊版」的樣子。
-- 第 30 節的 reported_harm 就是第二次走到同一條路上。
delete from public.chat_safety_signals where class in ('reported','reported_harm');
alter table public.chat_safety_signals drop constraint if exists chat_safety_signals_class_check;
alter table public.chat_safety_signals add constraint chat_safety_signals_class_check
  check (class in ('sexual','body_topic','threat','threat_harm','coercion',
                   'intimate_image','request','selfref','refusal'));

alter table public.match_messages drop constraint if exists match_messages_safety_level_check;
alter table public.match_messages add constraint match_messages_safety_level_check
  check (safety_level in ('boundary','sexual','danger'));

alter table public.feedback drop constraint if exists feedback_category_check;
alter table public.feedback add constraint feedback_category_check
  check (category in ('bug','other'));
alter table public.feedback drop constraint if exists feedback_status_check;
alter table public.feedback add constraint feedback_status_check
  check (status in ('new','done'));

-- ════════════════════════════════════════════════════════════
-- 二、重貼整份 schema。這一步本身就是斷言：
--     ON_ERROR_STOP 開著，任何一個 23514 都會讓整份測試停在這裡。
-- ════════════════════════════════════════════════════════════
\i supabase-schema.sql

-- ════════════════════════════════════════════════════════════
-- 三、確認舊約束真的被換掉了（不是只有「沒報錯」）
-- ════════════════════════════════════════════════════════════
do $$
declare n int;
begin
  raise notice '=== 重貼之後 ===';

  select count(*) into n from public.chat_safety_signals where class = 'reported';
  perform pg_temp.ok(n >= 1,
    'chat_safety_signals 的 reported 類別補回來了（這就是實際炸掉的那一項）', n::text);

  select count(*) into n from public.chat_safety_signals where class = 'reported_harm';
  perform pg_temp.ok(n >= 1,
    'reported_harm 也補回來了（第 30 節診療室安全模式靠它）', n::text);

  -- 直接試插一筆，確認 check 真的放行而不是剛好沒被檢查到
  begin
    insert into public.chat_safety_signals(code, class, pattern, note)
      values ('ZZ_TEST', 'reported', '測試用', '測試用');
    perform pg_temp.ok(true, 'class = reported 的新規則插得進去');
    delete from public.chat_safety_signals where code = 'ZZ_TEST';
  exception when others then
    perform pg_temp.ok(false, 'class = reported 的新規則插得進去', sqlerrm);
  end;

  -- 不合法的值仍然要被擋（約束不能被換成「什麼都放行」）
  begin
    insert into public.chat_safety_signals(code, class, pattern, note)
      values ('ZZ_BAD', '亂七八糟的類別', 'x', 'x');
    perform pg_temp.ok(false, '不在清單裡的類別仍然被擋下來');
    delete from public.chat_safety_signals where code = 'ZZ_BAD';
  exception when others then
    perform pg_temp.ok(true, '不在清單裡的類別仍然被擋下來（不是把約束放寬成沒有用）');
  end;

  /* 底下用 pg_get_constraintdef() 而不是 information_schema.check_clause：
     後者會把 IS NULL 之類的關鍵字轉成大寫，而 like 是區分大小寫的——
     第一版就是這樣寫出一個永遠不會通過的斷言，看起來像產品壞了，其實是查詢寫錯。 */
  select count(*) into n from pg_constraint
   where conname = 'feedback_category_check' and pg_get_constraintdef(oid) like '%confusing%';
  perform pg_temp.ok(n = 1, 'feedback 的類別清單也更新了（舊版只有 bug/other）', n::text);

  select count(*) into n from pg_constraint
   where conname = 'feedback_status_check' and pg_get_constraintdef(oid) like '%seen%';
  perform pg_temp.ok(n = 1, 'feedback 的狀態清單也更新了（舊版沒有 seen）', n::text);

  -- match_messages 的等級：null 要放行（絕大多數訊息都沒有安全標記）
  select count(*) into n from pg_constraint
   where conname = 'match_messages_safety_level_check'
     and pg_get_constraintdef(oid) ilike '%is null%';
  perform pg_temp.ok(n = 1,
    'match_messages 的等級約束明確允許 null（沒有標記的訊息才存得進去）', n::text);

  raise notice '=== 升級路徑測試結束 ===';
end $$;
