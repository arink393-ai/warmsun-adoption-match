-- 認養看板與《認養申請病例》：在真的 Postgres 16 上驗證
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
    account_status, consent, credits, area)
  values (p_id, p_name, 'keeper', 'dog', 'm', 'approved', 'approved', 'active', true, 99, '台北')
  on conflict (id) do update set
    name = excluded.name, kind = excluded.kind, species = excluded.species,
    gender = excluded.gender, photo_status = excluded.photo_status,
    verify_status = excluded.verify_status, account_status = excluded.account_status,
    consent = excluded.consent, credits = excluded.credits, area = excluded.area;
end $$;

-- 依 app_id 取出看板的那一列
create or replace function pg_temp.row_of(p_board jsonb, p_app uuid) returns jsonb
language sql immutable as $$
  select r from jsonb_array_elements(p_board) r where r->>'app_id' = p_app::text;
$$;

do $$
declare
  hoster uuid := '00000000-0000-0000-0000-0000000000d0';   -- 收件人（志工視角）
  a1 uuid := '00000000-0000-0000-0000-0000000000d1';
  a2 uuid := '00000000-0000-0000-0000-0000000000d2';
  a3 uuid := '00000000-0000-0000-0000-0000000000d3';
  app1 uuid; app2 uuid; app3 uuid;
  board jsonb; r jsonb; cs jsonb; n int;
begin
  raise notice '=== 準備：一個收件人、三個申請人 ===';
  perform pg_temp.mkuser(hoster, 'boardto');
  perform pg_temp.mkuser(a1, 'boardA');
  perform pg_temp.mkuser(a2, 'boardB');
  perform pg_temp.mkuser(a3, 'boardC');
  delete from public.applications where to_user = hoster;

  -- 收件人設一個「需沒有小孩」的條件，讓 a2 會亮紅燈
  update public.match_profiles set req_kids = '需沒有小孩', kids_plan = '想要小孩' where id = hoster;
  update public.match_profiles set weekly_work_hours = 120 where id = a1;   -- 🟡
  update public.match_profiles set has_kids = '有，同住' where id = a2;      -- 🔴
  update public.match_profiles set weekly_work_hours = 40, has_kids = '沒有',
    kids_plan = '想要小孩' where id = a3;                                    -- 🟢

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  for n in 1..3 loop
    perform set_config('request.jwt.claim.sub',
      case n when 1 then a1::text when 2 then a2::text else a3::text end, true);
    perform public.apply_to(hoster, '["答案"]'::jsonb, '["題目"]'::jsonb);
  end loop;
  -- 要先切回收件人，applications 的 RLS 才讓我們看得到這三筆
  -- （迴圈跑完時 jwt 還停在最後一個申請人身上）
  perform set_config('request.jwt.claim.sub', hoster::text, true);
  select id into app1 from public.applications where from_user = a1 and to_user = hoster;
  select id into app2 from public.applications where from_user = a2 and to_user = hoster;
  select id into app3 from public.applications where from_user = a3 and to_user = hoster;
  perform pg_temp.ok(app1 is not null and app2 is not null and app3 is not null,
    '三筆申請都建立起來了');

  -- ── 一、看板一次回傳 ────────────────────────────────────
  raise notice '--- 看板 ---';
  perform set_config('request.jwt.claim.sub', hoster::text, true);
  board := public.get_crm_board();
  perform pg_temp.ok(jsonb_array_length(board) = 3, '看板一次回傳三筆申請',
    jsonb_array_length(board)::text);

  r := pg_temp.row_of(board, app1);
  perform pg_temp.ok(r->>'name' = 'boardA', '帶出申請人的名字（不用另外一封一封查）', r->>'name');
  perform pg_temp.ok((r->>'stage')::int = 1 and r->>'status' = 'open', '帶出階段與狀態');
  perform pg_temp.ok((r->>'has_a1')::boolean, '知道第一階段有沒有作答');
  perform pg_temp.ok(r->>'opened_at' is null, '還沒打開 → opened_at 是空的');
  perform pg_temp.ok((r->>'unread')::int = 0, '未讀訊息數是 0');

  -- ── 二、初診燈號一起帶回來 ───────────────────────────────
  raise notice '--- 初診燈號 ---';
  -- 先讓三筆都跑過初診（正常情況下是使用者點「查看初診結果」時跑的）
  perform public.get_screening_for(a1);
  perform public.get_screening_for(a2);
  perform public.get_screening_for(a3);
  board := public.get_crm_board();

  perform pg_temp.ok((pg_temp.row_of(board, app1)->>'screened')::boolean,
    '跑過初診的申請會標記 screened');
  perform pg_temp.ok((pg_temp.row_of(board, app1)->>'yellow')::int >= 1,
    'A（工時 120）在看板上就看得到 🟡', pg_temp.row_of(board, app1)->>'yellow');
  perform pg_temp.ok((pg_temp.row_of(board, app2)->>'red')::int >= 1,
    'B（有孩子 vs 需沒有小孩）在看板上就看得到 🔴', pg_temp.row_of(board, app2)->>'red');
  perform pg_temp.ok((pg_temp.row_of(board, app3)->>'red')::int = 0,
    'C 沒有紅燈', pg_temp.row_of(board, app3)->>'red');

  -- 看板只給數量，不給細節——細節仍然只能走 get_screening_for
  perform pg_temp.ok(board::text not like '%已有孩子%' and board::text not like '%工作時間%',
    '看板只帶燈號數量，不帶初診的細節文案');

  -- ── 三、九個分格都算得出來 ───────────────────────────────
  raise notice '--- 九個分格 ---';
  perform public.mark_applications_opened(array[app1]);
  board := public.get_crm_board();
  perform pg_temp.ok(pg_temp.row_of(board, app1)->>'opened_at' is not null,
    '📋 打開過的會有 opened_at（跟 📨 新申請分得開）');
  perform pg_temp.ok(pg_temp.row_of(board, app2)->>'opened_at' is null,
    '📨 沒打開的仍然是新申請');

  perform public.send_stage2(app1, '["情境題"]'::jsonb);
  board := public.get_crm_board();
  perform pg_temp.ok((pg_temp.row_of(board, app1)->>'stage')::int = 2, '💬 第二階段算得出來');
  perform pg_temp.ok((pg_temp.row_of(board, app1)->>'stage2_paid')::boolean,
    '第二階段的子狀態（待出題／待作答）也分得出來');

  update public.applications set status = 'rejected' where id = app3;
  board := public.get_crm_board();
  perform pg_temp.ok(pg_temp.row_of(board, app3)->>'status' = 'rejected', '🏠 結案算得出來');
  perform pg_temp.ok(pg_temp.row_of(board, app3)->>'closed_reason' = 'declined_stage1',
    '結案帶出在哪一關流失', pg_temp.row_of(board, app3)->>'closed_reason');

  perform pg_temp.ok((pg_temp.row_of(board, app2)->>'idle_days')::int >= 0,
    '💤 逾期用 idle_days 判斷，看板直接算好');

  -- ── 四、《認養申請病例》七區塊 ───────────────────────────
  raise notice '--- 認養申請病例 ---';
  cs := public.get_application_case(app2);
  perform pg_temp.ok(cs->>'app_id' = app2::text, '① 病例摘要：拿得到這筆申請');
  perform pg_temp.ok((cs->'screening'->>'red')::int >= 1, '② 初診結果：帶出燈號',
    cs->'screening'->>'red');
  perform pg_temp.ok(cs->'screening'->'findings' is not null, '② 初診結果：帶出細節');

  perform pg_temp.ok(jsonb_array_length(cs->'templates') >= 1,
    '⑤ 回覆建議：依初診的理由碼推薦罐頭（不用 AI）',
    jsonb_array_length(cs->'templates')::text);
  perform pg_temp.ok((cs->'templates')::text like '%核心條件差異%',
    '⑤ 推薦的是對得上這個燈號的那一封', (cs->'templates')::text);

  perform pg_temp.ok(jsonb_array_length(cs->'my_reports') = 0, '⑥ 安全：目前沒有檢舉紀錄');
  perform pg_temp.ok((cs->>'blocked')::boolean = false, '⑥ 安全：目前沒有封鎖');

  -- 送一筆檢舉，再看一次
  insert into public.reports(target_id, by_id, why) values (a2, hoster, '測試用的檢舉理由');
  cs := public.get_application_case(app2);
  perform pg_temp.ok(jsonb_array_length(cs->'my_reports') = 1,
    '⑥ 安全：看得到「自己」送出過的檢舉', jsonb_array_length(cs->'my_reports')::text);

  -- ⑥ 只給自己的檢舉，不給別人的
  perform set_config('role', 'postgres', true);
  insert into public.reports(target_id, by_id, why) values (a2, a1, '別人送的檢舉');
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', hoster::text, true);
  cs := public.get_application_case(app2);
  perform pg_temp.ok(jsonb_array_length(cs->'my_reports') = 1,
    '⑥ 安全：別人送出的檢舉不會出現（那是管理員的事）',
    jsonb_array_length(cs->'my_reports')::text);
  perform pg_temp.ok(cs::text not like '%別人送的檢舉%', '⑥ 別人的檢舉內容完全不外流');

  -- ④ 志工筆記
  perform public.save_case_note(app2, '已電話確認，對方說孩子跟前配偶同住');
  cs := public.get_application_case(app2);
  perform pg_temp.ok(cs->>'note' like '%已電話確認%', '④ 面談紀錄：志工筆記存得起來', cs->>'note');
  perform pg_temp.ok(
    (select count(*) from public.application_events
      where app_id = app2 and kind = 'noted' and visibility = 'recipient') = 1,
    '④ 寫筆記會留下 recipient-only 的時間軸事件');

  -- ── 五、只能看自己的收件匣 ───────────────────────────────
  raise notice '--- 權限 ---';
  perform set_config('request.jwt.claim.sub', a1::text, true);
  board := public.get_crm_board();
  perform pg_temp.ok(jsonb_array_length(board) = 0,
    '申請人自己的看板是空的（看板是收件方視角）', jsonb_array_length(board)::text);
  begin
    perform public.get_application_case(app2);
    perform pg_temp.ok(false, '別人的病例不該打得開');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%找不到%', '別人的病例打不開');
  end;
  begin
    perform public.save_case_note(app2, '亂寫');
    perform pg_temp.ok(false, '別人的病例不該寫得了筆記');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%找不到%', '別人的病例寫不了筆記');
  end;

  raise notice '=== 看板測試結束 ===';
end $$;
