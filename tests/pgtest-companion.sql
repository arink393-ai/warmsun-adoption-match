-- 🌱 暖陽陪伴紀錄：companion_links ＋ 對話書籤（規格第 1、2 步）
--
-- 這一份守三件事，而且這三件事比「功能有沒有動」重要：
--   (1) **解鎖聯絡方式永遠不看陪伴紀錄。** 一旦某個地方寫成條件，
--       陪伴紀錄就從「值得回來的理由」變成「不做就拿不到東西的關卡」。
--   (2) **共同的東西要兩個人各自按下。** 一本關於兩個人的紀錄，
--       不該由其中一個人替兩個人決定。
--   (3) **書籤是自己的。** 收藏一句話預設只有自己看得到，
--       不通知對方，也不會變成一個公開的表態。
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
-- 一、解鎖不看陪伴紀錄（規則 1）
-- ════════════════════════════════════════════════════════════
do $$
declare f text; n int := 0;
begin
  raise notice '=== 解鎖與陪伴紀錄互不相干 ===';
  foreach f in array array['unlock_a1','unlock_stage3','consent_unlock_to','skip_to_unlock'] loop
    if (select string_agg(pg_get_functiondef(p.oid), E'\n')
          from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
         where ns.nspname = 'public' and p.proname = f) ~* 'companion' then
      n := n + 1;
      raise notice '   ↑ % 提到了 companion', f;
    end if;
  end loop;
  perform pg_temp.ok(n = 0,
    '四個解鎖函式都沒有提到 companion（陪伴紀錄不是解鎖的前置條件）', n::text);

  -- 反向也要成立：陪伴紀錄看得到解鎖狀態，但只拿來決定「能不能開始」
  perform pg_temp.ok(
    (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname='public' and p.proname='set_companion_agree') ~ 'unlock_from',
    '陪伴紀錄自己會檢查雙方是否已解鎖（方向是這一邊，不是反過來）');
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、沒有計分、沒有簽到（規則 2、3）
-- ════════════════════════════════════════════════════════════
do $$
declare cols text;
begin
  raise notice '--- 不打分數、不算連續天數 ---';
  select string_agg(column_name, ',') into cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'companion_links';
  perform pg_temp.ok(cols !~* 'score|rating|streak|points|level',
    'companion_links 沒有任何分數／連續天數／等級欄位（看到有人想加，回來讀這一行）', cols);
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、建立陪伴紀錄要兩個人都按
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000da01';
  b uuid := '00000000-0000-0000-0000-00000000da02';
  x uuid := '00000000-0000-0000-0000-00000000da09';
  app uuid; st jsonb; lk public.companion_links; t0 timestamptz; n int;
begin
  raise notice '=== 建立陪伴紀錄 ===';
  insert into auth.users(id,email) values (a,'da@t.local'),(b,'db@t.local'),(x,'dx@t.local')
    on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'甲','pet','cat',true,'active'),(b,'乙','keeper','dog',true,'active'),
           (x,'路人','pet','cat',true,'active')
    on conflict (id) do update set account_status='active', posting_locked=false;

  -- 還在第二階段
  insert into public.applications(from_user,to_user,stage,status)
    values (b,a,2,'open') returning id into app;

  perform set_config('request.jwt.claim.sub', a::text, true);
  st := public.companion_state(app);
  perform pg_temp.ok(not (st->>'eligible')::boolean,
    '第二階段還不能建立陪伴紀錄', st::text);
  perform pg_temp.ok((st->>'exists')::boolean is false and st->>'status' = 'none',
    '還沒建立時 status 是 none，不會回 null 讓前端自己猜', st::text);

  begin
    perform public.set_companion_agree(app, true);
    perform pg_temp.ok(false, '沒解鎖前按下去會被擋');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%解鎖%',
      '沒解鎖前按下去會被擋，而且說得出原因', sqlerrm);
  end;

  -- 只有一邊解鎖也不行
  update public.applications set stage = 3, unlock_from = true where id = app;
  begin
    perform public.set_companion_agree(app, true);
    perform pg_temp.ok(false, '只有一邊解鎖也不能建立');
  exception when others then perform pg_temp.ok(true, '只有一邊解鎖也不能建立'); end;

  -- 雙方都解鎖了
  update public.applications set unlock_to = true where id = app;
  st := public.companion_state(app);
  perform pg_temp.ok((st->>'eligible')::boolean,
    '第三階段＋雙方都解鎖 → 可以問要不要建立', st::text);

  raise notice '--- 一個人按不算 ---';
  st := public.set_companion_agree(app, true);
  perform pg_temp.ok((st->>'mine')::boolean and not (st->>'other')::boolean,
    '只有自己按下時，對方那格還是 false', st::text);
  perform pg_temp.ok(st->>'status' = 'pending',
    '單方面按下不會變成 active（跟 Consent Mode 同一條規則）', st->>'status');
  perform pg_temp.ok((st->>'days') is null,
    '還沒成立就沒有天數可以算', coalesce(st->>'days','null'));

  -- 對方完全沒被通知也沒被改動
  select * into lk from public.companion_links where application_id = app;
  perform pg_temp.ok(not lk.agreed_b,
    '替對方按下同意是做不到的（RPC 只動 auth.uid() 自己那一格）');

  raise notice '--- 兩個人都按才成立 ---';
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.set_companion_agree(app, true);
  perform pg_temp.ok(st->>'status' = 'active', '兩個人都按下 → active', st->>'status');
  perform pg_temp.ok((st->>'mine')::boolean and (st->>'other')::boolean,
    '兩邊都看得到對方也按了', st::text);
  perform pg_temp.ok((st->>'days')::int = 0, '成立當天是第 0 天', st->>'days');

  -- from_user / to_user 誰是 user_a 不影響任何一邊的體驗
  select * into lk from public.companion_links where application_id = app;
  perform pg_temp.ok(lk.user_a < lk.user_b,
    'user_a < user_b 恆成立（同一對人只會有一列，不會有兩本紀錄）');
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform pg_temp.ok((public.companion_state(app)->>'mine')::boolean,
    '換另一個人來看，「我按過了」也是對的（不會 a／b 對調）');

  raise notice '--- 暫停與回來 ---';
  t0 := lk.started_at;
  st := public.set_companion_agree(app, false);
  perform pg_temp.ok(st->>'status' = 'paused',
    '任一方都可以隨時撤回，關係變成暫停', st->>'status');
  perform pg_temp.ok(not (st->>'mine')::boolean and (st->>'other')::boolean,
    '撤回只動自己那一格，對方的還在', st::text);

  st := public.set_companion_agree(app, true);
  perform pg_temp.ok(st->>'status' = 'active', '回來按下去就繼續', st->>'status');
  select * into lk from public.companion_links where application_id = app;
  /* 暫停過再回來，起算日不能被洗掉。
     把「你們的陪伴紀錄從 X 開始」重算，等於把暫停講成一次失敗。 */
  perform pg_temp.ok(lk.started_at = t0,
    '暫停再回來不會重算起算日（暫停不是失敗）',
    lk.started_at::text || ' vs ' || t0::text);

  -- 同一對人只會有一列
  select count(*) into n from public.companion_links where user_a = least(a,b) and user_b = greatest(a,b);
  perform pg_temp.ok(n = 1, '按了這麼多次仍然只有一列', n::text);

  raise notice '--- 局外人 ---';
  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.set_companion_agree(app, true);
    perform pg_temp.ok(false, '不在這段關係裡的人不能建立');
  exception when others then perform pg_temp.ok(true, '不在這段關係裡的人不能建立'); end;
  begin
    perform public.companion_state(app);
    perform pg_temp.ok(false, '不在這段關係裡的人讀不到狀態');
  exception when others then perform pg_temp.ok(true, '不在這段關係裡的人讀不到狀態'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、對話書籤（🔖 記住這句）
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000db01';
  b uuid := '00000000-0000-0000-0000-00000000db02';
  x uuid := '00000000-0000-0000-0000-00000000db09';
  app uuid; app2 uuid; m1 bigint; m2 bigint; other_m bigint;
  r jsonb; l jsonb; n int; bm public.message_bookmarks;
begin
  raise notice '=== 對話書籤 ===';
  insert into auth.users(id,email) values (a,'ea@t.local'),(b,'eb@t.local'),(x,'ex@t.local')
    on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'丙','pet','cat',true,'active'),(b,'丁','keeper','dog',true,'active'),
           (x,'路人乙','pet','cat',true,'active')
    on conflict (id) do update set account_status='active', posting_locked=false;

  insert into public.applications(from_user,to_user,stage,status)
    values (b,a,3,'open') returning id into app;
  insert into public.applications(from_user,to_user,stage,status)
    values (x,a,2,'open') returning id into app2;

  insert into public.match_messages(application_id, sender_id, body)
    values (app, b, '等你考完試，我們去吃那間拉麵') returning id into m1;
  insert into public.match_messages(application_id, sender_id, body)
    values (app, a, '好啊，那就這樣說定了') returning id into m2;
  insert into public.match_messages(application_id, sender_id, body)
    values (app2, x, '在另一段對話裡') returning id into other_m;

  perform set_config('request.jwt.claim.sub', a::text, true);

  raise notice '--- 加、改、取消 ---';
  r := public.toggle_message_bookmark(m1);
  perform pg_temp.ok(r->>'state' = 'added', '按下去就收藏起來了', r::text);
  perform pg_temp.ok(r->>'kind' = 'love', '預設是 💛 喜歡的話', r::text);
  /* 預設 private 是這一節最重要的一條。
     收藏對方說過的一句話是很個人的事，不該自動變成一個對方會看到的表態。 */
  perform pg_temp.ok(r->>'visibility' = 'private',
    '預設只有自己看得到（收藏一句話不需要對方批准，也不通知對方）', r::text);

  r := public.toggle_message_bookmark(m1, 'promise');
  perform pg_temp.ok(r->>'state' = 'updated' and r->>'kind' = 'promise',
    '換一種類型是改，不是又存一筆', r::text);

  r := public.toggle_message_bookmark(m1, 'promise');
  perform pg_temp.ok(r->>'state' = 'removed',
    '同一種再按一次就是取消（一顆按鈕就夠，不必再放一個垃圾桶）', r::text);
  select count(*) into n from public.message_bookmarks where message_id = m1 and user_id = a;
  perform pg_temp.ok(n = 0, '取消之後真的不見了', n::text);

  -- 有寫字的時候，同一種再按一次是「改備註」而不是刪掉
  r := public.toggle_message_bookmark(m1, 'promise');
  r := public.toggle_message_bookmark(m1, 'promise', '這句話我想記著');
  perform pg_temp.ok(r->>'state' = 'updated' and r->>'note' = '這句話我想記著',
    '同一種但有寫備註 → 是補上備註，不是把收藏刪掉', r::text);

  raise notice '--- 一則訊息一個人只有一個書籤 ---';
  begin
    insert into public.message_bookmarks(application_id, message_id, user_id, kind)
      values (app, m1, a, 'memory');
    perform pg_temp.ok(false, '同一則訊息同一個人不能有兩個書籤');
  exception when unique_violation then
    perform pg_temp.ok(true, '同一則訊息同一個人不能有兩個書籤（資料庫層擋住）');
  end;

  -- 兩個人各自收藏同一句話是可以的，而且互不影響
  perform set_config('request.jwt.claim.sub', b::text, true);
  r := public.toggle_message_bookmark(m1, 'memory');
  perform pg_temp.ok(r->>'state' = 'added',
    '同一句話兩個人可以各自收藏（各自留各自的）', r::text);

  raise notice '--- 看不到對方的私人書籤 ---';
  l := public.list_message_bookmarks(app);
  perform pg_temp.ok(jsonb_array_length(l) = 1,
    '乙只看得到自己那一個，看不到甲設成私人的那個', l::text);
  perform pg_temp.ok((l->0->>'mine')::boolean, '自己的書籤標成 mine', l::text);

  -- 甲把它改成共同
  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.toggle_message_bookmark(m1, 'promise', '這句話我想記著', 'both');
  perform pg_temp.ok(r->>'visibility' = 'both', '想分享的話可以自己改成共同', r::text);

  perform set_config('request.jwt.claim.sub', b::text, true);
  l := public.list_message_bookmarks(app);
  perform pg_temp.ok(jsonb_array_length(l) = 2, '改成共同之後對方才看得到', l::text);
  perform pg_temp.ok(
    (select count(*) from jsonb_array_elements(l) e where not (e->>'mine')::boolean) = 1,
    '對方的書籤標成不是 mine（介面上要分得出來是誰留的）', l::text);

  raise notice '--- 不合法的輸入 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.toggle_message_bookmark(m2, 'sparkle');
    perform pg_temp.ok(false, '沒有這種書籤類型');
  exception when others then perform pg_temp.ok(true, '沒有這種書籤類型（四種以外叫不動）'); end;
  begin
    perform public.toggle_message_bookmark(m2, 'love', '', 'public');
    perform pg_temp.ok(false, '只有私人與共同兩種可見範圍');
  exception when others then
    perform pg_temp.ok(true, '只有私人與共同兩種可見範圍（沒有「全站公開」這個選項）');
  end;

  -- 備註太長要截斷而不是炸掉（使用者已經打完了，這裡沒有理由整筆丟掉）
  perform public.toggle_message_bookmark(m2, 'memory', repeat('字', 900));
  select * into bm from public.message_bookmarks where message_id = m2 and user_id = a;
  perform pg_temp.ok(char_length(bm.note) = 500,
    '太長的備註截到 500 字（不是整筆丟掉）', char_length(bm.note)::text);

  raise notice '--- 局外人 ---';
  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.toggle_message_bookmark(m1);
    perform pg_temp.ok(false, '不在這段對話裡的人不能收藏');
  exception when others then perform pg_temp.ok(true, '不在這段對話裡的人不能收藏'); end;
  begin
    perform public.list_message_bookmarks(app);
    perform pg_temp.ok(false, '不在這段對話裡的人讀不到書籤清單');
  exception when others then perform pg_temp.ok(true, '不在這段對話裡的人讀不到書籤清單'); end;

  -- 別段對話的書籤不會混進來
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.toggle_message_bookmark(other_m, 'love');
  l := public.list_message_bookmarks(app);
  perform pg_temp.ok(
    (select count(*) from jsonb_array_elements(l) e where (e->>'message_id')::bigint = other_m) = 0,
    '別段對話的書籤不會混進這一段', l::text);

  begin
    perform public.toggle_message_bookmark(-1);
    perform pg_temp.ok(false, '不存在的訊息叫不動');
  exception when others then perform pg_temp.ok(true, '不存在的訊息叫不動'); end;

  raise notice '--- 訊息刪掉時 ---';
  select count(*) into n from public.message_bookmarks where message_id = m2;
  delete from public.match_messages where id = m2;
  select count(*) into n from public.message_bookmarks where message_id = m2;
  perform pg_temp.ok(n = 0, '訊息被刪掉時書籤跟著走（不留孤兒指向不存在的話）', n::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 五、RLS：不透過 RPC 直接讀表也一樣
-- ════════════════════════════════════════════════════════════
--   上面走的都是 security definer 的 RPC。萬一哪天前端改成直接 select，
--   這一段確認資料庫本身也擋得住。
do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000db01';
  b uuid := '00000000-0000-0000-0000-00000000db02';
  x uuid := '00000000-0000-0000-0000-00000000db09';
  n int;
begin
  raise notice '=== 直接讀表（RLS）===';
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform set_config('role', 'authenticated', true);

  select count(*) into n from public.message_bookmarks where visibility = 'private' and user_id <> b;
  perform pg_temp.ok(n = 0, '直接 select 也看不到對方的私人書籤', n::text);
  select count(*) into n from public.message_bookmarks where user_id = b;
  perform pg_temp.ok(n >= 1, '自己的當然讀得到', n::text);
  select count(*) into n from public.message_bookmarks where visibility = 'both' and user_id <> b;
  perform pg_temp.ok(n = 1, '對方設成共同的讀得到', n::text);

  perform set_config('request.jwt.claim.sub', x::text, true);
  select count(*) into n from public.message_bookmarks
   where user_id in (a, b);
  perform pg_temp.ok(n = 0, '完全無關的人一個都讀不到（連共同的也不行）', n::text);

  -- companion_links 只有當事人讀得到
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000da09', true);
  select count(*) into n from public.companion_links;
  perform pg_temp.ok(n = 0, '局外人讀不到任何一段陪伴紀錄', n::text);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000da01', true);
  select count(*) into n from public.companion_links;
  perform pg_temp.ok(n = 1, '當事人讀得到自己那一段', n::text);

  perform set_config('role', 'none', true);
  raise notice '=== 陪伴紀錄測試結束 ===';
end $$;
