-- 主治醫師初診規則引擎：在真的 Postgres 16 上驗證
-- 用法：sudo -u postgres psql -d warmsun -f pgtest-screening.sql
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label ||
    coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

create or replace function pg_temp.mkuser(p_id uuid, p_name text) returns void
language plpgsql as $$
begin
  insert into auth.users(id, email) values (p_id, p_name || '@t.local') on conflict do nothing;
  insert into public.match_profiles(id, name, kind, species, gender, photo_status, verify_status,
    account_status, consent)
  values (p_id, p_name, 'pet', 'cat', 'f', 'approved', 'approved', 'active', true)
  -- handle_new_match_user() 這個 trigger 會在 auth.users 插入時先建一列預設的病歷卡
  -- （kind／species 都是空字串），所以這裡一定要把整列覆蓋掉，否則 get_visible_match_profiles
  -- 會因為 kind='' 而看不到這個人。
  on conflict (id) do update set
    name = excluded.name, kind = excluded.kind, species = excluded.species,
    gender = excluded.gender, photo_status = excluded.photo_status,
    verify_status = excluded.verify_status, account_status = excluded.account_status,
    consent = excluded.consent;
end $$;

do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000a1';
  u_b uuid := '00000000-0000-0000-0000-0000000000b1';
  res public.screening_results%rowtype;
  codes text[];
  n int; j jsonb; msg text;
begin
  raise notice '=== 準備兩個測試帳號 ===';
  perform pg_temp.mkuser(u_a, 'applicant');
  perform pg_temp.mkuser(u_b, 'recipient');

  -- ── 1. 工時規則 R001–R005 ────────────────────────────────
  raise notice '--- A. 工時（R001–R005）---';

  update public.match_profiles set weekly_work_hours = null where id = u_a;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select array_agg(f->>'code' order by f->>'code') into codes
    from jsonb_array_elements(res.findings) f;
  perform pg_temp.ok(codes @> array['R001'], 'R001：工時未填 → ⚪ 有一則「尚未提供工作時間」');
  perform pg_temp.ok(not (codes @> array['R002']) and not (codes @> array['R004']),
    'R001：工時未填時，R002–R005 全部不觸發（requires 缺欄位就跳過）');
  perform pg_temp.ok(res.unknown >= 1, 'R001：⚪ 計數 ≥ 1');

  for n, msg in
    select * from (values (45,'R002'),(70,'R002'),(85,'R003'),(120,'R004'),(200,'R005')) v(a,b)
  loop
    update public.match_profiles set weekly_work_hours = n where id = u_a;
    perform public.run_screening(u_a, u_b);
    select * into res from public.screening_results where from_user = u_a and to_user = u_b;
    select array_agg(f->>'code') into codes from jsonb_array_elements(res.findings) f;
    if n = 45 then
      perform pg_temp.ok(not (coalesce(codes,'{}') && array['R002','R003','R004','R005']),
        '工時 45 小時 → 不亮任何燈（正常工時不該被提醒）');
    else
      perform pg_temp.ok(codes @> array[msg], format('工時 %s 小時 → %s', n, msg));
      perform pg_temp.ok(cardinality(array(select unnest(codes) intersect select unnest(array['R002','R003','R004','R005']))) = 1,
        format('工時 %s 小時 → 四條工時規則只命中一條（區間互斥）', n));
    end if;
  end loop;

  update public.match_profiles set weekly_work_hours = 120 where id = u_a;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select f into j from jsonb_array_elements(res.findings) f where f->>'code' = 'R004';
  perform pg_temp.ok(jsonb_array_length(j->'ask') >= 1, 'R004：附帶建議問診題');
  perform pg_temp.ok((j->>'body') like '%待命%', 'R004：文案是「先確認資料代表什麼」而不是「你沒時間陪伴」');

  -- ── 2. 孩子規則 R013 / R014 / G002 ──────────────────────
  raise notice '--- E. 已有孩子（R013／R014／G002）---';

  update public.match_profiles set has_kids = '有，未同住' where id = u_a;
  update public.match_profiles set req_kids = '' where id = u_b;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select array_agg(f->>'code') into codes from jsonb_array_elements(res.findings) f;
  perform pg_temp.ok(codes @> array['R013'], 'R013：對方有孩子＋自己沒填孩子條件 → ⚪');

  update public.match_profiles set req_kids = '需沒有小孩' where id = u_b;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select array_agg(f->>'code') into codes from jsonb_array_elements(res.findings) f;
  perform pg_temp.ok(codes @> array['R014'], 'R014：對方有孩子＋條件是需沒有小孩 → 🔴');
  perform pg_temp.ok(res.red = 1, 'R014：🔴 計數 = 1');
  perform pg_temp.ok(not (codes @> array['R013']), 'R014 成立時 R013 不會同時出現');

  update public.match_profiles set req_kids = '可接受已有小孩' where id = u_b;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select array_agg(f->>'code') into codes from jsonb_array_elements(res.findings) f;
  perform pg_temp.ok(codes @> array['G002'] and res.red = 0, 'G002：可接受已有小孩 → 🟢，且沒有紅燈');

  -- ── 3. 生育規劃 R010 / R011 / G001 ──────────────────────
  raise notice '--- D. 生育規劃（R010／R011／G001）---';

  update public.match_profiles set kids_plan = '想要小孩' where id = u_a;
  update public.match_profiles set kids_plan = '不確定，需要再溝通' where id = u_b;
  perform public.run_screening(u_a, u_b);
  select array_agg(f->>'code') into codes from public.screening_results r,
    jsonb_array_elements(r.findings) f where r.from_user = u_a and r.to_user = u_b;
  perform pg_temp.ok(codes @> array['R010'], 'R010：想生 vs 不確定 → 🟡');

  update public.match_profiles set kids_plan = '不想要小孩' where id = u_a;
  perform public.run_screening(u_a, u_b);
  select array_agg(f->>'code') into codes from public.screening_results r,
    jsonb_array_elements(r.findings) f where r.from_user = u_a and r.to_user = u_b;
  perform pg_temp.ok(codes @> array['R011'], 'R011：不生 vs 不確定 → 🟡');

  update public.match_profiles set kids_plan = '不想要小孩' where id in (u_a, u_b);
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select array_agg(f->>'code') into codes from jsonb_array_elements(res.findings) f;
  perform pg_temp.ok(codes @> array['G001'], 'G001：雙方生育規劃相同 → 🟢');
  perform pg_temp.ok(not (coalesce(codes,'{}') && array['R010','R011']),
    'G001 成立時不會同時亮 R010／R011');

  -- 「不確定 vs 不確定」不該亮綠燈（兩個都沒決定，不是共識）
  update public.match_profiles set kids_plan = '不確定，需要再溝通' where id in (u_a, u_b);
  perform public.run_screening(u_a, u_b);
  select array_agg(f->>'code') into codes from public.screening_results r,
    jsonb_array_elements(r.findings) f where r.from_user = u_a and r.to_user = u_b;
  perform pg_temp.ok(not (coalesce(codes,'{}') @> array['G001']),
    '雙方都「不確定」不算一致，不亮 🟢');

  -- ── 4. R055 健康告知：只說有、不說是什麼，而且跟著本人選的時機 ──
  raise notice '--- U. 健康資料（R053–R055）---';

  update public.match_profiles
     set health = '規律服藥中，狀況穩定', health_tags = '["心血管疾病"]'::jsonb, health_when = 'stage2'
   where id = u_a;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select f into j from jsonb_array_elements(res.findings) f where f->>'code' = 'R055';
  perform pg_temp.ok(j is not null, 'R055：本人選擇在第二階段說明 → ⚪');
  perform pg_temp.ok((j->>'min_stage')::int = 2,
    'R055：min_stage 跟著本人選的 health_when 走（stage2 → 2）');
  perform pg_temp.ok(res.findings::text not like '%心血管%'
                 and res.findings::text not like '%規律服藥%',
    'R053／R054：初診結果裡完全沒有健康告知的內容，只說「有一項」');

  update public.match_profiles set health_when = 'never' where id = u_a;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  select array_agg(f->>'code') into codes from jsonb_array_elements(res.findings) f;
  perform pg_temp.ok(not (coalesce(codes,'{}') @> array['R055']),
    'R055：本人選「永遠不公開」時，連「有這件事」都不會透露');

  -- ── 5. 禁止規則 R047–R054 ───────────────────────────────
  raise notice '--- T. 禁止規則（R047–R054）---';

  perform pg_temp.ok(
    public.screening_forbidden_fields() @>
      array['mbti','height_cm','weight_kg','education','income','health','health_tags'],
    '禁止清單是從 outcome=never 的規則推出來的，七個欄位都在');

  -- 極端輸入：學歷、收入、身高、體重、MBTI 差到極點，也不能多出任何一盞燈
  update public.match_profiles set education='博士', income='120 萬以上', height_cm=190,
    weight_kg=95, mbti='INTJ', health='', health_tags='[]'::jsonb where id = u_a;
  update public.match_profiles set education='高中職以下', income='60 萬以下', height_cm=150,
    weight_kg=45, mbti='ESFP' where id = u_b;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  n := res.green + res.yellow + res.red;
  update public.match_profiles set education='大學', income='90～120 萬', height_cm=170,
    weight_kg=60, mbti='INFP' where id = u_a;
  update public.match_profiles set education='大學', income='90～120 萬', height_cm=170,
    weight_kg=60, mbti='INFP' where id = u_b;
  perform public.run_screening(u_a, u_b);
  select * into res from public.screening_results where from_user = u_a and to_user = u_b;
  perform pg_temp.ok(n = res.green + res.yellow + res.red,
    'R047–R051：學歷／收入／身高／體重／MBTI 從天差地遠改成完全相同，燈號數量一模一樣');

  -- screening_subject 根本不暴露這些欄位（第二道防線）
  j := public.screening_subject(u_a);
  perform pg_temp.ok(not (j ?| array['mbti','height_cm','weight_kg','education','income','health','health_tags']),
    'screening_subject 根本不把這七個欄位交給規則引擎');
  perform pg_temp.ok(j ? 'has_health_note' and j ? 'health_when',
    '健康告知只交出「有沒有」與「本人選的時機」兩個布林／列舉');

  -- 寫入違規規則必須被擋下來
  begin
    insert into public.screening_rules(code, topic, outcome, cond, requires, title)
    values ('X001','x','yellow','{"field":"applicant.income","op":"eq","value":"60 萬以下"}'::jsonb,
            '{applicant.income}','不該存在的規則');
    perform pg_temp.ok(false, '寫入引用收入的規則應該被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%違反禁止規則%', '寫入引用收入的規則被擋下來：' || left(sqlerrm, 40));
  end;

  begin
    insert into public.screening_rules(code, topic, outcome, cond, requires, title)
    values ('X002','x','yellow',
      '{"field":"applicant.age_num","op":"same","value":"recipient.age_num"}'::jsonb,
      '{applicant.age_num,recipient.age_num}','不該存在的規則');
    perform pg_temp.ok(false, '寫入「雙方年齡直接相比」的規則應該被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%年齡%', 'R052：寫入雙方年齡相比的規則被擋下來');
  end;

  -- ── 6. R052A：允許的唯一一種年齡用法 ─────────────────────
  raise notice '--- 年齡條件（R052A）---';
  update public.match_profiles set age = '45' where id = u_b;
  update public.match_profiles set req_age_min = '28', req_age_max = '40' where id = u_a;
  perform public.run_screening(u_a, u_b);
  select array_agg(f->>'code') into codes from public.screening_results r,
    jsonb_array_elements(r.findings) f where r.from_user = u_a and r.to_user = u_b;
  perform pg_temp.ok(codes @> array['R052A'], 'R052A：自己 45 歲、對方公開條件 28–40 → 🟡');

  update public.match_profiles set age = '35' where id = u_b;
  perform public.run_screening(u_a, u_b);
  select array_agg(f->>'code') into codes from public.screening_results r,
    jsonb_array_elements(r.findings) f where r.from_user = u_a and r.to_user = u_b;
  perform pg_temp.ok(not (coalesce(codes,'{}') @> array['R052A']), 'R052A：落在範圍內就不亮燈');

  update public.match_profiles set req_age_min = '', req_age_max = '' where id = u_a;
  perform public.run_screening(u_a, u_b);
  select array_agg(f->>'code') into codes from public.screening_results r,
    jsonb_array_elements(r.findings) f where r.from_user = u_a and r.to_user = u_b;
  perform pg_temp.ok(not (coalesce(codes,'{}') @> array['R052A']),
    'R052A：對方沒設年齡條件時不亮燈（value_ref 參照不到就當不成立）');

  raise notice '=== 規則引擎測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- get_screening_for()：分層、快取、封鎖
-- 這一段最重要的斷言是「第 0 層看得到數量，但看不到細節」——
-- 初診如果會說出「🔴 生育規劃衝突」，就等於繞過了四層漸進式揭露。
-- ════════════════════════════════════════════════════════════
do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000a1';
  u_b uuid := '00000000-0000-0000-0000-0000000000b1';
  r jsonb; t1 timestamptz; t2 timestamptz; app_id uuid;
begin
  raise notice '--- get_screening_for：揭露分層 ---';

  -- 造一組「有紅燈也有黃燈」的資料
  update public.match_profiles set has_kids = '有，同住', weekly_work_hours = 120,
    kids_plan = '想要小孩', age = '38' where id = u_a;
  update public.match_profiles set req_kids = '需沒有小孩',
    kids_plan = '不確定，需要再溝通', age = '35' where id = u_b;
  delete from public.applications where (from_user, to_user) in ((u_a,u_b),(u_b,u_a));
  delete from public.screening_results where from_user = u_a and to_user = u_b;

  -- 以 u_b 的身分呼叫（他在看 u_a 的病例）
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  r := public.get_screening_for(u_a);
  perform pg_temp.ok((r->>'stage')::int = 0, '還沒有申請關係 → stage 0');
  perform pg_temp.ok((r->>'red')::int >= 1, '第 0 層：看得到「🔴 N 項」的數量');
  perform pg_temp.ok((r->>'yellow')::int >= 1, '第 0 層：看得到「🟡 N 項」的數量');
  perform pg_temp.ok((r->>'hidden')::int >= 1, '第 0 層：有細節被收起來，並且告訴你有幾項');
  perform pg_temp.ok(r->>'findings' not like '%孩子%' and r->>'findings' not like '%生育%',
    '第 0 層：細節裡沒有洩漏對方的孩子或生育規劃');
  perform pg_temp.ok(r->>'findings' not like '%工作時間%' and r->>'findings' not like '%工作負荷%',
    '第 0 層：細節裡沒有洩漏對方的工時（工時是第 2 層資料）');
  perform pg_temp.ok((r->>'inputs_seen')::int > 0, '第 0 層：有回報「目前取得 N 項有效資料」');

  -- 建立第一階段申請關係
  -- u_a 是申請人、u_b 是收件人（也就是正在看報告的人）。方向要對，
  -- 因為 applications 的 RLS 只讓收件人（to_user）改階段——申請人不能自己把自己推進下一關。
  perform set_config('role', 'postgres', true);
  insert into public.applications(from_user, to_user, stage, status)
    values (u_a, u_b, 1, 'open') returning id into app_id;
  perform set_config('role', 'authenticated', true);

  r := public.get_screening_for(u_a);
  perform pg_temp.ok((r->>'stage')::int = 1, '送出第一階段申請 → stage 1');
  perform pg_temp.ok(r->>'findings' like '%孩子%', '第 1 層：孩子相關的細節開放了（has_kids 是第 1 層資料）');
  perform pg_temp.ok(r->>'findings' not like '%工作時間%' and r->>'findings' not like '%工作負荷%',
    '第 1 層：工時細節仍然收著（第 2 層才開放）');

  -- 進第二階段
  -- guard_application_privileged() 會把 stage 改回去，測試要明確帶旁路旗標
  -- （正式流程是走 advance_stage3 那類 RPC，不會有人直接 update）
  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set stage = 2 where id = app_id;
  perform set_config('app.bypass_app_guard', 'off', true);

  r := public.get_screening_for(u_a);
  perform pg_temp.ok((r->>'stage')::int = 2, '進第二階段 → stage 2');
  perform pg_temp.ok(r->>'findings' like '%工作時間非常高%', '第 2 層：工時細節開放');
  perform pg_temp.ok((r->>'hidden')::int = 0, '第 2 層：沒有東西被收起來了');
  perform pg_temp.ok((r->>'red')::int >= 1 and (r->>'yellow')::int >= 1,
    '數量在每一層都一樣，只有細節分層');

  raise notice '--- get_screening_for：快取 ---';
  t1 := (public.get_screening_for(u_a)->>'ran_at')::timestamptz;
  t2 := (public.get_screening_for(u_a)->>'ran_at')::timestamptz;
  perform pg_temp.ok(t1 = t2, '沒有資料變動時直接用快取，不重跑');

  raise notice '--- get_screening_for：拒絕的情境 ---';
  begin
    perform public.get_screening_for(u_b);
    perform pg_temp.ok(false, '對自己做初診應該被拒絕');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%自己%', '對自己做初診被拒絕');
  end;

  perform set_config('role', 'postgres', true);
  insert into public.match_user_blocks(blocker_id, blocked_id) values (u_a, u_b) on conflict do nothing;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.get_screening_for(u_a);
    perform pg_temp.ok(false, '被對方封鎖後應該連初診都查不到');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%找不到%', '被對方封鎖後，初診一併查不到（跟佈告欄一致）');
  end;
  perform set_config('role', 'postgres', true);
  delete from public.match_user_blocks where blocker_id = u_a and blocked_id = u_b;

  raise notice '=== get_screening_for 測試結束 ===';
end $$;

-- 快取失效必須跨交易才驗得出來：touch_updated_at() 用的是 now()，
-- 而 now() 在同一個交易裡永遠是交易開始時間，不會前進。
do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000a1';
  u_b uuid := '00000000-0000-0000-0000-0000000000b1';
  r jsonb; t0 timestamptz;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  t0 := (public.get_screening_for(u_a)->>'ran_at')::timestamptz;
  perform pg_temp.ok(t0 is not null, '（跨交易）先取得目前這份初診的時間');
end $$;

do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000a1';
  u_b uuid := '00000000-0000-0000-0000-0000000000b1';
  r jsonb; t0 timestamptz;
begin
  select ran_at into t0 from public.screening_results
   where from_user = u_a and to_user = u_b and audience = 'member';

  update public.match_profiles set weekly_work_hours = 45 where id = u_a;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  r := public.get_screening_for(u_a);
  perform pg_temp.ok((r->>'ran_at')::timestamptz > t0, '病歷卡改過之後會重跑初診');
  perform pg_temp.ok(r->>'findings' not like '%工作時間非常高%', '工時改成 45 之後，那盞黃燈消失');
  raise notice '=== 快取測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 新欄位不能從佈告欄漏出去
-- weekly_work_hours 跟 work_hours 是同一件事，遮罩層級必須一樣；
-- dealbreakers 的細項完全不外流，只給「有幾項不可妥協」。
-- ════════════════════════════════════════════════════════════
do $$
declare
  u_a uuid := '00000000-0000-0000-0000-0000000000a1';
  u_b uuid := '00000000-0000-0000-0000-0000000000b1';
  v jsonb; app_id uuid;
begin
  raise notice '--- 新欄位的遮罩 ---';
  update public.match_profiles
     set weekly_work_hours = 120, work_hours = '120 小時',
         dealbreakers = '{"kids_plan":"non_negotiable","marriage_intent":"discussable"}'::jsonb
   where id = u_a;
  delete from public.applications
   where (from_user, to_user) in ((u_a,u_b),(u_b,u_a));

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', u_b::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into v from public.get_visible_match_profiles(u_a);
  perform pg_temp.ok(v->'weekly_work_hours' = 'null'::jsonb or v->>'weekly_work_hours' is null,
    '第 0 層：weekly_work_hours 被遮住（跟 work_hours 同一層）', v->>'weekly_work_hours');
  perform pg_temp.ok(not (v ? 'dealbreakers'),
    'dealbreakers 的細項完全不出現在佈告欄資料裡');
  perform pg_temp.ok(v::text not like '%non_negotiable%',
    '不可妥協的題組名稱不會外流');
  perform pg_temp.ok((v->>'dealbreaker_count')::int = 1,
    '只給「有幾項不可妥協」', v->>'dealbreaker_count');

  perform set_config('role', 'postgres', true);
  insert into public.applications(from_user, to_user, stage, status)
    values (u_a, u_b, 2, 'open') returning id into app_id;
  perform set_config('role', 'authenticated', true);

  select * into v from public.get_visible_match_profiles(u_a);
  perform pg_temp.ok((v->>'weekly_work_hours')::int = 120,
    '第 2 層：weekly_work_hours 才開放', v->>'weekly_work_hours');
  perform pg_temp.ok(not (v ? 'dealbreakers'),
    '就算到第 2 層，dealbreakers 細項仍然不外流');

  raise notice '=== 遮罩測試結束 ===';
end $$;
