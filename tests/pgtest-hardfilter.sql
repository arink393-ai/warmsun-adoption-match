-- 🔴 送出申請前的 Hard Filter 提醒
--
-- 這一份守三件事：
--   (1) **數字要跟稍後的初診報告一致。** 這裡沒有另外一套規則，
--       直接借用 run_screening() 既有的紅燈邏輯——如果自己重新定義一套，
--       「送出前顯示 2 項衝突」跟「審查時看到 3 項🔴」對不起來就很難查。
--   (2) **只回一個數字，不回是哪一項。** 「所以你就是嫌我收入低？」
--       這種對話不該在送出前的畫面就發生。
--   (3) **只提醒，不擋。** 呼叫這支函式本身不會阻止任何人送出申請——
--       那個決定留在前端。
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
  /* handle_new_match_user() 在 auth.users 新增時就先塞了一列空白的
     match_profiles（kind='' species=''）。on conflict do update 只會改
     我明確列出的欄位，kind/species 不列進去的話就會維持那個空白值，
     get_visible_match_profiles() 的 `p.kind <> ''` 條件會把它濾掉，
     然後這個人就變成「找不到這個人」——看起來像產品的錯，其實是 fixture 漏寫。 */
  insert into public.match_profiles(id, name, kind, species, gender, consent, account_status,
      photo_status, verify_status)
    values (uid, nm, 'pet', 'cat', 'f', true, 'active', 'approved', 'approved')
    on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      species = excluded.species, gender = excluded.gender, consent = excluded.consent,
      account_status = 'active',
      photo_status = 'approved', verify_status = 'approved', posting_locked = false;
end $$;

-- ════════════════════════════════════════════════════════════
-- 一、完全相容：0 項衝突
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f1a01';
  b uuid := '00000000-0000-0000-0000-0000000f1a02';
  r jsonb;
begin
  raise notice '=== 完全相容 ===';
  perform pg_temp.mkuser(a, '甲');
  perform pg_temp.mkuser(b, '乙');
  update public.match_profiles set relationship_goal = '以結婚為前提的長期穩定關係',
    marriage_intent = '一定要結婚', kids_plan = '想要小孩', dealbreakers = '{}'::jsonb
   where id in (a, b);

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.check_hard_filter(b);
  perform pg_temp.ok(r->>'conflicts' = '0', '完全相容時是 0', r::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、真的有衝突：數字要對，而且不能洩漏是哪一項
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f1b01';
  b uuid := '00000000-0000-0000-0000-0000000f1b02';
  r jsonb;
begin
  raise notice '=== 兩項不可妥協衝突 ===';
  perform pg_temp.mkuser(a, '丙');
  perform pg_temp.mkuser(b, '丁');

  -- R007：關係方向相反，且雙方都標成不可妥協
  update public.match_profiles set relationship_goal = '以結婚為前提的長期穩定關係',
    dealbreakers = jsonb_build_object('relationship_goal','non_negotiable','marriage_intent','non_negotiable')
   where id = a;
  update public.match_profiles set relationship_goal = '目前不尋找長期關係',
    marriage_intent = '不打算結婚',
    dealbreakers = jsonb_build_object('relationship_goal','non_negotiable','marriage_intent','non_negotiable')
   where id = b;
  update public.match_profiles set marriage_intent = '一定要結婚' where id = a;

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.check_hard_filter(b);
  perform pg_temp.ok(r->>'conflicts' = '2', '兩條規則同時命中，回傳 2', r::text);

  /* 這是整份測試最重要的一條：不能有 findings、topic、code 這種
     可以反推出「是哪一項」的欄位。 */
  perform pg_temp.ok(not (r ? 'findings') and not (r ? 'topics') and not (r ? 'topic')
                     and not (r ? 'reasons') and not (r ? 'codes'),
    '回傳裡沒有任何找得出「是哪一項」的欄位', r::text);
  perform pg_temp.ok((select count(*) from jsonb_object_keys(r)) = 1,
    '整包回傳只有一個欄位（conflicts）', r::text);

  -- 反方向也要一致（對方檢查我，看到的數字要一樣）
  perform set_config('request.jwt.claim.sub', b::text, true);
  r := public.check_hard_filter(a);
  perform pg_temp.ok(r->>'conflicts' = '2', '反過來查也是 2（規則本身是對稱的）', r::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、跟稍後的初診報告數字要一致
-- ════════════════════════════════════════════════════════════
-- 這裡刻意拆成兩個 do 區塊、不是一個：get_screening_for() 判斷快取還新不新，
-- 用的是 `screening_results.ran_at >= greatest(profiles.updated_at, rules.updated_at)`，
-- 而 profiles.updated_at 是用 now()（同一筆交易內凍結不動），
-- ran_at 用的是 clock_timestamp()（同一筆交易內還是會往前走）。
-- 如果預檢跟送出申請擠在同一個 do 區塊（同一筆交易）裡，
-- apply_to() 內部對 match_profiles 的 update 產生的 updated_at
-- 會凍結在交易剛開始那一刻，比預檢當下的 ran_at 還早，
-- get_screening_for() 就會誤判快取還新鮮，不會真的重跑 run_screening()，
-- 「送出申請之後才留下初診時間軸事件」這件事也就測不到。
-- 實際使用時，預檢跟送出申請本來就是兩次不同的請求（不同交易），
-- 不會有這個問題——這裡用兩個 do 區塊，就是在還原這個真實情況。
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f1c01';
  b uuid := '00000000-0000-0000-0000-0000000f1c02';
  r jsonb;
begin
  raise notice '=== 跟初診報告一致 ===';
  perform pg_temp.mkuser(a, '戊');
  perform pg_temp.mkuser(b, '己');
  update public.match_profiles set kids_plan = '想要小孩',
    dealbreakers = jsonb_build_object('kids_plan','non_negotiable') where id = a;
  update public.match_profiles set kids_plan = '不想要小孩',
    dealbreakers = jsonb_build_object('kids_plan','non_negotiable') where id = b;

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.check_hard_filter(b);
  perform pg_temp.ok(r->>'conflicts' = '1', '送出前看到 1 項衝突', r::text);
end $$;

do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f1c01';
  b uuid := '00000000-0000-0000-0000-0000000f1c02';
  app_row public.applications; s jsonb;
begin
  -- 真的送出申請，換對方登入看初診報告
  perform set_config('request.jwt.claim.sub', a::text, true);
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  perform set_config('request.jwt.claim.sub', b::text, true);
  s := public.get_screening_for(a);
  perform pg_temp.ok((s->>'red')::int = 1,
    '對方稍後看到的初診報告紅燈數跟送出前顯示的一致（沒有另外一套規則）', s::text);

  /* 而且這一列 screening_results 應該是同一列被更新，不是多插一列——
     不然同一對人會留下重複的初診紀錄。 */
  perform pg_temp.ok(
    (select count(*) from public.screening_results
      where from_user = a and to_user = b and audience = 'member') = 1,
    '預檢用的那一列會被真正的初診直接更新，不會留下重複紀錄');

  -- 預檢本身不會被記進 CRM 時間軸（那時候還沒有申請關係）
  perform pg_temp.ok(
    (select count(*) from public.application_events
      where app_id = app_row.id and kind = 'screened') = 1,
    '送出申請之後才有一筆「初診」時間軸事件，預檢那一次沒有留下紀錄');
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、只提醒不擋：檢查本身不影響 apply_to
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f1d01';
  b uuid := '00000000-0000-0000-0000-0000000f1d02';
  r jsonb; app_row public.applications;
begin
  raise notice '=== 只提醒不擋 ===';
  perform pg_temp.mkuser(a, '庚');
  perform pg_temp.mkuser(b, '辛');
  update public.match_profiles set relationship_goal = '以結婚為前提的長期穩定關係',
    dealbreakers = jsonb_build_object('relationship_goal','non_negotiable') where id = a;
  update public.match_profiles set relationship_goal = '目前不尋找長期關係',
    dealbreakers = jsonb_build_object('relationship_goal','non_negotiable') where id = b;

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.check_hard_filter(b);
  perform pg_temp.ok((r->>'conflicts')::int > 0, '確實有衝突', r::text);

  -- 即使有衝突，apply_to 仍然照樣送得出去——擋不擋是前端自己決定的事
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  perform pg_temp.ok(app_row.id is not null,
    '有 hard filter 衝突不會擋住 apply_to 本身（系統只提醒，不替使用者決定）');
end $$;

-- ════════════════════════════════════════════════════════════
-- 五、邊界情況
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f1e01';
  b uuid := '00000000-0000-0000-0000-0000000f1e02';
  x uuid := '00000000-0000-0000-0000-0000000f1e09';
begin
  raise notice '=== 邊界情況 ===';
  perform pg_temp.mkuser(a, '壬');
  perform pg_temp.mkuser(b, '癸');

  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.check_hard_filter(a);
    perform pg_temp.ok(false, '不能對自己檢查');
  exception when others then perform pg_temp.ok(true, '不能對自己檢查'); end;

  begin
    perform public.check_hard_filter(x);
    perform pg_temp.ok(false, '對不存在的人檢查會報錯');
  exception when others then perform pg_temp.ok(true, '對不存在的人檢查會報錯'); end;

  -- 封鎖之後不能檢查（跟 apply_to 同一條防線）
  insert into public.match_user_blocks(blocker_id, blocked_id) values (b, a);
  begin
    perform public.check_hard_filter(b);
    perform pg_temp.ok(false, '被對方封鎖後不能再檢查');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%無法對這個帳號%', '被對方封鎖後不能再檢查', sqlerrm);
  end;
  delete from public.match_user_blocks where blocker_id = b and blocked_id = a;

  -- 沒登入
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.check_hard_filter(b);
    perform pg_temp.ok(false, '沒登入不能檢查');
  exception when others then perform pg_temp.ok(true, '沒登入不能檢查'); end;

  raise notice '=== Hard Filter 測試結束 ===';
end $$;
