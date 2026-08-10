-- 意見回饋
--
-- 這一份主要在守兩件事：
-- (1) 使用者只看得到自己送出的，管理員看得到全部——回饋裡常常寫著很私人的挫折。
-- (2) 「像在講某個人」的提醒沿用第 24 節的訊號類別，不另外抄一份詞庫。
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
  insert into public.match_profiles(id, name, kind, species, consent, is_admin, account_status)
    values (p_id, p_name, 'keeper', 'dog', true, p_admin, 'active')
    on conflict (id) do update set is_admin = excluded.is_admin,
      account_status = excluded.account_status, name = excluded.name;
end $$;

do $$
declare
  a    uuid := '00000000-0000-0000-0000-00000000fb01';
  b    uuid := '00000000-0000-0000-0000-00000000fb02';
  boss uuid := '00000000-0000-0000-0000-00000000fb0a';
  f public.feedback; n int; q jsonb; ok_flag boolean;
begin
  raise notice '=== 意見回饋 ===';
  perform pg_temp.mkuser(a, 'fbA');
  perform pg_temp.mkuser(b, 'fbB');
  perform pg_temp.mkuser(boss, 'fbBoss', true);

  perform set_config('request.jwt.claim.sub', a::text, true);

  -- ── 送出 ───────────────────────────────────────────────
  f := public.submit_feedback('bug', '第 2 步按「上傳大頭照」之後沒有反應，重整照片也不見了。', 'center', '');
  perform pg_temp.ok(f.id is not null, '送得出去');
  perform pg_temp.ok(f.user_id = a, '送出者是自己，前端不能自己塞 user_id', f.user_id::text);
  perform pg_temp.ok(f.status = 'new', '狀態一律從 new 開始，前端不能自己塞', f.status);
  perform pg_temp.ok(f.page = 'center', '有記下是在哪一個分頁遇到的', f.page);
  perform pg_temp.ok(f.env = '', '沒有勾選就不附上瀏覽器資訊', '「' || f.env || '」');

  -- 太短、類別亂給、太頻繁
  begin
    perform public.submit_feedback('bug', '壞了', '', '');
    perform pg_temp.ok(false, '太短的內容擋下來');
  exception when others then perform pg_temp.ok(true, '太短的內容擋下來（修不了的回報等於沒有）'); end;
  begin
    perform public.submit_feedback('沒有這個類別', '這是一段夠長的意見內容', '', '');
    perform pg_temp.ok(false, '不支援的類別擋下來');
  exception when others then perform pg_temp.ok(true, '不支援的類別擋下來'); end;

  -- ── 只看得到自己的 ─────────────────────────────────────
  raise notice '--- 只看得到自己的 ---';
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.submit_feedback('suggestion', '希望佈告欄可以照最近更新排序。', 'board', '');

  perform set_config('request.jwt.claim.sub', a::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.feedback;
  perform pg_temp.ok(n = 1, '一般會員只讀得到自己送出的那一則', n::text);

  perform set_config('request.jwt.claim.sub', b::text, true);
  select count(*) into n from public.feedback;
  perform pg_temp.ok(n = 1, '另一個人也只讀得到自己的', n::text);

  perform set_config('request.jwt.claim.sub', boss::text, true);
  select count(*) into n from public.feedback;
  perform pg_temp.ok(n = 2, '管理員讀得到全部', n::text);
  perform set_config('role', 'postgres', true);

  -- ── 像在講某個人 ───────────────────────────────────────
  raise notice '--- 像在講某個人的提醒 ---';
  perform pg_temp.ok(
    not public.feedback_looks_personal('第 2 步的照片上傳按了沒反應'),
    '一般的產品問題不會被誤判成在講某個人');
  perform pg_temp.ok(
    not public.feedback_looks_personal('我不喜歡別人問我會不會口交，希望站上能講清楚界線'),
    '在講自己界線的回饋也不會被誤判（跟第 24 節同一條誤判防線）');
  perform pg_temp.ok(
    public.feedback_looks_personal('有個人一直傳裸照給我，還說不給看就把我的照片傳出去'),
    '真的在描述某個人的騷擾行為時會提醒');
  perform pg_temp.ok(
    public.feedback_looks_personal('對方說不聽話就讓我好看'),
    '威脅類的內容會提醒');

  /* 這個函式只回傳「要不要提醒」，不擋下送出——
     使用者說「這件事我就是想當成產品問題講」也是他的權利。 */
  perform set_config('request.jwt.claim.sub', a::text, true);
  f := public.submit_feedback('other', '有個人一直傳裸照給我，我想讓你們知道這個站需要更好的擋人機制。', '', '');
  perform pg_temp.ok(f.id is not null,
    '提醒歸提醒，看起來像在講某個人的內容仍然送得出去（不擋）');

  -- ── 管理端 ─────────────────────────────────────────────
  raise notice '--- 管理端 ---';
  perform set_config('request.jwt.claim.sub', boss::text, true);
  q := public.admin_feedback_list(null);
  perform pg_temp.ok(jsonb_array_length(q) = 3, '管理員列得出全部', jsonb_array_length(q)::text);
  q := public.admin_feedback_list('new');
  perform pg_temp.ok(jsonb_array_length(q) = 3, '可以只列未處理的', jsonb_array_length(q)::text);

  f := public.admin_set_feedback_status(f.id, 'done', '已修正，感謝回報');
  perform pg_temp.ok(f.status = 'done', '改得動狀態', f.status);
  perform pg_temp.ok(f.admin_note = '已修正，感謝回報', '回覆存得進去', f.admin_note);
  perform pg_temp.ok(f.handled_at is not null, '標成已處理時記下時間');

  q := public.admin_feedback_list('new');
  perform pg_temp.ok(jsonb_array_length(q) = 2, '已處理的就不在未處理清單裡', jsonb_array_length(q)::text);

  -- 送出者看得到站方的回覆（不然送出去就是個黑洞）
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', a::text, true);
  select count(*) into n from public.feedback
   where user_id = a and admin_note = '已修正，感謝回報';
  perform pg_temp.ok(n = 1, '送出者看得到站方的回覆', n::text);
  perform set_config('role', 'postgres', true);

  -- ── 一般會員叫不動管理端 ───────────────────────────────
  raise notice '--- 權限 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.admin_feedback_list(null);
    perform pg_temp.ok(false, '非管理員列不出全部意見回饋');
  exception when others then perform pg_temp.ok(true, '非管理員列不出全部意見回饋'); end;
  begin
    perform public.admin_set_feedback_status(f.id, 'new', '亂改');
    perform pg_temp.ok(false, '非管理員改不動狀態');
  exception when others then perform pg_temp.ok(true, '非管理員改不動狀態'); end;

  -- 未登入
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.submit_feedback('bug', '這是一段夠長的意見內容', '', '');
    perform pg_temp.ok(false, '沒登入送不出意見');
  exception when others then perform pg_temp.ok(true, '沒登入送不出意見'); end;

  -- ── 頻率限制 ───────────────────────────────────────────
  raise notice '--- 頻率限制 ---';
  perform set_config('request.jwt.claim.sub', b::text, true);
  begin
    for n in 1..5 loop
      perform public.submit_feedback('other', '這是第 ' || n || ' 則測試用的意見內容。', '', '');
    end loop;
    perform pg_temp.ok(false, '短時間內送太多會被擋');
  exception when others then
    perform pg_temp.ok(true, '短時間內送太多會被擋（防連點兩下與被盜帳號洗版）');
  end;

  -- ── 帳號被停用 ─────────────────────────────────────────
  update public.match_profiles set account_status = 'suspended' where id = a;
  perform set_config('request.jwt.claim.sub', a::text, true);
  begin
    perform public.submit_feedback('bug', '這是一段夠長的意見內容', '', '');
    perform pg_temp.ok(false, '被停用的帳號送不出意見');
  exception when others then perform pg_temp.ok(true, '被停用的帳號送不出意見'); end;

  raise notice '=== 意見回饋測試結束 ===';
end $$;
