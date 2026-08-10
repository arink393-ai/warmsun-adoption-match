-- 其餘 41 條規則、Dealbreaker 嚴重度、安全佇列 R056–R058
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

create or replace function pg_temp.mkuser(p_id uuid, p_name text, p_admin boolean default false)
returns void language plpgsql as $$
begin
  insert into auth.users(id, email) values (p_id, p_name || '@t.local') on conflict do nothing;
  insert into public.match_profiles(id, name, kind, species, gender, photo_status, verify_status,
    account_status, consent, is_admin)
  values (p_id, p_name, 'pet', 'cat', 'f', 'approved', 'approved', 'active', true, p_admin)
  on conflict (id) do update set name = excluded.name, is_admin = excluded.is_admin,
    kind = excluded.kind, species = excluded.species, photo_status = excluded.photo_status,
    verify_status = excluded.verify_status, account_status = excluded.account_status;
end $$;

-- 跑一次初診並回傳命中的規則代號
create or replace function pg_temp.codes(a uuid, b uuid) returns text[]
language plpgsql as $$
declare r text[];
begin
  perform public.run_screening(a, b);
  select coalesce(array_agg(f->>'code'), '{}'::text[]) into r
    from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b;
  return r;
end $$;

do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000000f1';
  b uuid := '00000000-0000-0000-0000-0000000000f2';
  ks text[]; n int;
begin
  raise notice '=== 規則庫盤點 ===';
  perform pg_temp.mkuser(a, 'ruleA');
  perform pg_temp.mkuser(b, 'ruleB');

  select count(*) into n from public.screening_rules
   where code ~ '^R0[0-5][0-9]$' and code between 'R001' and 'R058';
  perform pg_temp.ok(n = 58, 'R001–R058 全部 58 條都在規則庫裡', n::text);

  /* R034／R035／R036／R041／R044 原本是「放在表單上問不到真話」而關著的五條。
     第 23 節先決定「問什麼才問得到真話」，再把規則重寫到那些欄位上，五條都開了。
     這裡斷言「一條都沒關著」——關著的規則等於一個沒人在看的洞：
     欄位還在、表單還在問，燈卻永遠不會亮。 */
  select count(*) into n from public.screening_rules where not enabled and code like 'R%';
  perform pg_temp.ok(n = 0,
    '規則庫裡沒有停用中的規則（原本關著的五條已在第 23 節重寫並開啟）', n::text);
  /* 第二階段結構化表單做好之後（schema §21），這六條才打開。
     這裡斷言「全開」而不是「全關」——如果哪天表單被拿掉、欄位卻留著，
     這六條會拿 null 去比對而永遠不亮燈，那是沉默的失效，不是安全狀態。 */
  select count(*) into n from public.screening_rules where enabled and code like 'S2-%';
  perform pg_temp.ok(n = 6,
    '第二階段結構化問診的六條都已開啟（表單做好了）', n::text);

  select count(*) into n from public.screening_rules where outcome = 'never';
  perform pg_temp.ok(n = 15, '禁止規則與「刻意不觸發」共 15 條留在庫裡看得見', n::text);

  -- 禁止清單沒有被新規則汙染
  perform pg_temp.ok(
    public.screening_forbidden_fields() @>
      array['mbti','height_cm','weight_kg','education','income','health','health_tags'],
    '加了 41 條規則之後，禁止欄位清單仍然完整');

  -- ── Dealbreaker：沒標不可妥協，就只有黃燈 ───────────────
  raise notice '--- Dealbreaker 嚴重度 ---';
  update public.match_profiles set relationship_goal = '以結婚為前提的長期穩定關係',
    dealbreakers = '{}'::jsonb where id = a;
  update public.match_profiles set relationship_goal = '目前不尋找長期關係',
    dealbreakers = '{}'::jsonb where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(ks @> array['R006'], 'R006：關係方向不同 → 🟡', array_to_string(ks,','));
  perform pg_temp.ok(not (ks @> array['R007']),
    '沒有人標不可妥協時，不會亮 🔴（這是整套規則的通則）', array_to_string(ks,','));

  update public.match_profiles set dealbreakers = '{"relationship_goal":"non_negotiable"}'::jsonb
   where id = a;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(not (ks @> array['R007']),
    '只有一方標不可妥協也還不夠——那是他自己要判斷的事', array_to_string(ks,','));

  update public.match_profiles set dealbreakers = '{"relationship_goal":"non_negotiable"}'::jsonb
   where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(ks @> array['R007'], 'R007：雙方都標不可妥協才亮 🔴', array_to_string(ks,','));
  perform pg_temp.ok(not (ks @> array['R006']),
    '亮 🔴 時不會同時亮 R006 的 🟡（R006 只涵蓋「觀望」那組）', array_to_string(ks,','));

  -- 「可討論」不等於「不可妥協」
  update public.match_profiles set dealbreakers = '{"relationship_goal":"discussable"}'::jsonb
   where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(not (ks @> array['R007']),
    '標成「可討論」不會升成 🔴', array_to_string(ks,','));

  -- ── escalate：🟡／🔴 依重要性 ───────────────────────────
  raise notice '--- 依重要性升級（R025）---';
  update public.match_profiles set relationship_goal = '', dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set debt = '有，可負擔範圍內', debt_when = 'public' where id = a;
  update public.match_profiles set req_partner_debt = '不接受伴侶有負債' where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(ks @> array['R025'], 'R025 命中', array_to_string(ks,','));
  select count(*) into n from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b and f->>'code' = 'R025' and f->>'outcome' = 'yellow';
  perform pg_temp.ok(n = 1, '沒標不可妥協時是 🟡', n::text);

  update public.match_profiles set dealbreakers = '{"partner_debt":"non_negotiable"}'::jsonb where id = b;
  perform pg_temp.codes(a, b);
  select count(*) into n from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b and f->>'code' = 'R025' and f->>'outcome' = 'red';
  perform pg_temp.ok(n = 1, '對方標成不可妥協後升級成 🔴（escalate）', n::text);

  -- ── 幾條代表性的新規則 ──────────────────────────────────
  raise notice '--- 新題組的規則 ---';
  update public.match_profiles set debt = '', debt_when = 'never', dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set req_partner_debt = '' where id = b;

  -- R016 寵物：不需要雙方都標不可妥協
  update public.match_profiles set has_pets = '有，不能放棄' where id = a;
  update public.match_profiles set pet_acceptance = '過敏或無法與寵物共同生活' where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(ks @> array['R016'],
    'R016：寵物不可放棄 vs 無法共同生活 → 🔴（過敏是事實限制，不是偏好）',
    array_to_string(ks,','));

  -- R029 作息：單純作息不同不觸發，要加上「都要固定相處」
  update public.match_profiles set has_pets = '', pet_acceptance = '' where id in (a,b);
  update public.match_profiles set chronotype = '早鳥型', daily_together_need = '一週幾次' where id = a;
  update public.match_profiles set chronotype = '夜貓型', daily_together_need = '一週幾次' where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(not (ks @> array['R029']),
    'R028／R029：單純作息相反不觸發（早鳥 vs 夜貓本身不是問題）', array_to_string(ks,','));
  update public.match_profiles set daily_together_need = '每天要有固定相處時間' where id in (a,b);
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(ks @> array['R029'],
    'R029：作息相反＋雙方都要固定相處 → 🟡', array_to_string(ks,','));

  -- R046 綠燈：「先說一聲再暫停」跟冷暴力是相反的兩件事
  update public.match_profiles set chronotype = '', daily_together_need = '' where id in (a,b);
  update public.match_profiles set conflict_style = '會先說一聲再暫停，之後回來處理' where id in (a,b);
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(ks @> array['R046'], 'R046：雙方都會先告知再暫停 → 🟢', array_to_string(ks,','));

  update public.match_profiles set conflict_style = '當下就想處理' where id = a;
  update public.match_profiles set conflict_style = '需要冷靜一段時間' where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(ks @> array['R045'], 'R045：處理節奏不同 → 🟡', array_to_string(ks,','));
  perform pg_temp.ok(not (ks @> array['R046']), '節奏不同時不會同時亮綠燈');

  -- R023／R024：收入與負債本身不觸發
  raise notice '--- 刻意不觸發的那幾條 ---';
  update public.match_profiles set conflict_style = '' where id in (a,b);
  update public.match_profiles set income = '120 萬以上', debt = '有，目前壓力較大', debt_when = 'public'
   where id = a;
  update public.match_profiles set income = '60 萬以下', debt = '沒有' where id = b;
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(cardinality(ks) = 0 or not (ks && array['R023','R024']),
    'R023／R024：收入差距與「有負債」本身都不亮燈', array_to_string(ks,','));

  -- 停用的規則不會被評估
  raise notice '--- 停用的規則 ---';
  update public.match_profiles set income = '', debt = '', debt_when = 'never' where id in (a,b);
  ks := pg_temp.codes(a, b);
  perform pg_temp.ok(not (ks && array['R034','R035','R036','R041','R044']),
    '停用的五條完全不會出現在結果裡', array_to_string(ks,','));

  raise notice '=== 規則庫測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 安全佇列 R056–R058
-- ════════════════════════════════════════════════════════════
do $$
declare
  boss uuid := '00000000-0000-0000-0000-0000000000f9';
  bad  uuid := '00000000-0000-0000-0000-0000000000fa';
  r1   uuid := '00000000-0000-0000-0000-0000000000fb';
  r2   uuid := '00000000-0000-0000-0000-0000000000fc';
  q jsonb; row jsonb; codes text[]; outc text;
begin
  raise notice '--- 安全佇列 ---';
  perform pg_temp.mkuser(boss, 'safeboss', true);
  perform pg_temp.mkuser(bad,  'safebad');
  perform pg_temp.mkuser(r1,   'safer1');
  perform pg_temp.mkuser(r2,   'safer2');
  delete from public.reports where target_id = bad;
  update public.match_profiles set bio = '', wants = '', taboo = '' where id = bad;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- 一般會員不能看
  perform set_config('request.jwt.claim.sub', r1::text, true);
  begin
    perform public.admin_safety_queue();
    perform pg_temp.ok(false, '一般會員不該看得到安全佇列');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%管理員%', '一般會員看不到安全佇列');
  end;

  perform set_config('request.jwt.claim.sub', boss::text, true);
  q := public.admin_safety_queue();
  perform pg_temp.ok(q::text not like '%safebad%', '沒有任何旗標時不會出現在佇列上');

  -- R056：暴力類別的檢舉
  perform set_config('role', 'postgres', true);
  insert into public.reports(target_id, by_id, why, category) values (bad, r1, '言語威脅', 'violence');
  perform set_config('role', 'authenticated', true);
  q := public.admin_safety_queue();
  select r into row from jsonb_array_elements(q) r where r->>'user_id' = bad::text;
  select array_agg(f->>'code') into codes from jsonb_array_elements(row->'flags') f;
  perform pg_temp.ok(codes @> array['R056'], 'R056：暴力類別的未處理檢舉 → 🚨',
    array_to_string(codes,','));
  perform pg_temp.ok((row->>'priority')::int = 1, '有 🚨 的排在最前面', row->>'priority');

  -- R057：兩位互不相關的檢舉人
  perform set_config('role', 'postgres', true);
  insert into public.reports(target_id, by_id, why, category) values (bad, r2, '也被騷擾', 'harassment');
  perform set_config('role', 'authenticated', true);
  q := public.admin_safety_queue();
  select r into row from jsonb_array_elements(q) r where r->>'user_id' = bad::text;
  select array_agg(f->>'code') into codes from jsonb_array_elements(row->'flags') f;
  perform pg_temp.ok(codes @> array['R057'], 'R057：兩位互不相關的會員檢舉 → 🚨',
    array_to_string(codes,','));

  -- 檢舉人之間有申請關係時，就不算「互不相關」
  perform set_config('role', 'postgres', true);
  insert into public.applications(from_user, to_user, stage, status) values (r1, r2, 1, 'open');
  perform set_config('role', 'authenticated', true);
  q := public.admin_safety_queue();
  select r into row from jsonb_array_elements(q) r where r->>'user_id' = bad::text;
  select array_agg(f->>'code') into codes from jsonb_array_elements(row->'flags') f;
  perform pg_temp.ok(not (codes @> array['R057']),
    'R057：檢舉人之間有申請關係時就不算「互不相關」（避免一群朋友互相拉幫結派）',
    array_to_string(codes,','));
  perform set_config('role', 'postgres', true);
  delete from public.applications where from_user = r1 and to_user = r2;
  perform set_config('role', 'authenticated', true);

  -- R058：自由文字
  perform set_config('role', 'postgres', true);
  update public.match_profiles set taboo = '冷暴力,情緒勒索' where id = bad;
  perform set_config('role', 'authenticated', true);
  q := public.admin_safety_queue();
  select r into row from jsonb_array_elements(q) r where r->>'user_id' = bad::text;
  select array_agg(f->>'code') into codes from jsonb_array_elements(row->'flags') f;
  perform pg_temp.ok(codes @> array['R058'], 'R058：自由文字偵測命中', array_to_string(codes,','));
  select f->>'outcome' into outc from jsonb_array_elements(row->'flags') f where f->>'code' = 'R058';
  perform pg_temp.ok(outc = 'unknown',
    'R058 的輸出永遠是 ⚪，不是 🚨——「我無法接受冷暴力」跟「我會冷暴力」看起來一樣',
    outc);
  perform pg_temp.ok(row::text not like '%這個人有%' and row::text not like '%判定%',
    'R058 的文案不會寫成「這個人有這些行為」');

  -- 安全結果不會混進會員看得到的初診
  raise notice '--- 安全事件與一般初診完全分離 ---';
  perform pg_temp.ok(
    (select count(*) from public.screening_rules where outcome in ('safety') and audience <> 'admin') = 0,
    '🚨 規則一律是 audience=admin');
  /* screening_results 對前端完全不開放（那是刻意的），所以要切回 postgres 才查得到 */
  perform set_config('role', 'postgres', true);
  perform pg_temp.ok(
    (select count(*) from public.screening_results where audience = 'member'
      and (findings::text like '%R056%' or findings::text like '%R057%'
        or findings::text like '%R058%')) = 0,
    '會員看得到的初診結果裡沒有任何 R056–R058');
  perform pg_temp.ok(
    (select count(*) from public.screening_results where audience <> 'member') = 0,
    '安全事件根本不會寫進 screening_results（只在管理後台即時算）');

  raise notice '=== 安全佇列測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 新欄位一個都不能從佈告欄漏出去
-- get_visible_match_profiles() 是黑名單制：漏掉一個就是一次洩漏。
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000000f1';
  b uuid := '00000000-0000-0000-0000-0000000000f2';
  v jsonb; app_id uuid; leaked text;
  tier1 text[] := array['chronotype','contact_frequency','daily_together_need',
                        'alone_time_need','conflict_style','marriage_intent'];
  tier2 text[] := array['relocation','long_distance_ok','cohabit_with_parents',
                        'family_visit_freq','parents_in_decisions',
                        'relationship_structure','finance_style'];
  f text;
begin
  raise notice '--- 新欄位的遮罩 ---';
  perform set_config('role', 'postgres', true);
  update public.match_profiles set
    chronotype='夜貓型', contact_frequency='每天多次', daily_together_need='每天要有固定相處時間',
    alone_time_need='需要很多獨處時間', conflict_style='當下就想處理', marriage_intent='一定要結婚',
    relocation='不願意搬遷', long_distance_ok='不接受遠距', cohabit_with_parents='婚後必須與父母同住',
    family_visit_freq='每週', parents_in_decisions='父母會參與重大決定',
    relationship_structure='開放式關係', finance_style='完全共同財務',
    has_pets='有，不能放棄', pet_acceptance='可以一起照顧',
    dealbreakers='{"kids_plan":"non_negotiable","finance":"non_negotiable"}'::jsonb
   where id = a;
  delete from public.applications where (from_user,to_user) in ((a,b),(b,a));

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  select * into v from public.get_visible_match_profiles(a);

  leaked := '';
  foreach f in array (tier1 || tier2) loop
    if v->>f is not null then leaked := leaked || f || ' '; end if;
  end loop;
  perform pg_temp.ok(leaked = '', '第 0 層：13 個第 1／2 層的新欄位一個都沒漏出來', leaked);
  perform pg_temp.ok(v->>'has_pets' = '有，不能放棄',
    '寵物是刻意公開的（第 0 層就看得到）', v->>'has_pets');
  perform pg_temp.ok(not (v ? 'dealbreakers'), 'dealbreakers 細項完全不外流');
  perform pg_temp.ok((v->>'dealbreaker_count')::int = 2, '只給「有幾項不可妥協」',
    v->>'dealbreaker_count');

  perform set_config('role', 'postgres', true);
  insert into public.applications(from_user, to_user, stage, status)
    values (b, a, 1, 'open') returning id into app_id;
  perform set_config('role', 'authenticated', true);
  select * into v from public.get_visible_match_profiles(a);
  leaked := '';
  foreach f in array tier1 loop
    if v->>f is null then leaked := leaked || f || ' '; end if;
  end loop;
  perform pg_temp.ok(leaked = '', '第 1 層：生活節奏與結婚意願開放', leaked);
  leaked := '';
  foreach f in array tier2 loop
    if v->>f is not null then leaked := leaked || f || ' '; end if;
  end loop;
  perform pg_temp.ok(leaked = '', '第 1 層：家庭居住／關係結構／財務仍然收著', leaked);

  /* 這裡 b 是申請人（to_user 是 a），applications 的 RLS 只讓收件方改階段，
     所以要切回 postgres 才推得動——正式流程走的是 send_stage2 那類 RPC。 */
  perform set_config('role', 'postgres', true);
  perform set_config('app.bypass_app_guard', 'on', true);
  update public.applications set stage = 2 where id = app_id;
  perform set_config('app.bypass_app_guard', '', true);
  perform set_config('role', 'authenticated', true);
  select * into v from public.get_visible_match_profiles(a);
  leaked := '';
  foreach f in array tier2 loop
    if v->>f is null then leaked := leaked || f || ' '; end if;
  end loop;
  perform pg_temp.ok(leaked = '', '第 2 層：全部開放', leaked);

  raise notice '=== 遮罩測試結束 ===';
end $$;
