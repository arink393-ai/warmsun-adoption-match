-- 八個生活場景：資料來源 ↔ 規則庫最終狀態的一致性，加上三個新題組的行為。
--
-- 這一份跟 gen-topics.mjs --check 分工：那邊驗「產生物有沒有跟 JSON 漂移」，
-- 這邊驗「規則庫實際比對的字串，是不是選項裡真的有的字」。
-- 後者一定要在資料庫上驗——schema 是可重跑的檔案，同一條規則會先在第 18 節建立、
-- 再被第 20／23 節改寫，靜態讀檔看到的是所有歷史版本，不是最終狀態。
\set ON_ERROR_STOP on
\pset pager off
\t on

\i data/topic-options.sql

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

create or replace function pg_temp.mkuser(p_id uuid, p_name text) returns void
language plpgsql as $$
begin
  insert into auth.users (id, email) values (p_id, p_name || '@t.test')
    on conflict (id) do nothing;
  insert into public.match_profiles (id, name, kind, species, consent)
    values (p_id, p_name, 'keeper', 'dog', true)
    on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      species = excluded.species, consent = excluded.consent;
end $$;

-- 兩個人跑一次初診，回傳命中的規則代碼。
-- run_screening() 把結果寫進 screening_results，不是直接回傳 findings；
-- 而且它有快取，所以要先把 updated_at 推一下才會真的重算。
create or replace function pg_temp.hits(p_a uuid, p_b uuid) returns text[]
language plpgsql as $$
declare ks text[];
begin
  update public.match_profiles set updated_at = clock_timestamp() where id in (p_a, p_b);
  perform public.run_screening(p_a, p_b);
  select coalesce(array_agg(f->>'code'), '{}'::text[]) into ks
    from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = p_a and s.to_user = p_b;
  return ks;
end $$;

-- 某一條規則命中時的那一筆 finding（拿來驗文案）
create or replace function pg_temp.finding(p_a uuid, p_b uuid, p_code text) returns jsonb
language sql stable as $$
  select f from public.screening_results s, jsonb_array_elements(s.findings) f
   where s.from_user = p_a and s.to_user = p_b and f->>'code' = p_code;
$$;

-- ════════════════════════════════════════════════════════════
-- 一、資料來源 ↔ 規則庫
-- ════════════════════════════════════════════════════════════
do $$
declare n int; bad text;
begin
  raise notice '=== 資料來源一致性 ===';

  -- 八個題組、十八個欄位
  select count(distinct topic) into n from topic_cols;
  perform pg_temp.ok(n = 8, '八個生活場景都在資料來源裡', n::text);
  select count(*) into n from topic_cols;
  perform pg_temp.ok(n = 18, '十八個結構化欄位', n::text);

  -- 每個欄位都真的存在於 match_profiles（拼錯的話規則永遠讀到 null）
  select string_agg(t.col, '、') into bad
    from topic_cols t
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema='public' and c.table_name='match_profiles'
                        and c.column_name = t.col);
  perform pg_temp.ok(bad is null, '每個欄位都真的存在於 match_profiles', bad);

  /* ── 這是整份測試最重要的一項 ─────────────────────────────
     規則庫裡拿去比對的每一個字串，都必須是選項裡真的有的字。
     差一個字，那條規則會從此永遠不命中——不會報錯、不會有紅字，
     畫面上完全看不出來，只是那個題組再也不會亮燈。 */
  with refs as (
    select r.code, x.f, x.op, x.val
      from public.screening_rules r,
           lateral (
             with recursive walk(node) as (
               select r.cond
               union all
               select child
                 from walk w,
                      lateral jsonb_array_elements(
                        case
                          when w.node ? 'all' then w.node->'all'
                          when w.node ? 'any' then w.node->'any'
                          when w.node ? 'not' then jsonb_build_array(w.node->'not')
                          else '[]'::jsonb
                        end) child
             )
             select w.node->>'field' as f,
                    coalesce(w.node->>'op','eq') as op,
                    w.node->'value' as val
               from walk w where w.node ? 'field'
           ) x
     where r.enabled
  ), lits as (
    select refs.code,
           regexp_replace(refs.f, '^(applicant|recipient)\.', '') as col,
           v as lit
      from refs,
           lateral jsonb_array_elements_text(
             case when jsonb_typeof(refs.val) = 'array' then refs.val
                  when jsonb_typeof(refs.val) = 'string' then jsonb_build_array(refs.val)
                  else '[]'::jsonb end) v
     where refs.f ~ '^(applicant|recipient)\.[a-z0-9_]+$'
       and refs.op in ('eq','ne','in','not_in','contains')
  )
  select string_agg(distinct l.code || '：' || l.col || ' = ' || l.lit, '；') into bad
    from lits l
    join topic_cols tc on tc.col = l.col
   where not exists (select 1 from topic_opts o where o.col = l.col and o.opt = l.lit);
  perform pg_temp.ok(bad is null,
    '規則比對的每一個字串都是選項裡真的有的字（差一個字就永遠不命中）', bad);

  /* 反過來：做成結構化題目、卻沒有任何啟用中的規則在讀的欄位。
     那就違反了「只有會改變初診結果的資料才值得結構化」——
     等於白白增加填寫成本。 */
  select string_agg(tc.col, '、') into bad
    from topic_cols tc
   where not exists (
     select 1 from public.screening_rules r
      where r.enabled and r.cond::text like '%' || tc.col || '%');
  perform pg_temp.ok(bad is null,
    '每個結構化欄位都至少有一條啟用中的規則在讀（不然不該問）', bad);

  /* 規則引擎讀得到嗎？screening_subject() 是白名單，漏一個的後果跟遮罩
     黑名單漏一個相反、但一樣安靜：規則永遠讀到 null，從此不會命中。 */
  perform pg_temp.mkuser('00000000-0000-0000-0000-0000000001f0'::uuid, 'wl');
  select string_agg(tc.col, '、') into bad
    from topic_cols tc
   where not (public.screening_subject('00000000-0000-0000-0000-0000000001f0'::uuid) ? tc.col);
  perform pg_temp.ok(bad is null,
    '每個結構化欄位都在 screening_subject() 的白名單裡（不然規則永遠讀到 null）', bad);

  -- 這些欄位都不能是禁止欄位
  select string_agg(tc.col, '、') into bad
    from topic_cols tc
   where tc.col = any (public.screening_forbidden_fields());
  perform pg_temp.ok(bad is null, '沒有任何結構化欄位踩到禁止規則', bad);

  -- 五條原本關著的規則現在都開了，而且沒有任何規則還關著
  select count(*) into n from public.screening_rules where not enabled and code like 'R%';
  perform pg_temp.ok(n = 0, '原本關著的五條都已經重寫並開啟，規則庫沒有停用中的規則', n::text);

  raise notice '=== 資料來源一致性結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、居家社交界線 R034／R034B
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000001a1';
  b uuid := '00000000-0000-0000-0000-0000000001a2';
  ks text[]; j jsonb;
begin
  raise notice '--- 居家社交界線 ---';
  perform pg_temp.mkuser(a, 'soc_a');
  perform pg_temp.mkuser(b, 'soc_b');

  -- 都喜歡邀朋友 → 不亮
  update public.match_profiles set home_social_frequency = '喜歡常邀請朋友來家裡' where id in (a,b);
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks && array['R034','R034B']),
    '兩個人都喜歡邀朋友來家裡 → 不亮燈', array_to_string(ks,','));

  -- 一方常邀、一方希望是私人空間 → 🟡
  update public.match_profiles set home_social_frequency = '希望家是高度私人的空間' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R034'], '一方常邀朋友、一方希望家是私人空間 → 🟡', array_to_string(ks,','));

  -- 只是「比較喜歡在外面聚會」也算期待不同，但不會升成紅燈
  update public.match_profiles set home_social_frequency = '比較喜歡在外面聚會' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R034'] and not (ks @> array['R034B']),
    '一方常邀、一方喜歡在外面聚會 → 只有 🟡', array_to_string(ks,','));

  -- 加上界線與雙方不可妥協 → 🔴
  update public.match_profiles set home_social_frequency = '希望家是高度私人的空間',
    home_guest_boundary = '不希望朋友進入私人空間',
    dealbreakers = '{"home_social_boundary":"non_negotiable"}'::jsonb where id = b;
  update public.match_profiles
     set dealbreakers = '{"home_social_boundary":"non_negotiable"}'::jsonb where id = a;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R034B'], '再加上「不希望朋友進家門」且雙方不可妥協 → 🔴',
    array_to_string(ks,','));
  -- 同一個題組只會留一條
  perform pg_temp.ok(not (ks @> array['R034']),
    '同一個題組只留最嚴重的那一條，不會同時報 🟡 和 🔴', array_to_string(ks,','));

  -- 只有一方標不可妥協 → 退回 🟡
  update public.match_profiles set dealbreakers = '{"home_social_boundary":"very_important"}'::jsonb where id = a;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R034'] and not (ks @> array['R034B']),
    '只有一方標不可妥協（另一方只是🟠）→ 退回 🟡', array_to_string(ks,','));

  -- 文案不能寫成內向／外向
  j := pg_temp.finding(a, b, 'R034');
  perform pg_temp.ok((j->>'body') ~ '不是外向或內向',
    'R034 的文案主動否定「內向／外向」的解讀，只講空間怎麼用', j->>'body');
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、家務責任 R035／R035B／R036
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000001b1';
  b uuid := '00000000-0000-0000-0000-0000000001b2';
  ks text[]; j jsonb;
begin
  raise notice '--- 家務責任 ---';
  perform pg_temp.mkuser(a, 'hw_a');
  perform pg_temp.mkuser(b, 'hw_b');

  -- 公平的定義一樣 → 不亮
  update public.match_profiles set housework_fairness = '兩個人做一樣多' where id in (a,b);
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks && array['R035','R036']),
    '兩個人對公平的定義一樣 → 不亮燈', array_to_string(ks,','));

  -- 「尚未想過」不算差異（沒想過不是立場）
  update public.match_profiles set housework_fairness = '尚未想過' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['R035']),
    '一方「尚未想過」不算立場不同，不亮燈', array_to_string(ks,','));

  -- 定義不同 → 🟡
  update public.match_profiles set housework_fairness = '整體貢獻平衡就好，不一定一樣多' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R035'], '對公平的定義不同 → 🟡', array_to_string(ks,','));

  -- 傳統性別角色 vs 平均分擔，且雙方不可妥協 → 🔴（R036 是 R035 的子規則）
  update public.match_profiles set housework_fairness = '依傳統性別角色分工',
    dealbreakers = '{"housework":"non_negotiable"}'::jsonb where id = b;
  update public.match_profiles set dealbreakers = '{"housework":"non_negotiable"}'::jsonb where id = a;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R036'],
    '傳統性別角色 vs 兩人做一樣多、雙方不可妥協 → 🔴', array_to_string(ks,','));
  perform pg_temp.ok(not (ks @> array['R035']),
    '同一個題組只留一條（🔴 蓋掉 🟡）', array_to_string(ks,','));

  j := pg_temp.finding(a, b, 'R036');
  perform pg_temp.ok((j->>'body') !~ '男性|女性|男生|女生',
    'R036 的文案不點名任何性別，只說前提不同', j->>'body');
  perform pg_temp.ok((j->>'body') ~ '不判斷哪一種比較好|不判斷',
    'R036 明講系統不判斷哪一種比較好', j->>'body');

  -- 整潔標準的處理方式不同 → 🟡（換一組人，避免被 🔴 蓋掉）
  update public.match_profiles set housework_fairness = '', dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set cleanliness_conflict_style = '以要求較高的一方為主' where id = a;
  update public.match_profiles set cleanliness_conflict_style = '各自負責自己的空間' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R035B'],
    '整潔標準不同時的處理方式不一致 → 🟡', array_to_string(ks,','));
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、宗教界線 R041／R041B／R041C
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000001c1';
  b uuid := '00000000-0000-0000-0000-0000000001c2';
  ks text[]; j jsonb; n int;
begin
  raise notice '--- 宗教界線 ---';
  perform pg_temp.mkuser(a, 'rel_a');
  perform pg_temp.mkuser(b, 'rel_b');

  /* 最重要的一項：信仰不同本身永遠不亮燈。
     規則庫裡不能有任何一條去比對信仰內容——我們根本沒有那個欄位，
     這裡順便確認沒有人偷偷加回來。 */
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'match_profiles'
     and column_name in ('religion','faith','religion_name');
  perform pg_temp.ok(n = 0, '資料庫裡沒有「信仰是什麼」這個欄位，只有重要程度與界線', n::text);

  -- 都可以互相尊重 → 不亮
  update public.match_profiles set religion_partner_expectation = '可以互相尊重，不需要改變',
    religion_importance = '有固定的信仰與習慣' where id = a;
  update public.match_profiles set religion_partner_expectation = '可以互相尊重，不需要改變',
    religion_importance = '沒有宗教信仰' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks && array['R041','R041B']),
    '雙方信仰不同、但都可以互相尊重 → 不亮任何警示', array_to_string(ks,','));

  -- 「有固定的信仰與習慣」對上「沒有宗教信仰」還不到需要提的程度
  perform pg_temp.ok(not (ks @> array['R041C']),
    '一方有固定信仰、一方沒有信仰 → 連中性提示都不給（這太常見了）', array_to_string(ks,','));

  -- 一方是生活核心、一方沒有信仰 → ⚪ 中性提示，不是黃燈
  update public.match_profiles set religion_importance = '是生活的核心' where id = a;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R041C'],
    '一方信仰是生活核心、一方沒有信仰 → ⚪ 中性提示', array_to_string(ks,','));
  j := pg_temp.finding(a, b, 'R041C');
  perform pg_temp.ok(j->>'outcome' = 'unknown',
    '而且它是 ⚪ 不是 🟡——信仰虔誠不是需要處理的問題', j->>'outcome');
  perform pg_temp.ok((j->>'body') ~ '不是問題', '文案明講「這不是問題」', j->>'body');

  -- 要求對方改宗、對方希望維持 → 需要雙方都不可妥協才 🔴
  update public.match_profiles
     set religion_partner_expectation = '希望伴侶跟隨自己的信仰' where id = a;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['R041']),
    '一方希望對方跟隨信仰，但沒有標不可妥協 → 還不到 🔴', array_to_string(ks,','));

  update public.match_profiles set dealbreakers = '{"religion_boundary":"non_negotiable"}'::jsonb
   where id in (a,b);
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R041'],
    '雙方都標不可妥協 → 🔴（看的是「要求」，不是信仰本身）', array_to_string(ks,','));
  j := pg_temp.finding(a, b, 'R041');
  perform pg_temp.ok((j->>'body') ~ '要求',
    'R041 的文案明說它看的是要求，不是信仰本身', j->>'body');

  -- 子女宗教教育的期待不同 → 🟡（清掉上面的 🔴 才看得到同題組的黃燈）
  update public.match_profiles set religion_partner_expectation = '可以互相尊重，不需要改變',
    religion_importance = '偶爾參與', dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles set religion_child_plan = '希望依照我的信仰' where id = a;
  update public.match_profiles set religion_child_plan = '可以再討論' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R041B'], '對子女宗教教育的期待不同 → 🟡', array_to_string(ks,','));

  -- 兩邊都「可以再討論」→ 不亮
  update public.match_profiles set religion_child_plan = '可以再討論' where id = a;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['R041B']),
    '兩邊都說可以再討論 → 不亮燈', array_to_string(ks,','));
end $$;

-- ════════════════════════════════════════════════════════════
-- 五、前任與異性界線 R044／R044B／R044C
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000001d1';
  b uuid := '00000000-0000-0000-0000-0000000001d2';
  ks text[]; j jsonb;
begin
  raise notice '--- 前任與異性界線 ---';
  perform pg_temp.mkuser(a, 'bnd_a');
  perform pg_temp.mkuser(b, 'bnd_b');

  /* 這一組最容易寫壞：不能變成「有異性朋友就亮燈」。 */
  update public.match_profiles set opposite_friend_boundary = '完全沒問題' where id in (a,b);
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks && array['R044','R044B','R044C']),
    '兩個人都覺得異性朋友完全沒問題 → 不亮燈（有異性朋友本身不是問題）',
    array_to_string(ks,','));

  -- 界線期待不同 → 🟡
  update public.match_profiles set opposite_friend_boundary = '需要提前告知' where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R044B'], '一方完全沒問題、一方希望先講一聲 → 🟡',
    array_to_string(ks,','));
  j := pg_temp.finding(a, b, 'R044B');
  perform pg_temp.ok((j->>'body') ~ '本身不是問題',
    'R044B 的文案明講有異性朋友本身不是問題', j->>'body');

  -- 前任聯絡：完全不能接受 vs 沒有問題，雙方不可妥協 → 🔴
  update public.match_profiles set ex_contact_acceptance = '完全不能接受',
    dealbreakers = '{"relationship_boundary":"non_negotiable"}'::jsonb where id = a;
  update public.match_profiles set ex_contact_acceptance = '沒有問題',
    dealbreakers = '{"relationship_boundary":"non_negotiable"}'::jsonb where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R044'], '前任聯絡的界線相反且雙方不可妥協 → 🔴',
    array_to_string(ks,','));
  perform pg_temp.ok(not (ks && array['R044B','R044C']),
    '同一個題組只留最嚴重的一條', array_to_string(ks,','));

  -- 複選清單：差幾項才算落差大
  update public.match_profiles set ex_contact_acceptance = '', opposite_friend_boundary = '',
    dealbreakers = '{}'::jsonb where id in (a,b);
  update public.match_profiles
     set relationship_boundary_actions = '["單獨旅行","深夜長時間聊天","單獨過夜"]'::jsonb where id = a;
  update public.match_profiles
     set relationship_boundary_actions = '["單獨旅行","深夜長時間聊天","單獨過夜"]'::jsonb where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['R044C']), '兩份界線清單一樣 → 不亮燈', array_to_string(ks,','));

  -- 差兩項還不到門檻
  update public.match_profiles
     set relationship_boundary_actions = '["單獨旅行","深夜長時間聊天","單獨過夜","一般吃飯"]'::jsonb
   where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['R044C']), '只差一項不算落差大', array_to_string(ks,','));

  -- 差三項 → 🟡
  update public.match_profiles
     set relationship_boundary_actions = '["一般吃飯","工作往來","分享親密的情緒問題"]'::jsonb
   where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R044C'], '兩份清單差三項以上 → 🟡', array_to_string(ks,','));

  j := pg_temp.finding(a, b, 'R044C');
  perform pg_temp.ok((j->>'body') ~ '不代表誰比較嚴格',
    'R044C 的文案明講勾多勾少沒有好壞', j->>'body');

  /* 勾得多的那一方跟勾得少的那一方對調，結果要一樣——
     這條比的是差集，不是誰的清單比較長。 */
  update public.match_profiles
     set relationship_boundary_actions = '["一般吃飯","工作往來","分享親密的情緒問題"]'::jsonb where id = a;
  update public.match_profiles
     set relationship_boundary_actions = '["單獨旅行","深夜長時間聊天","單獨過夜"]'::jsonb where id = b;
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(ks @> array['R044C'], '兩邊對調，結果一樣（比的是差集不是長度）',
    array_to_string(ks,','));

  -- 兩邊都沒填 → 不亮（沒填不是「完全一致」）
  update public.match_profiles set relationship_boundary_actions = '[]'::jsonb where id in (a,b);
  ks := pg_temp.hits(a, b);
  perform pg_temp.ok(not (ks @> array['R044C']),
    '兩邊都沒勾 → 不亮燈（沒填不等於一致）', array_to_string(ks,','));

  raise notice '=== 八個生活場景測試結束 ===';
end $$;
