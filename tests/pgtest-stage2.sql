-- 第二階段結構化問診 S2-01～S2-05：先關著，但要證明「翻開關就會動」
-- 這一份的重點不是「它們現在不會亮」，而是「等表單做好、enabled=true 之後，
-- 不用改引擎、不用改條件，它們就是對的」。
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
    account_status, consent)
  values (p_id, p_name, 'pet', 'cat', 'f', 'approved', 'approved', 'active', true)
  on conflict (id) do update set name = excluded.name, kind = excluded.kind,
    species = excluded.species, photo_status = excluded.photo_status,
    verify_status = excluded.verify_status, account_status = excluded.account_status;
end $$;

create or replace function pg_temp.hits(a uuid, b uuid) returns text[]
language plpgsql as $$
declare r text[];
begin
  perform public.run_screening(a, b);
  select coalesce(array_agg(f->>'code'), '{}'::text[]) into r
    from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b;
  return r;
end $$;

create or replace function pg_temp.outcome_of(a uuid, b uuid, p_code text) returns text
language sql stable as $$
  select f->>'outcome' from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b and f->>'code' = p_code;
$$;

do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000ab01';
  b uuid := '00000000-0000-0000-0000-00000000ab02';
  ks text[]; n int; j jsonb;
begin
  raise notice '=== 掛著的狀態 ===';
  perform pg_temp.mkuser(a, 's2A');
  perform pg_temp.mkuser(b, 's2B');

  select count(*) into n from public.screening_rules where code like 'S2-%';
  perform pg_temp.ok(n = 6, 'S2-01～S2-05（含 S2-04B）共 6 條都在庫裡', n::text);

  select count(*) into n from public.screening_rules where code like 'S2-%' and enabled;
  perform pg_temp.ok(n = 0, '六條全部 enabled = false，現在不會影響任何人', n::text);

  /* requires 只能列「兩個方向的分支都會讀」的欄位。對稱的 any 規則
     （A 對上 B 或反過來）如果把單邊才會填的欄位列進去，另一邊沒填時
     整條就會被跳過——而那正是它要抓的情況。所以有兩條刻意是空的。 */
  select count(*) into n from public.screening_rules
   where code like 'S2-%' and cardinality(requires) > 0;
  perform pg_temp.ok(n = 5, '五條有 requires、S2-04B 刻意留空（任一方回答就要提醒）', n::text);

  /* 同一個坑也修掉了已經啟用的 R038——它原本要求雙方都填 family_visit_freq，
     但那條規則抓的正是「只有一邊填了期待」的情況。 */
  perform pg_temp.ok(
    (select cardinality(requires) from public.screening_rules where code = 'R038') = 0,
    'R038 的 requires 也清空了（同一個對稱規則的陷阱，那條是已經啟用的）');

  perform pg_temp.ok(
    (select cardinality(requires) from public.screening_rules where code = 'S2-02') = 2,
    'S2-02 沒有把單邊才會填的 partner_alone_time_acceptance 列進 requires',
    (select array_to_string(requires,',') from public.screening_rules where code = 'S2-02'));

  /* S2 規則的 priority 要比同題組的簡易版小，翻開開關後才留得下比較細的那一條 */
  perform pg_temp.ok(
    (select priority from public.screening_rules where code = 'S2-01')
      < (select priority from public.screening_rules where code = 'R031')
    and (select priority from public.screening_rules where code = 'S2-05')
      < (select priority from public.screening_rules where code = 'R039'),
    'S2 規則的 priority 比同題組的簡易版小（數字小＝優先留下）');

  -- topic 要跟簡易版一致，之後才會被「同題組只報最嚴重的一層」收斂
  perform pg_temp.ok(
    (select topic from public.screening_rules where code = 'S2-01')
      = (select topic from public.screening_rules where code = 'R030'),
    'S2-01 跟 R030 同一個 topic（之後不會同一件事講兩次）');
  perform pg_temp.ok(
    (select topic from public.screening_rules where code = 'S2-05')
      = (select topic from public.screening_rules where code = 'R039'),
    'S2-05 跟 R039 同一個 topic');

  -- 掛著的時候真的不會亮
  update public.match_profiles set contact_frequency = '希望一天中保持多次聯絡',
    dealbreakers = '{"contact_frequency":"non_negotiable"}'::jsonb where id = a;
  update public.match_profiles set contact_frequency = '不需要固定聯絡，有事情再說',
    dealbreakers = '{"contact_frequency":"non_negotiable"}'::jsonb where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['S2-01']), 'enabled=false 時不會出現在結果裡',
    array_to_string(ks, ','));

  -- ══ 以下把六條暫時打開，證明「翻開關就會動」═══════════════
  raise notice '=== 翻開開關之後 ===';
  update public.screening_rules set enabled = true where code like 'S2-%';

  -- S2-01 聯絡頻率
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['S2-01'], 'S2-01：一天多次 vs 有事再說，雙方不可妥協 → 命中',
    array_to_string(ks, ','));
  perform pg_temp.ok(pg_temp.outcome_of(a, b, 'S2-01') = 'red', 'S2-01 是 🔴',
    pg_temp.outcome_of(a, b, 'S2-01'));
  perform pg_temp.ok(not (ks @> array['R030']) and not (ks @> array['R031']),
    '同題組只留最細的那一條，R030／R031 被收斂掉（不會同一件事講三次）',
    array_to_string(ks, ','));

  -- 只有一方不可妥協 → 不該是 🔴
  update public.match_profiles set dealbreakers = '{"contact_frequency":"very_important"}'::jsonb
   where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['S2-01']),
    '一方只標 🟠 非常重要時不會亮 🔴（🟠 不等於不可妥協）', array_to_string(ks, ','));
  perform pg_temp.ok(ks @> array['R030'],
    '降回簡易版的 🟡「聯絡頻率期待不同」', array_to_string(ks, ','));

  -- S2-02 陪伴／獨處
  raise notice '--- S2-02 陪伴與獨處 ---';
  update public.match_profiles set contact_frequency = '', dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set alone_time_need = '我非常重視獨立生活與個人空間',
    dealbreakers = '{"alone_time":"non_negotiable"}'::jsonb where id = a;
  update public.match_profiles set alone_time_need = '很少，我喜歡大部分時間一起行動',
    partner_alone_time_acceptance = '無法接受',
    dealbreakers = '{"alone_time":"non_negotiable"}'::jsonb where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['S2-02'], 'S2-02：高獨處 vs 高陪伴且無法接受 → 命中',
    array_to_string(ks, ','));
  select f into j from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b and f->>'code' = 'S2-02';
  perform pg_temp.ok((j->>'body') like '%這不是誰太黏或誰太冷淡%',
    'S2-02 的文案主動否定「一個太黏、一個太冷淡」這種說法', j->>'body');
  perform pg_temp.ok((j->>'body') like '%兩種都成立的需求%',
    'S2-02 明講兩種需求都成立，只是對不上');

  -- 對方可以接受時就不該亮
  update public.match_profiles set partner_alone_time_acceptance = '視情況討論' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['S2-02']),
    '對方回答「視情況討論」就不亮（差距本身不是問題，無法接受才是）', array_to_string(ks, ','));

  -- S2-03 家務
  raise notice '--- S2-03 家務 ---';
  update public.match_profiles set alone_time_need = '', partner_alone_time_acceptance = '',
    dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set housework_model = '按彼此擅長與喜好分配，不一定一人一半' where id = a;
  update public.match_profiles set housework_model = '原則上平均分配' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['S2-03']),
    'S2-03：平均分配 vs 按擅長分配 → 不亮燈（這兩個不衝突）', array_to_string(ks, ','));

  update public.match_profiles set housework_model = '傾向由其中一方主要負責',
    dealbreakers = '{"housework":"non_negotiable"}'::jsonb where id = a;
  update public.match_profiles set dealbreakers = '{"housework":"non_negotiable"}'::jsonb where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['S2-03'],
    'S2-03：一方主要負責 vs 平均分配，雙方不可妥協 → 🔴', array_to_string(ks, ','));

  -- S2-04 衝突節奏
  raise notice '--- S2-04 衝突節奏 ---';
  update public.match_profiles set housework_model = '', dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set conflict_pause_preference = '當下就談清楚' where id = a;
  update public.match_profiles set conflict_pause_preference = '可能需要 2～3 天' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['S2-04'], 'S2-04：當下就談 vs 需要 2～3 天 → 🟡',
    array_to_string(ks, ','));
  perform pg_temp.ok(pg_temp.outcome_of(a, b, 'S2-04') = 'yellow',
    'S2-04 是 🟡，不是 🔴——節奏不同不是不適合', pg_temp.outcome_of(a, b, 'S2-04'));

  -- S2-04B：不承諾回來談 → ⚪，而且絕對不能被寫成冷暴力
  update public.match_profiles set conflict_return_commitment = '不想承諾時間' where id = b;
  ks := pg_temp.hits(a, b);
  select f into j from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b and f->>'code' in ('S2-04','S2-04B');
  perform pg_temp.ok(ks && array['S2-04','S2-04B'], '衝突題組有東西亮著', array_to_string(ks, ','));
  perform pg_temp.ok(
    (select count(*) from public.screening_rules where code = 'S2-04B' and outcome = 'unknown') = 1,
    'S2-04B 的輸出是 ⚪，不是黃燈也不是紅燈');
  perform pg_temp.ok(
    (select body from public.screening_rules where code = 'S2-04B') like '%不等於冷暴力%',
    'S2-04B 明講「這不等於冷暴力」，不替任何人下判斷');
  /* 提到「冷暴力」不是問題（R046、R058 都在講「不要判定」）；
     問題是有沒有哪一條把它寫成使用者的既定事實。 */
  perform pg_temp.ok(
    (select count(*) from public.screening_rules
      where title ~ '(有|會|傾向).{0,4}冷暴力' or body ~ '判定為冷暴力|有冷暴力傾向') = 0,
    '規則庫裡沒有任何一條把使用者判定成冷暴力');

  -- S2-05 原生家庭界線
  raise notice '--- S2-05 原生家庭界線 ---';
  update public.match_profiles set conflict_pause_preference = '', conflict_return_commitment = ''
   where id in (a,b);
  update public.match_profiles set parents_in_decisions = '家人的意見通常會是重要決定因素',
    dealbreakers = '{"parents_in_decisions":"non_negotiable"}'::jsonb where id = a;
  update public.match_profiles set parents_in_decisions = '我和伴侶共同決定',
    dealbreakers = '{"parents_in_decisions":"non_negotiable"}'::jsonb where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['S2-05'], 'S2-05：家人同意 vs 伴侶共同決定，雙方不可妥協 → 🔴',
    array_to_string(ks, ','));
  select f into j from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = a and s.to_user = b and f->>'code' = 'S2-05';
  perform pg_temp.ok((j->>'body') like '%界線設定不同%' and (j->>'body') not like '%媽寶%',
    'S2-05 寫成「界線設定不同」，不是判誰媽寶', j->>'body');

  -- 只是回家頻率不同 → 🟡，不是 🔴
  update public.match_profiles set parents_in_decisions = '', dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set family_visit_freq = '很少' where id = a;
  update public.match_profiles set req_family_involvement = '希望經常參與' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R038'],
    '只是參與程度期待不同 → 🟡（R038），不會升成 🔴', array_to_string(ks, ','));

  -- ══ 收工：一定要關回去 ═════════════════════════════════════
  update public.screening_rules set enabled = false where code like 'S2-%';
  select count(*) into n from public.screening_rules where code like 'S2-%' and enabled;
  perform pg_temp.ok(n = 0, '測試結束，六條都關回去了', n::text);

  raise notice '=== 第二階段問診測試結束 ===';
end $$;
