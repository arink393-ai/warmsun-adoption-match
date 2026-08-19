-- ❤️ 關係能力評估（Relationship Readiness）
--
-- 這一份守四件事：
--   (1) **存檔驗證**：只收白名單裡的 6 個 key、每題有長度上限、
--       不能藏聯絡方式，跟第 26 節的興趣／個性標籤同一套規矩。
--   (2) **揭露分層**：第 2 層才看得到（比照第 23 節的宗教／感情史，
--       不是跟學歷同一層），第 0、1 層一律拿到 {}，不會洩漏內容。
--   (3) **沒有分數**：拿到的一律是原始文字（jsonb string），
--       不會出現任何數字或燈號。
--   (4) **白名單跟畫面上的題目文字同步**：guard_profile_custom_text()
--       裡的白名單是獨立寫的一份（理由見 schema 裡的註解），這裡逐一
--       拿 readiness_questions() 回傳的 6 個 key 去試存檔，兩邊只要
--       有一個字不一樣，這裡就會紅。
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
  insert into public.match_profiles(id, name, kind, species, gender, consent, account_status,
      photo_status, verify_status)
    values (uid, nm, 'pet', 'cat', 'f', true, 'active', 'approved', 'approved')
    on conflict (id) do update set name = excluded.name, kind = excluded.kind,
      species = excluded.species, gender = excluded.gender, consent = excluded.consent,
      account_status = 'active',
      photo_status = 'approved', verify_status = 'approved', posting_locked = false;
end $$;

-- ════════════════════════════════════════════════════════════
-- 一、存檔驗證
-- ════════════════════════════════════════════════════════════
do $$
declare a uuid := '00000000-0000-0000-0000-0000000f2a01'; r jsonb;
begin
  raise notice '=== 存檔驗證 ===';
  perform pg_temp.mkuser(a, '甲');
  perform set_config('request.jwt.claim.sub', a::text, true);

  -- 合法的兩題，而且前後各留一點空白測修剪
  update public.match_profiles set readiness = jsonb_build_object(
    'conflict_repair', '  先各自冷靜十分鐘，再回來把話說完。  ',
    'accountability', '直接承認是我忘記了，沒有找藉口。')
   where id = a;
  select readiness into r from public.match_profiles where id = a;
  perform pg_temp.ok(r->>'conflict_repair' = '先各自冷靜十分鐘，再回來把話說完。',
    '合法的回答存得進去，而且前後空白會被修剪', r::text);
  perform pg_temp.ok((select count(*) from jsonb_object_keys(r)) = 2,
    '只存了填過的那兩題', r::text);

  -- 空字串等於還沒回答，不佔位置
  update public.match_profiles set readiness = jsonb_build_object(
    'conflict_repair', '正常回答', 'boundary_respect', '   ')
   where id = a;
  select readiness into r from public.match_profiles where id = a;
  perform pg_temp.ok(not (r ? 'boundary_respect'),
    '只有空白的回答不會被存進去（等於還沒回答那一題）', r::text);

  -- 不在白名單裡的 key
  begin
    update public.match_profiles set readiness = jsonb_build_object('mbti', 'INFP') where id = a;
    perform pg_temp.ok(false, '不在白名單裡的 key 會被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%不是有效的關係能力題目%', '不在白名單裡的 key 會被擋下來', sqlerrm);
  end;

  -- 藏聯絡方式
  begin
    update public.match_profiles set readiness =
      jsonb_build_object('conflict_repair', '有事直接加我 LINE ID: abc123 比較快')
     where id = a;
    perform pg_temp.ok(false, '回答裡藏聯絡方式會被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%聯絡方式%', '回答裡藏聯絡方式會被擋下來', sqlerrm);
  end;

  -- 超過長度上限
  begin
    update public.match_profiles set readiness =
      jsonb_build_object('conflict_repair', repeat('字', 501))
     where id = a;
    perform pg_temp.ok(false, '超過 500 字會被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%超過 500 字%', '超過 500 字會被擋下來', sqlerrm);
  end;

  -- 剛好 500 字：不該被擋
  update public.match_profiles set readiness =
    jsonb_build_object('conflict_repair', repeat('字', 500))
   where id = a;
  select readiness into r from public.match_profiles where id = a;
  perform pg_temp.ok(char_length(r->>'conflict_repair') = 500, '剛好 500 字不會被擋', r::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、白名單跟畫面上的題目同步
-- ════════════════════════════════════════════════════════════
do $$
declare a uuid := '00000000-0000-0000-0000-0000000f2b01';
  q jsonb; k text; n int := 0;
begin
  raise notice '=== 白名單同步 ===';
  perform pg_temp.mkuser(a, '乙');
  perform set_config('request.jwt.claim.sub', a::text, true);

  q := public.readiness_questions();
  perform pg_temp.ok(jsonb_array_length(q) = 6, '題目一共 6 題', jsonb_array_length(q)::text);

  -- 逐一拿題目表裡的 key 去試存檔，只要有一個字跟 guard 裡的白名單兜不起來就會炸
  for k in select value->>'key' from jsonb_array_elements(q) loop
    update public.match_profiles set readiness = jsonb_build_object(k, '測試回答內容') where id = a;
    n := n + 1;
  end loop;
  perform pg_temp.ok(n = 6, 'readiness_questions() 的 6 個 key 全部都能存檔成功（跟白名單一致）', n::text);

  -- 每一題都要有 key／title／prompt 三個欄位，畫面才有東西可以顯示
  perform pg_temp.ok(not exists (
    select 1 from jsonb_array_elements(q) e
     where not (e ? 'key' and e ? 'title' and e ? 'prompt')),
    '每一題都有 key、title、prompt 三個欄位');
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、揭露分層：第 2 層才看得到，而且沒有分數
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000f2c01';
  b uuid := '00000000-0000-0000-0000-0000000f2c02';
  v jsonb; app_row public.applications;
begin
  raise notice '=== 揭露分層 ===';
  perform pg_temp.mkuser(a, '丙');
  perform pg_temp.mkuser(b, '丁');
  update public.match_profiles set readiness = jsonb_build_object(
    'conflict_repair', '先各自冷靜，再回來談。',
    'reciprocity', '會留意對方是不是也主動安排時間見面。')
   where id = b;

  -- 第 0 層：還沒提出邀請
  perform set_config('request.jwt.claim.sub', a::text, true);
  select (x->'readiness') into v from public.get_visible_match_profiles(b) x;
  perform pg_temp.ok(v = '{}'::jsonb, '第 0 層看到的 readiness 是空物件，不會洩漏內容', v::text);

  -- 第 1 層：通過第一階段
  app_row := public.apply_to(b, '["嗨","嗨"]'::jsonb);
  update public.applications set stage = 1 where id = app_row.id;
  select (x->'readiness') into v from public.get_visible_match_profiles(b) x;
  perform pg_temp.ok(v = '{}'::jsonb,
    '第 1 層還是看不到（跟宗教／感情史同一層，比學歷晚一層開放）', v::text);

  -- 第 2 層：進入第二階段
  update public.applications set stage = 2 where id = app_row.id;
  select (x->'readiness') into v from public.get_visible_match_profiles(b) x;
  perform pg_temp.ok(v->>'conflict_repair' = '先各自冷靜，再回來談。',
    '第 2 層開始看得到原始回答文字', v::text);
  perform pg_temp.ok((select count(*) from jsonb_object_keys(v)) = 2,
    '看到的題數跟對方實際填過的一樣', v::text);

  -- 沒有分數：每一個值都是字串，不是數字
  perform pg_temp.ok(not exists (
    select 1 from jsonb_each(v) e where jsonb_typeof(e.value) <> 'string'),
    '每一題的內容都是原始文字（string），不會被算成數字或燈號', v::text);
  perform pg_temp.ok(not (v::text ~ '\d+\s*/\s*100' or v::text ~ '分$'),
    '回傳的內容裡沒有「幾分之幾」或「幾分」這種評分格式', v::text);

  raise notice '=== 關係能力評估測試結束 ===';
end $$;
