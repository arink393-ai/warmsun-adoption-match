-- 📷 對話相簿（7 天過期）與 📬 待審通知
--
-- 相簿這一份守的是一件事：**過期要真的過期。**
-- 「畫面上看不到」不算過期——知道路徑的人還拿得到，那就等於沒有過期。
-- 所以 Storage 的讀取政策裡也要有 expires_at 這個條件，這一份會去讀那條政策。
--
-- 通知那一份守的是：**通知失敗不能讓使用者那一次操作失敗。**
-- 送不出檢舉比收不到通知嚴重得多。
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
-- 一、過期要真的過期
-- ════════════════════════════════════════════════════════════
do $$
declare def text; cols text;
begin
  raise notice '=== 過期的定義 ===';
  select pg_get_expr(d.adbin, d.adrelid) into def
    from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
   where d.adrelid = 'public.chat_photos'::regclass and a.attname = 'expires_at';
  perform pg_temp.ok(def like '%7 days%' or def like '%7 day%',
    '預設 7 天後過期', def);

  /* 這是整份測試最重要的一條。
     Storage 的讀取政策如果只檢查「是不是當事人」，
     過期的照片只是在畫面上不見了，知道路徑的人還是拿得到。 */
  select qual::text into def from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname = 'chat_photos_participant_read';
  perform pg_temp.ok(def like '%expires_at%',
    'Storage 的讀取政策本身就會擋過期的（不只是畫面上看不到）', def);
  perform pg_temp.ok(def like '%chat_photos%' and def like '%applications%',
    '而且一樣要求是這段對話的當事人', def);

  select qual::text into def from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname = 'chat_photos_sender_write';
  perform pg_temp.ok(def is not null, '上傳有自己的政策');
  select with_check::text into def from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname = 'chat_photos_sender_write';
  perform pg_temp.ok(def like '%applications%',
    '只能傳進自己有份的那段對話的資料夾', def);

  select string_agg(column_name, ',') into cols from information_schema.columns
   where table_schema='public' and table_name='chat_photos';
  perform pg_temp.ok(cols not like '%public%',
    'chat_photos 沒有任何「公開」欄位（這個 bucket 是私密的）', cols);
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、傳、看、過期、收回
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e6a01';
  b uuid := '00000000-0000-0000-0000-0000000e6a02';
  x uuid := '00000000-0000-0000-0000-0000000e6a09';
  app uuid; app2 uuid; r jsonb; j jsonb; pid uuid; i int;
begin
  raise notice '=== 相簿 ===';
  insert into auth.users(id,email) values (a,'pa@t.local'),(b,'pb@t.local'),(x,'px@t.local')
    on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'甲','pet','cat',true,'active'),(b,'乙','keeper','dog',true,'active'),
           (x,'路人','pet','cat',true,'active')
    on conflict (id) do update set name = excluded.name, account_status='active';
  insert into public.applications(from_user,to_user,stage,status)
    values (b,a,2,'open') returning id into app;
  insert into public.applications(from_user,to_user,stage,status)
    values (x,a,2,'open') returning id into app2;

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.add_chat_photo(app, app::text || '/p1.jpg', '那天的天空');
  perform pg_temp.ok(r->>'id' is not null, '傳得上去');

  j := public.list_chat_photos(app);
  perform pg_temp.ok(jsonb_array_length(j->'photos') = 1, '相簿裡看得到', j::text);
  perform pg_temp.ok((j->'photos'->0->>'days_left')::int = 7, '剩 7 天', j->'photos'->0->>'days_left');
  perform pg_temp.ok((j->'photos'->0->>'mine')::boolean, '標得出是自己傳的');

  -- 路徑一定要在這段對話的資料夾底下
  begin
    perform public.add_chat_photo(app, app2::text || '/sneaky.jpg');
    perform pg_temp.ok(false, '路徑不在這段對話底下會被擋');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%路徑%',
      '路徑不在這段對話底下會被擋（不然 Storage 的政策就形同虛設）', sqlerrm);
  end;

  -- 說明欄一樣不能放聯絡方式
  begin
    perform public.add_chat_photo(app, app::text || '/p2.jpg', '加我 LINE ID: abcd');
    perform pg_temp.ok(false, '照片說明裡的聯絡方式被擋');
  exception when others then perform pg_temp.ok(true, '照片說明裡的聯絡方式被擋'); end;

  -- 對方看得到
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform pg_temp.ok(jsonb_array_length(public.list_chat_photos(app)->'photos') = 1,
    '對方也看得到');
  begin
    perform public.expire_chat_photo(
      (select id from public.chat_photos where application_id = app limit 1));
    perform pg_temp.ok(false, '對方不能收回別人傳的照片');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%傳出去的人%', '只有傳出去的人可以收回', sqlerrm);
  end;

  -- 局外人
  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.list_chat_photos(app);
    perform pg_temp.ok(false, '局外人看不到相簿');
  exception when others then perform pg_temp.ok(true, '局外人看不到相簿'); end;
  begin
    perform public.add_chat_photo(app, app::text || '/x.jpg');
    perform pg_temp.ok(false, '局外人傳不進去');
  exception when others then perform pg_temp.ok(true, '局外人傳不進去'); end;

  raise notice '--- 過期 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  select id into pid from public.chat_photos where application_id = app limit 1;
  update public.chat_photos set expires_at = now() - interval '1 hour' where id = pid;
  j := public.list_chat_photos(app);
  perform pg_temp.ok(jsonb_array_length(j->'photos') = 0, '過期的不會出現在相簿裡', j::text);
  perform pg_temp.ok(j->'expired_mine' @> to_jsonb(app::text || '/p1.jpg'),
    '會告訴前端哪幾個是自己傳的、已經過期的（讓它順手去 Storage 刪掉）',
    j->>'expired_mine');

  -- 對方那一邊不會被叫去刪別人的檔案
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform pg_temp.ok(public.list_chat_photos(app)->'expired_mine' = '[]'::jsonb,
    '只列自己傳的（別人的檔案自己沒有權限刪，也不該有）');

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform pg_temp.ok(public.mark_chat_photos_purged(array[app::text || '/p1.jpg']) = 1,
    '刪完回報之後就不會再列一次');
  perform pg_temp.ok(public.list_chat_photos(app)->'expired_mine' = '[]'::jsonb,
    '（確認真的不會再列）');

  raise notice '--- 收回 ---';
  r := public.add_chat_photo(app, app::text || '/p3.jpg');
  perform public.expire_chat_photo((r->>'id')::uuid);
  perform pg_temp.ok(jsonb_array_length(public.list_chat_photos(app)->'photos') = 0,
    '自己傳的可以提早收回，而且立刻生效');

  raise notice '--- 上限 ---';
  for i in 1..30 loop
    perform public.add_chat_photo(app, app::text || '/bulk' || i || '.jpg');
  end loop;
  begin
    perform public.add_chat_photo(app, app::text || '/bulk31.jpg');
    perform pg_temp.ok(false, '超過 30 張會被擋');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%30%', '超過 30 張會被擋（不要被當成免費圖床）', sqlerrm);
  end;

  -- 申請被退回之後不能再傳（applications.status 只有 open / rejected）
  update public.applications set status = 'rejected' where id = app;
  begin
    perform public.add_chat_photo(app, app::text || '/after.jpg');
    perform pg_temp.ok(false, '申請被退回之後傳不了');
  exception when others then perform pg_temp.ok(true, '申請被退回之後傳不了'); end;
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、待審通知的 outbox
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e7a01';
  c uuid := '00000000-0000-0000-0000-0000000e7a02';
  adm uuid := '00000000-0000-0000-0000-0000000e7a0a';
  n int; h jsonb; kinds text;
begin
  raise notice '=== 待審通知 ===';
  insert into auth.users(id,email) values (a,'na@t.local'),(c,'nc@t.local'),(adm,'nadm@t.local')
    on conflict do nothing;
  insert into public.match_profiles(id,name,kind,species,consent,account_status,is_admin)
    values (a,'甲','pet','cat',true,'active',false),
           (c,'丙','pet','cat',true,'active',false),
           (adm,'管理員','keeper','dog',true,'active',true)
    on conflict (id) do update set name = excluded.name, is_admin = excluded.is_admin,
      account_status='active';

  delete from public.owner_notifications;

  -- 檢舉
  perform set_config('request.jwt.claim.sub', a::text, true);
  insert into public.reports(target_id, by_id, why) values (adm, a, '這個人一直傳奇怪的訊息');
  select count(*) into n from public.owner_notifications where kind = 'report';
  perform pg_temp.ok(n = 1, '送出檢舉會記一筆通知', n::text);
  perform pg_temp.ok(
    (select subject from public.owner_notifications where kind='report') like '%檢舉%',
    '主旨看得出是什麼事');
  perform pg_temp.ok(
    (select body from public.owner_notifications where kind='report') like '%3 個工作日%',
    '而且把時效寫進信裡（那是對使用者承諾過的）');

  -- 意見回饋
  perform public.submit_feedback('bug', '第 3 步的照片上傳按了沒反應', '/index.html', '');
  select count(*) into n from public.owner_notifications where kind = 'feedback';
  perform pg_temp.ok(n = 1, '意見回饋也會記一筆', n::text);

  -- 照片與身分驗證：只在送出審核那一刻
  update public.match_profiles set photo_status = 'pending' where id = a;
  update public.match_profiles set photo_status = 'pending' where id = a;  -- 再存一次
  select count(*) into n from public.owner_notifications where kind = 'photo_review';
  /* 改成 pending 那一次才記。每存一次檔就寄一封信，站方會直接把通知關掉。 */
  perform pg_temp.ok(n = 1, '重複存成同一個狀態不會再記一筆', n::text);
  update public.match_profiles set verify_status = 'pending' where id = a;
  perform pg_temp.ok(
    (select count(*) from public.owner_notifications where kind = 'verify_review') = 1,
    '身分驗證也會記一筆');

  raise notice '--- 通知壞掉不能拖累使用者 ---';
  /* 這是整段最重要的一條：送不出檢舉比收不到通知嚴重得多。 */
  /* 用一個一定會炸的 trigger 來模擬「outbox 壞掉」。
     （第一版是把 check 改成不可能的值，但既有的資料列會讓 alter 本身就失敗，
       那是在測我的測試，不是在測產品。） */
  create or replace function pg_temp.boom() returns trigger language plpgsql as $f$
  begin raise exception '假裝 outbox 壞掉'; end $f$;
  create trigger trg_boom before insert on public.owner_notifications
    for each row execute function pg_temp.boom();
  begin
    -- 換一個對象：reports 有 one_open_per_pair 的唯一鍵，
    -- 對同一個人送第二件會因為別的原因失敗，那就測不到想測的東西
    insert into public.reports(target_id, by_id, why) values (c, a, '通知壞掉時送出的檢舉');
    perform pg_temp.ok(true, 'outbox 寫不進去時，檢舉照樣送得出去');
  exception when others then
    perform pg_temp.ok(false, 'outbox 寫不進去時，檢舉照樣送得出去', sqlerrm);
  end;
  perform pg_temp.ok(
    (select count(*) from public.reports where why = '通知壞掉時送出的檢舉') = 1,
    '而且那件檢舉真的存進去了');
  drop trigger if exists trg_boom on public.owner_notifications;

  raise notice '--- 狀態揭穿自己 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.owner_notification_health();
    perform pg_temp.ok(false, '一般會員看不到通知狀態');
  exception when others then perform pg_temp.ok(true, '一般會員看不到通知狀態'); end;

  perform set_config('request.jwt.claim.sub', adm::text, true);
  h := public.owner_notification_health();
  perform pg_temp.ok((h->>'pending')::int >= 4, '算得出還有幾筆沒寄出', h->>'pending');
  /* 這個旗標的用途是**揭穿自己**：從來沒寄出過而且已經在累積，
     幾乎可以確定是沒設定，而不是「剛好都寄完了」。 */
  perform pg_temp.ok((h->>'looks_unconfigured')::boolean,
    '從來沒寄出過而且有累積 → 標成「看起來沒設定」', h::text);

  -- 一般會員讀不到內容
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.owner_notifications;
  perform pg_temp.ok(n = 0, '一般會員直接讀表也讀不到（裡面有檢舉內容）', n::text);
  perform set_config('role', 'none', true);

  raise notice '--- 寄出之後 ---';
  perform set_config('request.jwt.claim.sub', adm::text, true);
  perform public.mark_owner_notifications_sent(
    array(select id from public.owner_notifications where sent_at is null));
  h := public.owner_notification_health();
  perform pg_temp.ok((h->>'pending')::int = 0, '寄出之後 pending 歸零', h->>'pending');
  perform pg_temp.ok(not (h->>'looks_unconfigured')::boolean,
    '而且不再標成沒設定', h::text);

  raise notice '=== 相簿與通知測試結束 ===';
end $$;
