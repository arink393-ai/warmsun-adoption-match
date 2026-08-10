-- 🌱 陪伴紀錄第 6、7 步：診療室的讀取權限與診療紀錄
--
-- 規格第 3 節開頭那句：「這是最容易做錯的地方」。
-- 所以這一份的重點不是「功能會不會動」，是**沒勾的東西進不進得去 AI 的輸入**。
-- 一個 security definer 的函式如果多回傳了一個欄位，
-- 使用者不會看到、不會被通知，也永遠不會來檢舉。
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
  insert into public.match_profiles(id,name,kind,species,consent,account_status,bio,dealbreakers)
    values (a,'甲','pet','cat',true,'active','我的自介裡有一句很私人的話','{"no_smoking":true}'::jsonb),
           (b,'乙','keeper','dog',true,'active','乙的自介','{}'::jsonb)
    on conflict (id) do update set account_status='active', posting_locked=false,
      bio = excluded.bio, dealbreakers = excluded.dealbreakers;
  insert into public.applications(from_user,to_user,stage,status,unlock_from,unlock_to)
    values (b,a,3,'open',true,true) returning id into app;
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_agree(app, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.set_companion_agree(app, true);
  return (st->>'link_id')::uuid;
end $$;

-- ════════════════════════════════════════════════════════════
-- 一、預設全部關著
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e2a01';
  b uuid := '00000000-0000-0000-0000-0000000e2a02';
  lk uuid; p jsonb; ctx jsonb; cols text; k text;
begin
  raise notice '=== 預設 ===';
  lk := pg_temp.mklink(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);

  p := public.clinic_permissions(lk);
  foreach k in array array['allow_profile','allow_dealbreakers','allow_stage2',
                           'allow_checkins','allow_sessions','allow_goals','allow_joint'] loop
    perform pg_temp.ok(not (p->>k)::boolean, k || ' 預設是關的', p->>k);
  end loop;

  /* 一個叫 allow_chat_range 的欄位存在資料庫裡，遲早會有人把它當成常設開關來讀，
     而那正好違反規格「對話的授權是一次性的」。所以這個欄位不存在。 */
  select string_agg(column_name, ',') into cols from information_schema.columns
   where table_schema='public' and table_name='clinic_context_permissions';
  perform pg_temp.ok(cols not like '%allow_chat%',
    '沒有 allow_chat_range 這種常設的對話授權欄位', cols);

  -- 什麼都沒勾時，context 是空的
  ctx := public.build_clinic_context(lk, 'solo', 0);
  perform pg_temp.ok(ctx::text not like '%很私人的話%',
    '沒勾病歷卡，自介就不會出現在 AI 的輸入裡', ctx::text);
  perform pg_temp.ok(ctx::text not like '%no_smoking%',
    '沒勾不可妥協項目，它就不會出現', ctx::text);
  perform pg_temp.ok(not (ctx ? 'chat'), '對話當然也不在', ctx::text);
  perform pg_temp.ok((ctx ? 'mode') and (ctx ? 'link_id'),
    'context 只有模式與這段關係本身', ctx::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、勾了才進得去，而且一次只開一格
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e2b01';
  b uuid := '00000000-0000-0000-0000-0000000e2b02';
  lk uuid; p jsonb; ctx jsonb;
begin
  raise notice '=== 一次一格 ===';
  lk := pg_temp.mklink(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);

  p := public.set_clinic_permission(lk, 'allow_profile', true);
  perform pg_temp.ok((p->>'allow_profile')::boolean, '勾了病歷卡', p::text);
  perform pg_temp.ok(not (p->>'allow_dealbreakers')::boolean,
    '勾一格不會順手把別格也打開', p::text);

  ctx := public.build_clinic_context(lk, 'solo', 0);
  perform pg_temp.ok(ctx::text like '%很私人的話%', '勾了才讀得到自介', ctx::text);
  perform pg_temp.ok(ctx::text not like '%no_smoking%',
    '沒勾的不可妥協項目仍然不在', ctx::text);

  -- 取消勾選之後立刻不再讀
  p := public.set_clinic_permission(lk, 'allow_profile', false);
  ctx := public.build_clinic_context(lk, 'solo', 0);
  perform pg_temp.ok(ctx::text not like '%很私人的話%',
    '取消勾選之後下一次就讀不到了（不是下次登入才生效）', ctx::text);

  begin
    perform public.set_clinic_permission(lk, 'is_admin', true);
    perform pg_temp.ok(false, '不能拿這支函式去改別的欄位');
  exception when others then
    perform pg_temp.ok(true, '不能拿這支函式去改別的欄位（白名單擋在前面）');
  end;

  -- 只動自己那一列
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform pg_temp.ok(not (public.clinic_permissions(lk)->>'allow_profile')::boolean,
    '甲勾的東西不會變成乙也勾了');
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、共同關係分析要雙方同意
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e2c01';
  b uuid := '00000000-0000-0000-0000-0000000e2c02';
  lk uuid; app uuid; p jsonb; ctx jsonb;
begin
  raise notice '=== 共同分析 ===';
  lk := pg_temp.mklink(a, b);
  select id into app from public.applications
   where least(from_user,to_user) = least(a,b) and greatest(from_user,to_user) = greatest(a,b);
  insert into public.match_messages(application_id, sender_id, body)
    values (app, b, '這句話是對方在對話裡說的');

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_clinic_permission(lk, 'allow_joint', true);
  begin
    perform public.build_clinic_context(lk, 'joint', 30);
    /* 單方面把一段關係交給 AI 分析，等於替另一個人決定他要不要被分析。 */
    perform pg_temp.ok(false, '只有自己同意時開不了共同分析');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%兩個人都同意%',
      '只有自己同意時開不了共同分析，而且說得出原因', sqlerrm);
  end;

  -- solo 還是可以用
  ctx := public.build_clinic_context(lk, 'solo', 30);
  perform pg_temp.ok(ctx::text not like '%對方在對話裡說的%',
    'solo 模式不管指定幾天，對話都進不去（solo 說好了只讀使用者自己給的片段）', ctx::text);

  -- 對方也同意
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_clinic_permission(lk, 'allow_joint', true);
  perform set_config('request.jwt.claim.sub', a::text, true);
  p := public.clinic_permissions(lk);
  perform pg_temp.ok((p->>'other_allow_joint')::boolean, '看得到對方也同意了', p::text);

  ctx := public.build_clinic_context(lk, 'joint', 30);
  perform pg_temp.ok(ctx::text like '%對方在對話裡說的%',
    '兩個人都同意、而且這一次指定了天數，對話才進得去', ctx::text);
  perform pg_temp.ok((ctx->>'chat_days')::int = 30, '而且記下這一次讀了幾天', ctx->>'chat_days');

  raise notice '--- 對話的授權是一次性的 ---';
  /* 上一次勾了 30 天，這一次沒指定 → 一則對話都不能進去。
     這正是 last_chat_days 不能被當成權限的理由。 */
  ctx := public.build_clinic_context(lk, 'joint', 0);
  perform pg_temp.ok(not (ctx ? 'chat'),
    '上一次讀了 30 天，這一次沒指定就是零（授權是一次性的，不是常設開關）', ctx::text);
  perform pg_temp.ok((public.clinic_permissions(lk)->>'last_chat_days')::int = 30,
    'last_chat_days 只是拿來預填畫面，它自己不會讓對話進去');

  -- 上限
  ctx := public.build_clinic_context(lk, 'joint', 9999);
  perform pg_temp.ok((ctx->>'chat_days')::int = 90, '讀取範圍有上限，不能一次要走全部', ctx->>'chat_days');

  begin
    perform public.build_clinic_context(lk, 'everything', 0);
    perform pg_temp.ok(false, '沒有第三種模式');
  exception when others then perform pg_temp.ok(true, '沒有第三種模式'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、安全模式
-- ════════════════════════════════════════════════════════════
do $$
declare v jsonb;
begin
  raise notice '=== 安全模式 ===';
  /* 直接接第 24 節的偵測，不另外寫一套——
     不然會出現「對話室亮紅燈、診療室卻繼續勸和」。 */
  v := public.clinic_safety_mode('他打我，但我不知道是不是我先惹他生氣');
  perform pg_temp.ok((v->>'safety')::boolean,
    '「他打我」會切換成安全模式，不當成一般伴侶衝突', v::text);

  v := public.clinic_safety_mode('不聽話我就讓妳好看');
  perform pg_temp.ok((v->>'safety')::boolean, '威脅也會切換成安全模式', v::text);

  -- 一般衝突不會被誤判成安全事件
  v := public.clinic_safety_mode('我們最近常常為了誰洗碗吵架，我覺得有點累');
  perform pg_temp.ok(not (v->>'safety')::boolean,
    '一般的爭執不會被誤判成人身安全事件（誤判會讓人不敢談日常摩擦）', v::text);
  v := public.clinic_safety_mode('他上週忘記我的生日，我很難過');
  perform pg_temp.ok(not (v->>'safety')::boolean, '難過不等於危險', v::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 五、診療紀錄是本人的
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e2d01';
  b uuid := '00000000-0000-0000-0000-0000000e2d02';
  x uuid := '00000000-0000-0000-0000-0000000e2d09';
  lk uuid; s public.clinic_sessions; j jsonb; n int;
begin
  raise notice '=== 診療紀錄 ===';
  lk := pg_temp.mklink(a, b);
  insert into auth.users(id,email) values (x,'x2@t.local') on conflict do nothing;

  perform set_config('request.jwt.claim.sub', a::text, true);
  s := public.save_clinic_session(lk, '關於家事分工', '我覺得最近都是我在做',
        '{"事實":"...","感受":"...","需求":"...","下一個問題":"..."}'::jsonb);
  perform pg_temp.ok(s.id is not null, '存得下來');
  perform pg_temp.ok(s.mode = 'solo', '預設是只幫自己整理，不是共同分析', s.mode);

  j := public.list_clinic_sessions(lk);
  perform pg_temp.ok(jsonb_array_length(j) = 1, '自己看得到自己的', j::text);

  /* joint 指的是「輸出可以談到兩個人」，不是「對方可以翻我的診療紀錄」。 */
  perform set_config('request.jwt.claim.sub', b::text, true);
  j := public.list_clinic_sessions(lk);
  perform pg_temp.ok(jsonb_array_length(j) = 0,
    '對方翻不到我的診療紀錄（就算兩個人都同意共同分析也一樣）', j::text);
  select count(*) into n from public.clinic_sessions where link_id = lk and user_id = a;
  perform pg_temp.ok(n = 1, '（紀錄確實存在，只是對方讀不到）', n::text);

  begin
    perform public.delete_clinic_session(s.id);
    perform pg_temp.ok(false, '對方刪不掉我的診療紀錄');
  exception when others then perform pg_temp.ok(true, '對方刪不掉我的診療紀錄'); end;

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.delete_clinic_session(s.id);
  perform pg_temp.ok(jsonb_array_length(public.list_clinic_sessions(lk)) = 0,
    '自己刪得掉自己的');

  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.build_clinic_context(lk, 'solo', 0);
    perform pg_temp.ok(false, '局外人組不出 context');
  exception when others then perform pg_temp.ok(true, '局外人組不出 context'); end;
  begin
    perform public.clinic_permissions(lk);
    perform pg_temp.ok(false, '局外人讀不到授權狀態');
  exception when others then perform pg_temp.ok(true, '局外人讀不到授權狀態'); end;

  raise notice '=== 診療室測試結束 ===';
end $$;
