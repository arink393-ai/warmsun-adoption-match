-- 💛 他們的故事：公開的成功故事
--
-- 這一份守的是三道關，而且每一道都可能被單獨繞過去：
--   ① 伺服器端擋聯絡方式——這一頁**訪客也看得到**，是全站最外層的一個自由輸入欄位
--   ② 兩個人都同意才送得出去——而且**改了字，同意要作廢**，
--      不然第 ② 道關可以被一次編輯整個繞過去
--   ③ 人工審核通過才公開——而且審核**不能替當事人補上同意**
--
-- 以及一條不靠排程的規則：關係結束或收回相互承認，故事立刻下架。
\set ON_ERROR_STOP on
\pset pager off
\t on

create or replace function pg_temp.ok(p_cond boolean, p_label text, p_actual text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice '✅ %', p_label;
  else raise notice '❌ %', p_label || coalesce('（實際：' || p_actual || '）', ''); end if;
end $$;

-- 建一段已經互相承認彼此是伴侶的關係
create or replace function pg_temp.mkpartners(a uuid, b uuid) returns uuid
language plpgsql as $$
declare app uuid; st jsonb; lk uuid;
begin
  insert into auth.users(id,email) values (a, a::text || '@t.local'), (b, b::text || '@t.local')
    on conflict do nothing;
  /* on conflict 這裡一定要把 name 也寫進去：
     建 auth.users 時 handle_new_match_user() 已經先塞了一列空白的 profile，
     只 do update set account_status 的話暱稱會是空字串，
     然後「同意具名卻沒有名字」看起來就像產品壞了。 */
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'小綠','pet','cat',true,'active'), (b,'小橘','keeper','dog',true,'active')
    on conflict (id) do update set name = excluded.name,
      account_status='active', posting_locked=false;
  insert into public.applications(from_user,to_user,stage,status,unlock_from,unlock_to)
    values (b,a,3,'open',true,true) returning id into app;
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_agree(app, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.set_companion_agree(app, true);
  lk := (st->>'link_id')::uuid;
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_partner(lk, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_companion_partner(lk, true);
  return lk;
end $$;

create or replace function pg_temp.story() returns text language sql as $$
  select '我們是在第二階段的對話裡開始認真的。一開始只是問對方週末都在做什麼，'
      || '後來變成每天都想講一句話。走到現在兩年了，還是會為了誰洗碗吵架。'
$$;

-- ════════════════════════════════════════════════════════════
-- 一、誰可以寫
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e5a01';
  b uuid := '00000000-0000-0000-0000-0000000e5a02';
  x uuid := '00000000-0000-0000-0000-0000000e5a09';
  lk uuid; app uuid; st jsonb; s jsonb;
begin
  raise notice '=== 誰可以寫 ===';
  -- 先做一段只有陪伴紀錄、沒有互相承認的關係
  insert into auth.users(id,email) values (a,'sa@t.local'),(b,'sb@t.local'),(x,'sx@t.local')
    on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'小綠','pet','cat',true,'active'),(b,'小橘','keeper','dog',true,'active'),
           (x,'路人','pet','cat',true,'active')
    on conflict (id) do update set account_status='active';
  insert into public.applications(from_user,to_user,stage,status,unlock_from,unlock_to)
    values (b,a,3,'open',true,true) returning id into app;
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_agree(app, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.set_companion_agree(app, true);
  lk := (st->>'link_id')::uuid;

  perform set_config('request.jwt.claim.sub', a::text, true);
  s := public.story_state(lk);
  perform pg_temp.ok(not (s->>'eligible')::boolean,
    '只有陪伴紀錄、還沒互相承認 → 還不能寫故事', s::text);
  begin
    perform public.save_story(lk, '我們的故事', pg_temp.story());
    perform pg_temp.ok(false, '沒有互相承認就寫不了');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%互相承認%',
      '沒有互相承認就寫不了，而且說得出條件', sqlerrm);
  end;

  -- 互相承認之後才可以
  perform public.set_companion_partner(lk, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_companion_partner(lk, true);
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform pg_temp.ok((public.story_state(lk)->>'eligible')::boolean, '互相承認之後就可以寫');

  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.save_story(lk, '我來亂寫', pg_temp.story());
    perform pg_temp.ok(false, '局外人寫不進去');
  exception when others then perform pg_temp.ok(true, '局外人寫不進去'); end;
  begin
    perform public.story_state(lk);
    perform pg_temp.ok(false, '局外人讀不到草稿狀態');
  exception when others then perform pg_temp.ok(true, '局外人讀不到草稿狀態'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、① 聯絡方式與長度
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e5b01';
  b uuid := '00000000-0000-0000-0000-0000000e5b02';
  lk uuid;
begin
  raise notice '=== 聯絡方式 ===';
  lk := pg_temp.mkpartners(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);

  /* 這一頁訪客也看得到。一則故事如果可以寫「有興趣的人加我 LINE」，
     整套四層漸進式揭露就被繞過去了，而且是使用者自己繞的。 */
  begin
    perform public.save_story(lk, '我們的故事',
      pg_temp.story() || ' 想聊聊的人可以加我 LINE ID: greenone');
    perform pg_temp.ok(false, '內文裡的聯絡方式被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%聯絡方式%' and sqlerrm like '%訪客也看得到%',
      '內文裡的聯絡方式被擋下來，而且說得出為什麼這裡特別嚴', sqlerrm);
  end;
  begin
    perform public.save_story(lk, '找我 IG @greenone', pg_temp.story());
    perform pg_temp.ok(false, '標題裡的聯絡方式也被擋');
  exception when others then perform pg_temp.ok(true, '標題裡的聯絡方式也被擋'); end;

  begin
    perform public.save_story(lk, '我們的故事', '太短了');
    perform pg_temp.ok(false, '太短的擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%30 個字%', '太短的擋下來，而且說得出下限', sqlerrm);
  end;
  begin
    perform public.save_story(lk, '', pg_temp.story());
    perform pg_temp.ok(false, '沒有標題不行');
  exception when others then perform pg_temp.ok(true, '沒有標題不行'); end;
  begin
    perform public.save_story(lk, '我們的故事', repeat('字', 5000));
    perform pg_temp.ok(false, '太長的擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%4000%', '太長的擋下來，而且說得出上限', sqlerrm);
  end;

  -- 正常的寫得進去
  perform pg_temp.ok((public.save_story(lk, '我們的故事', pg_temp.story())->>'exists')::boolean,
    '正常的故事寫得進去');
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、② 兩個人都同意，而且改了字同意要作廢
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e5c01';
  b uuid := '00000000-0000-0000-0000-0000000e5c02';
  lk uuid; s jsonb; sid uuid; n int;
begin
  raise notice '=== 雙方同意 ===';
  lk := pg_temp.mkpartners(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);
  s := public.save_story(lk, '我們的故事', pg_temp.story());
  perform pg_temp.ok(s->>'status' = 'draft', '剛寫好是草稿', s->>'status');

  s := public.set_story_agree(lk, true);
  perform pg_temp.ok((s->>'mine')::boolean and not (s->>'other')::boolean,
    '一個人按不算', s::text);
  perform pg_temp.ok(s->>'status' = 'draft', '單方面同意不會送審', s->>'status');

  perform set_config('request.jwt.claim.sub', b::text, true);
  s := public.set_story_agree(lk, true);
  perform pg_temp.ok(s->>'status' = 'pending', '兩個人都同意才進審核佇列', s->>'status');

  /* 這是這一節最容易漏的一條：對方同意的是「那一段文字」，
     不是「你之後想寫的任何東西」。少了它，第 ② 道關可以被一次編輯繞過去。 */
  raise notice '--- 改了字 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  s := public.save_story(lk, '我們的故事', pg_temp.story() || ' 後來我們決定一起養一隻貓。');
  perform pg_temp.ok(not (s->>'mine')::boolean and not (s->>'other')::boolean,
    '改了字之後，兩邊的同意都作廢（對方同意的是那一段文字）', s::text);
  perform pg_temp.ok(s->>'status' = 'draft', '而且退回草稿', s->>'status');

  -- 只動自己那一格
  perform public.set_story_agree(lk, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform pg_temp.ok(not (public.story_state(lk)->>'mine')::boolean,
    '甲的同意不會變成乙也同意了');
  perform public.set_story_agree(lk, true);

  -- 具名各自決定
  raise notice '--- 具名 ---';
  s := public.story_state(lk);
  perform pg_temp.ok(not (s->>'show_name')::boolean,
    '預設不具名（「這兩個帳號在一起」本身就是一則新的公開資訊）', s::text);
  s := public.set_story_name(lk, true);
  perform pg_temp.ok((s->>'show_name')::boolean, '自己可以選擇具名', s::text);
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform pg_temp.ok(not (public.story_state(lk)->>'show_name')::boolean,
    '乙具名不會把甲也一起具名', public.story_state(lk)::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、③ 人工審核，以及訪客看到什麼
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e5d01';
  b uuid := '00000000-0000-0000-0000-0000000e5d02';
  adm uuid := '00000000-0000-0000-0000-0000000e5d0a';
  lk uuid; sid uuid; s jsonb; pub jsonb; q jsonb;
begin
  raise notice '=== 人工審核 ===';
  lk := pg_temp.mkpartners(a, b);
  insert into auth.users(id,email) values (adm,'adm@t.local') on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status,is_admin)
    values (adm,'管理員','keeper','dog',true,'active',true)
    on conflict (id) do update set is_admin = true;

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.save_story(lk, '我們的故事', pg_temp.story());
  perform public.set_story_agree(lk, true);
  perform public.set_story_name(lk, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_story_agree(lk, true);
  select id into sid from public.companion_stories where link_id = lk;

  -- 審核前訪客看不到
  perform set_config('request.jwt.claim.sub', '', true);
  pub := public.list_public_stories();
  perform pg_temp.ok(pub::text not like '%我們的故事%',
    '還沒審核通過之前，訪客看不到', pub::text);

  -- 一般會員不能審
  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.admin_review_story(sid, true);
    perform pg_temp.ok(false, '一般會員不能審自己的故事');
  exception when others then perform pg_temp.ok(true, '一般會員不能審自己的故事'); end;
  begin
    perform public.admin_story_queue();
    perform pg_temp.ok(false, '一般會員看不到審核佇列');
  exception when others then perform pg_temp.ok(true, '一般會員看不到審核佇列'); end;

  perform set_config('request.jwt.claim.sub', adm::text, true);
  q := public.admin_story_queue();
  perform pg_temp.ok(q::text like '%我們的故事%', '管理員看得到待審的', q::text);
  perform public.admin_review_story(sid, true, '');

  perform set_config('request.jwt.claim.sub', '', true);
  pub := public.list_public_stories();
  perform pg_temp.ok(pub::text like '%我們的故事%', '審核通過之後訪客看得到', pub::text);
  perform pg_temp.ok(pub->0->>'name_a' = '小綠', '同意具名的那一邊顯示暱稱', pub::text);
  perform pg_temp.ok((pub->0->>'name_b') is null,
    '沒同意具名的那一邊不顯示（前端會顯示成「一位使用者」）', pub::text);

  /* 公開清單只能回公開需要的東西。link_id、author、agreed_* 流出去
     等於把「哪兩個帳號」直接接起來。 */
  perform pg_temp.ok(not (pub->0 ? 'link_id') and not (pub->0 ? 'author')
                     and not (pub->0 ? 'agreed_a'),
    '公開清單不含 link_id／author／同意狀態', pub::text);
  /* 一旦故事之間可以比較，寫故事就變成一件要表現的事。 */
  perform pg_temp.ok(pub::text !~ 'views|likes|hearts|rank|featured|熱門',
    '公開清單沒有瀏覽數、愛心、排行或精選', pub::text);

  -- 訪客直接讀表讀不到
  perform set_config('role', 'anon', true);
  begin
    perform (select count(*) from public.companion_stories);
    perform pg_temp.ok((select count(*) from public.companion_stories) = 0,
      '訪客直接 select 這張表拿不到東西（只有 RPC 那條路）');
  exception when others then
    perform pg_temp.ok(true, '訪客直接 select 這張表拿不到東西（只有 RPC 那條路）');
  end;
  perform set_config('role', 'none', true);

  raise notice '--- 撤下 ---';
  /* 撤下不需要對方同意、不用寫原因，而且立刻生效。 */
  perform set_config('request.jwt.claim.sub', b::text, true);
  s := public.set_story_agree(lk, false);
  perform pg_temp.ok(s->>'status' = 'draft', '任一方撤回同意，故事就退回草稿', s->>'status');
  perform set_config('request.jwt.claim.sub', '', true);
  pub := public.list_public_stories();
  perform pg_temp.ok(pub::text not like '%我們的故事%',
    '而且公開頁面立刻就沒有了（不用等審核、不用等對方）', pub::text);

  -- 管理員不能替當事人補上同意
  perform set_config('request.jwt.claim.sub', adm::text, true);
  begin
    perform public.admin_review_story(sid, true);
    perform pg_temp.ok(false, '沒有雙方同意時管理員不能公開它');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%沒有雙方同意%',
      '沒有雙方同意時管理員不能公開它（不然撤下的故事可以被一鍵放回去）', sqlerrm);
  end;

  -- 退件
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_story_agree(lk, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  perform public.admin_review_story(sid, false, '請把第三段裡提到的公司名稱拿掉');
  perform set_config('request.jwt.claim.sub', a::text, true);
  s := public.story_state(lk);
  perform pg_temp.ok(s->>'status' = 'rejected', '退件了', s->>'status');
  perform pg_temp.ok((s->>'admin_note') like '%公司名稱%',
    '退件理由看得到（不然使用者不知道要改什麼）', s->>'admin_note');
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.ok(public.list_public_stories()::text not like '%我們的故事%',
    '退件的不會出現在公開頁面');
end $$;

-- ════════════════════════════════════════════════════════════
-- 五、(4) 關係結束或收回相互承認 → 自動下架
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e5e01';
  b uuid := '00000000-0000-0000-0000-0000000e5e02';
  adm uuid := '00000000-0000-0000-0000-0000000e5d0a';
  lk uuid; sid uuid; pub jsonb; s jsonb;
begin
  raise notice '=== 自動下架 ===';
  lk := pg_temp.mkpartners(a, b);
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.save_story(lk, '兩年了', pg_temp.story());
  perform public.set_story_agree(lk, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_story_agree(lk, true);
  select id into sid from public.companion_stories where link_id = lk;
  perform set_config('request.jwt.claim.sub', adm::text, true);
  perform public.admin_review_story(sid, true, '');
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.ok(public.list_public_stories()::text like '%兩年了%', '先確認它真的公開了');

  /* 一則屬於已經分開的兩個人的「成功故事」留在公開頁面上，對兩邊都是傷害。
     這一條不能靠排程——排程還沒有。 */
  raise notice '--- 收回相互承認 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_partner(lk, false);
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.ok(public.list_public_stories()::text not like '%兩年了%',
    '一方收回相互承認，故事立刻下架', public.list_public_stories()::text);

  -- 放回去，再測結束
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_partner(lk, true);
  perform public.set_story_agree(lk, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.set_story_agree(lk, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  perform public.admin_review_story(sid, true, '');
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.ok(public.list_public_stories()::text like '%兩年了%', '重新審過就又公開了');

  raise notice '--- 結束關係 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.end_companion_link(lk);
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.ok(public.list_public_stories()::text not like '%兩年了%',
    '關係一結束，故事立刻下架（不靠排程）', public.list_public_stories()::text);

  -- 結束之後也不能再改
  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.save_story(lk, '兩年了', pg_temp.story());
    perform pg_temp.ok(false, '結束之後寫不了故事');
  exception when others then perform pg_temp.ok(true, '結束之後寫不了故事'); end;

  raise notice '=== 他們的故事測試結束 ===';
end $$;
