-- 對話室安全提醒（三級）與 Consent Mode
--
-- 這一份最重要的不是「有沒有抓到」，而是**有沒有抓錯**。
-- 「我不喜歡別人問我會不會口交」跟「妳會口交嗎」含同一個詞。
-- 把前者也亮燈，會讓人不敢談論自己的界線——剛好害到最需要保護的那個人。
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

-- 判等級的簡寫
create or replace function pg_temp.lv(p_body text, p_consent boolean default false,
                                      p_refused boolean default false)
returns text language sql stable as $$
  select coalesce(public.chat_safety_level(p_body, p_consent, p_refused)->>'level', '－');
$$;

-- ════════════════════════════════════════════════════════════
-- 一、不能只做關鍵字比對
-- ════════════════════════════════════════════════════════════
do $$
begin
  raise notice '=== 誤判防線 ===';

  /* 這是整份測試的核心案例 */
  perform pg_temp.ok(pg_temp.lv('我不喜歡別人問我會不會口交') = '－',
    '「我不喜歡別人問我會不會口交」不亮燈（在講自己的界線，不是在要求）',
    pg_temp.lv('我不喜歡別人問我會不會口交'));

  perform pg_temp.ok(pg_temp.lv('之前有人問我這種問題，我覺得很不舒服') = '－',
    '引述別人說過的話不亮燈', pg_temp.lv('之前有人問我這種問題，我覺得很不舒服'));

  perform pg_temp.ok(pg_temp.lv('我不想談身材這種話題') = '－',
    '表達自己不想談某個話題不亮燈', pg_temp.lv('我不想談身材這種話題'));

  -- 一般對話當然不亮
  perform pg_temp.ok(pg_temp.lv('你今天過得好嗎') = '－',
    '「你今天過得好嗎」是提問，但沒有任何性或身體內容 → 不亮燈',
    pg_temp.lv('你今天過得好嗎'));
  perform pg_temp.ok(pg_temp.lv('等你考完試，我們去吃那間拉麵') = '－',
    '一般的約定不亮燈', pg_temp.lv('等你考完試，我們去吃那間拉麵'));

  -- 光有詞、沒有對對方提出要求，也不亮
  perform pg_temp.ok(pg_temp.lv('這部電影裡有一段裸體的畫面') = '－',
    '談到性相關的詞但不是在對對方要求 → 不亮燈',
    pg_temp.lv('這部電影裡有一段裸體的畫面'));

  raise notice '=== 誤判防線結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、三個等級
-- ════════════════════════════════════════════════════════════
do $$
declare j jsonb;
begin
  raise notice '--- 🟡 界線提醒 ---';
  perform pg_temp.ok(pg_temp.lv('可以看看妳身材嗎') = 'boundary',
    '「可以看看妳身材嗎」→ 🟡 界線提醒', pg_temp.lv('可以看看妳身材嗎'));
  perform pg_temp.ok(pg_temp.lv('你體重多少啊') = 'boundary',
    '私密的身體話題加上提問 → 🟡', pg_temp.lv('你體重多少啊'));

  raise notice '--- 🟠 性話題警示 ---';
  perform pg_temp.ok(pg_temp.lv('妳會口交嗎') = 'sexual',
    '「妳會口交嗎」→ 🟠（露骨性內容＋對對方提問）', pg_temp.lv('妳會口交嗎'));
  perform pg_temp.ok(pg_temp.lv('傳裸照給我') = 'sexual',
    '要求提供私密影像 → 🟠', pg_temp.lv('傳裸照給我'));
  perform pg_temp.ok(pg_temp.lv('我想看妳的胸部') = 'sexual',
    '直接索求 → 🟠', pg_temp.lv('我想看妳的胸部'));

  raise notice '--- 🔴 安全紅燈 ---';
  perform pg_temp.ok(pg_temp.lv('不給我看我就把妳的裸照傳出去') = 'danger',
    '威脅散布私密影像 → 🔴', pg_temp.lv('不給我看我就把妳的裸照傳出去'));
  perform pg_temp.ok(pg_temp.lv('妳一定要傳裸照給我，不然就分手') = 'danger',
    '強迫加上私密影像 → 🔴', pg_temp.lv('妳一定要傳裸照給我，不然就分手'));
  perform pg_temp.ok(pg_temp.lv('不聽話我就讓妳好看') = 'danger',
    '人身威脅加條件 → 🔴', pg_temp.lv('不聽話我就讓妳好看'));

  /* 對方已經說過不要，再問一次就不是同一件事了 */
  perform pg_temp.ok(pg_temp.lv('妳會口交嗎', false, false) = 'sexual',
    '第一次問 → 🟠');
  perform pg_temp.ok(pg_temp.lv('妳會口交嗎', false, true) = 'danger',
    '對方說過不要之後又問一次 → 🔴（同一句話，性質不同了）',
    pg_temp.lv('妳會口交嗎', false, true));

  -- 等級要帶得出代碼，前端才知道要顯示哪一段文案
  j := public.chat_safety_level('不給我看我就把妳的裸照傳出去');
  perform pg_temp.ok(j->>'code' is not null, '🔴 有帶理由代碼', j::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、Consent Mode
-- ════════════════════════════════════════════════════════════
do $$
begin
  raise notice '--- Consent Mode ---';

  perform pg_temp.ok(pg_temp.lv('妳會口交嗎', false) = 'sexual', '沒開同意時 → 🟠');
  perform pg_temp.ok(pg_temp.lv('妳會口交嗎', true) = '－',
    '雙方同意談私密話題後，🟠 不再打斷對話', pg_temp.lv('妳會口交嗎', true));
  perform pg_temp.ok(pg_temp.lv('可以看看妳身材嗎', true) = '－',
    '🟡 也一樣不再打斷', pg_temp.lv('可以看看妳身材嗎', true));

  /* 這幾條是 Consent Mode 的底線：同意談性話題，
     從來不等於同意被威脅、被強迫、或在說了不要之後還被繼續。 */
  perform pg_temp.ok(pg_temp.lv('不給我看我就把妳的裸照傳出去', true) = 'danger',
    '就算開了同意，威脅仍然是 🔴', pg_temp.lv('不給我看我就把妳的裸照傳出去', true));
  perform pg_temp.ok(pg_temp.lv('妳一定要傳裸照給我，不然就分手', true) = 'danger',
    '就算開了同意，強迫仍然是 🔴', pg_temp.lv('妳一定要傳裸照給我，不然就分手', true));
  perform pg_temp.ok(pg_temp.lv('妳會口交嗎', true, true) = 'danger',
    '就算開了同意，對方說不要之後繼續仍然是 🔴',
    pg_temp.lv('妳會口交嗎', true, true));
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、走真的送訊息流程
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000c001';
  b uuid := '00000000-0000-0000-0000-00000000c002';
  app uuid; m public.match_messages; st jsonb; n int;
begin
  raise notice '--- 送訊息時就地判定 ---';
  insert into auth.users(id, email) values (a,'ca@t.local'),(b,'cb@t.local') on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'甲','pet','cat',true,'active'),(b,'乙','keeper','dog',true,'active')
    on conflict (id) do update set account_status='active', posting_locked=false;

  insert into public.applications(from_user,to_user,stage,status)
    values (b,a,2,'open') returning id into app;

  perform set_config('request.jwt.claim.sub', b::text, true);

  m := public.send_match_message(app, '你今天過得好嗎');
  perform pg_temp.ok(m.safety_level is null, '一般訊息沒有安全標記', coalesce(m.safety_level,'null'));

  m := public.send_match_message(app, '可以看看妳身材嗎');
  perform pg_temp.ok(m.safety_level = 'boundary', '🟡 有存在訊息上', coalesce(m.safety_level,'null'));

  m := public.send_match_message(app, '妳會口交嗎');
  perform pg_temp.ok(m.safety_level = 'sexual', '🟠 有存在訊息上', coalesce(m.safety_level,'null'));

  /* 訊息不會被擋下來。擋掉的話送出的人只會改幾個字再送一次，
     而收到的人反而失去「這個人剛剛說了什麼」的證據。 */
  perform pg_temp.ok(m.id is not null,
    '被標記的訊息仍然送得出去（不擋，是標記並把選項交給收到的人）');

  -- 對方表達拒絕之後，同一句話升成 🔴
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.send_match_message(app, '我不想談這個，請停下');
  perform set_config('request.jwt.claim.sub', b::text, true);
  m := public.send_match_message(app, '妳會口交嗎');
  perform pg_temp.ok(m.safety_level = 'danger',
    '對方說了「請停下」之後再送一次 → 🔴', coalesce(m.safety_level,'null'));

  -- Consent Mode 要兩個人都按
  raise notice '--- 同意要兩個人都按 ---';
  st := public.set_chat_consent(app, true);
  perform pg_temp.ok((st->>'mine')::boolean and not (st->>'both')::boolean,
    '只有自己按下時，還不算雙方同意', st::text);
  perform pg_temp.ok(not public.chat_consent_on(app),
    '單方面宣告的同意不是同意');

  perform set_config('request.jwt.claim.sub', a::text, true);
  st := public.set_chat_consent(app, true);
  perform pg_temp.ok((st->>'both')::boolean, '兩邊都按下才成立', st::text);
  perform pg_temp.ok(public.chat_consent_on(app), 'chat_consent_on 也看得到');

  -- 撤回
  st := public.set_chat_consent(app, false);
  perform pg_temp.ok(not (st->>'both')::boolean, '任一方都可以隨時撤回', st::text);
  perform pg_temp.ok(not public.chat_consent_on(app), '撤回之後警示就回來了');

  -- 不能替對方按下同意（RPC 只動 auth.uid() 自己那一列）
  select count(*) into n from public.chat_consent
   where application_id = app and user_id = b;
  perform pg_temp.ok(n = 1,
    '撤回自己的同意不會動到對方那一列（替對方按同意是最不能允許的事）', n::text);

  -- 局外人碰不到
  raise notice '--- 局外人 ---';
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c009', true);
  begin
    perform public.set_chat_consent(app, true);
    perform pg_temp.ok(false, '不在這段對話裡的人不能按同意');
  exception when others then
    perform pg_temp.ok(true, '不在這段對話裡的人不能按同意');
  end;
  begin
    perform public.chat_consent_state(app);
    perform pg_temp.ok(false, '不在這段對話裡的人讀不到同意狀態');
  exception when others then
    perform pg_temp.ok(true, '不在這段對話裡的人讀不到同意狀態');
  end;

  raise notice '=== 對話室安全測試結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 五、規則是資料，而且管理端看得到 🔴
-- ════════════════════════════════════════════════════════════
do $$
declare boss uuid := '00000000-0000-0000-0000-00000000c0a1'; q jsonb; n int;
begin
  raise notice '--- 規則庫與管理端 ---';
  select count(*) into n from public.chat_safety_signals where enabled;
  perform pg_temp.ok(n >= 10, '訊號規則是資料，不是寫死在函式裡', n::text);

  -- 反向訊號一定要存在，不然誤判防線就沒了
  select count(*) into n from public.chat_safety_signals where class = 'selfref' and enabled;
  perform pg_temp.ok(n >= 2,
    '有「在講自己的界線／在引述」的反向訊號（少了它就退化成關鍵字封鎖）', n::text);

  insert into auth.users(id,email) values (boss,'cboss@t.local') on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,is_admin)
    values (boss,'管理員','keeper','dog',true,true)
    on conflict (id) do update set is_admin = true;
  perform set_config('request.jwt.claim.sub', boss::text, true);
  q := public.admin_chat_danger_counts();
  perform pg_temp.ok(jsonb_array_length(q) >= 1, '管理端看得到有 🔴 的對話', q::text);
  perform pg_temp.ok(not (q::text ~ '口交'),
    '但列表上不外流訊息內容（內容要在檢舉稽核流程裡看，不是隨手翻）');

  -- 一般會員叫不動
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c002', true);
  begin
    perform public.admin_chat_danger_counts();
    perform pg_temp.ok(false, '非管理員叫不動安全佇列');
  exception when others then
    perform pg_temp.ok(true, '非管理員叫不動安全佇列');
  end;
end $$;
