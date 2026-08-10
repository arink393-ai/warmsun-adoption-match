-- 🌱 陪伴紀錄第 5 步：關係健康檢查
--
-- 這一份守的是規格第 4 節那一句：
--   A 填「最近覺得孤單」，系統**不會**通知 B「你的伴侶說跟你交往很孤單」。
-- 那只會直接製造一場架，而且會讓人下次不敢誠實填。
-- 所以這裡驗的重點是「什麼情況下對方拿得到我的答案」，
-- 以及「拿到了之後只能拿來做什麼」。
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
  insert into public.match_profiles(id,name,kind,species,consent,account_status)
    values (a,'甲','pet','cat',true,'active'), (b,'乙','keeper','dog',true,'active')
    on conflict (id) do update set account_status='active', posting_locked=false;
  insert into public.applications(from_user,to_user,stage,status,unlock_from,unlock_to)
    values (b,a,3,'open',true,true) returning id into app;
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform public.set_companion_agree(app, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  st := public.set_companion_agree(app, true);
  return (st->>'link_id')::uuid;
end $$;

-- ════════════════════════════════════════════════════════════
-- 一、題目本身
-- ════════════════════════════════════════════════════════════
do $$
declare q jsonb; txt text;
begin
  raise notice '=== 題目 ===';
  q := public.checkin_questions();
  perform pg_temp.ok(jsonb_array_length(q) >= 5, '題目不只一兩題', jsonb_array_length(q)::text);

  /* 選項刻意用文字而不是 1～5。
     數字放在那裡遲早會有人把它加起來，然後就有了一個沒有校準基礎的分數。 */
  txt := q::text;
  perform pg_temp.ok(txt !~ '"[1-5]"' and txt !~ '非常同意|完全不同意',
    '選項不是 1～5 分量表（數字放著遲早會被加起來變成分數）', left(txt, 200));

  perform pg_temp.ok(txt like '%太多了想要一點自己的時間%',
    '「相處時間」有「太多了」這個方向（不預設相處越多越好）', left(txt, 400));
  perform pg_temp.ok(txt like '%說不上來%',
    '每一題都留一個「說不上來」（不強迫把感覺分類）');
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、預設不分享
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e1a01';
  b uuid := '00000000-0000-0000-0000-0000000e1a02';
  lk uuid; r jsonb; s jsonb; n int; def text;
begin
  raise notice '=== 分享 ===';
  lk := pg_temp.mklink(a, b);

  select column_default into def from information_schema.columns
   where table_schema='public' and table_name='relationship_checkins'
     and column_name='share_with_partner';
  perform pg_temp.ok(def = 'false',
    'share_with_partner 的預設值就是 false（這個預設值本身就是那條規則）', def);

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.submit_checkin(lk, '{"connected":"有點遠","time":"太少","stress":["工作","金錢"]}'::jsonb);
  perform pg_temp.ok(not (r->>'shared')::boolean, '沒特別說就是不分享', r::text);

  -- 乙讀不到
  perform set_config('request.jwt.claim.sub', b::text, true);
  select count(*) into n from public.relationship_checkins
   where link_id = lk and user_id = a and share_with_partner;
  perform pg_temp.ok(n = 0, '沒分享的那一份對方拿不到');

  s := public.checkin_summary(lk);
  perform pg_temp.ok(not (s->>'has_mine')::boolean, '乙自己還沒填', s::text);
  /* 「對方填了但沒給你看」這句話本身就是一個指控。 */
  perform pg_temp.ok(s::text not like '%有點遠%' and s::text not like '%太少%',
    '摘要裡完全看不到對方沒分享的答案', s::text);
  perform pg_temp.ok(not (s->>'both_shared')::boolean,
    '也不會透露「對方填了但沒分享」', s::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、兩邊都分享才有共同觀察
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e1b01';
  b uuid := '00000000-0000-0000-0000-0000000e1b02';
  lk uuid; r jsonb; s jsonb; obs text;
begin
  raise notice '=== 共同觀察 ===';
  lk := pg_temp.mklink(a, b);

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.submit_checkin(lk,
    '{"connected":"有點遠","time":"太少","stress":["工作","金錢"],"want_more":["被理解"]}'::jsonb, true);
  perform set_config('request.jwt.claim.sub', b::text, true);
  r := public.submit_checkin(lk,
    '{"connected":"跟之前差不多","time":"太少","stress":["工作","家人"],"want_more":["自己的時間"]}'::jsonb, true);

  s := public.checkin_summary(lk);
  perform pg_temp.ok((s->>'both_shared')::boolean, '兩邊都分享了才成立', s::text);
  obs := s->>'shared_observations';

  /* 共同觀察只列**兩個人一樣**的那幾項，而且是並列描述。
     不一樣的地方不會被端出來說「你們對這件事看法不同」——
     那是把差異變成一個要處理的問題。 */
  perform pg_temp.ok(obs like '%太少%', '兩個人都覺得相處時間太少 → 列為共同', obs);
  perform pg_temp.ok(obs like '%工作%', '兩個人都勾了工作 → 列為共同', obs);
  perform pg_temp.ok(obs not like '%金錢%' and obs not like '%家人%',
    '只有一個人勾的不算共同（不會變成「他覺得你有問題」）', obs);
  perform pg_temp.ok(obs not like '%有點遠%' and obs not like '%跟之前差不多%',
    '兩個人答不一樣的那一題整題不出現（差異不是要被指出來的東西）', obs);

  -- 沒有分數
  perform pg_temp.ok(s::text !~ 'score|Score|分數|健康度|[0-9]+%',
    '摘要裡沒有任何分數（沒有校準基礎的數字會被當成結論）', s::text);

  -- 有一個可以談的方向，而且是問句
  perform pg_temp.ok(s->>'next_question' is not null, '給一個可以談的方向');
  perform pg_temp.ok((s->>'next_question') like '%？',
    '而且是問句，不是指令（診療室是協調者，不是仲裁者）', s->>'next_question');
  perform pg_temp.ok((s->>'next_question') !~ '應該|必須|你要|建議你',
    '不用祈使句', s->>'next_question');

  -- 分享可以反悔
  raise notice '--- 反悔 ---';
  perform set_config('request.jwt.claim.sub', a::text, true);
  s := public.checkin_summary(lk);
  perform public.set_checkin_share((s->>'mine_id')::uuid, false);
  perform set_config('request.jwt.claim.sub', b::text, true);
  s := public.checkin_summary(lk);
  perform pg_temp.ok(not (s->>'both_shared')::boolean,
    '對方收回分享之後共同觀察就沒了（分享是可以反悔的）', s::text);
  perform pg_temp.ok((s->>'shared_observations') = '[]',
    '而且已經算出來的共同觀察也不會留著', s->>'shared_observations');
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、每月最多一次
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000e1c01';
  b uuid := '00000000-0000-0000-0000-0000000e1c02';
  x uuid := '00000000-0000-0000-0000-0000000e1c09';
  lk uuid; r jsonb; n int;
begin
  raise notice '=== 頻率與雜訊 ===';
  lk := pg_temp.mklink(a, b);
  insert into auth.users(id,email) values (x,'x1@t.local') on conflict do nothing;

  perform set_config('request.jwt.claim.sub', a::text, true);
  r := public.submit_checkin(lk, '{"connected":"更靠近了"}'::jsonb);
  begin
    perform public.submit_checkin(lk, '{"connected":"有點遠"}'::jsonb);
    /* 這個上限的用途是擋住系統自己：一旦可以天天填，
       畫面上遲早會長出「你已經 5 天沒有回診了」。 */
    perform pg_temp.ok(false, '一個月內填第二次會被擋');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%30 天%',
      '一個月內填第二次會被擋，而且說得出下一次是什麼時候', sqlerrm);
  end;

  -- 不是題目表裡的 key 會被丟掉
  update public.relationship_checkins set created_at = now() - interval '40 days'
   where link_id = lk and user_id = a;
  r := public.submit_checkin(lk, '{"connected":"更靠近了","secret_field":"任意值"}'::jsonb);
  select count(*) into n from public.relationship_checkins
   where link_id = lk and user_id = a and answers ? 'secret_field';
  perform pg_temp.ok(n = 0,
    '題目表以外的欄位會被丟掉（這張表會被 AI 讀，不能變成任意欄位的倉庫）', n::text);

  -- 局外人
  perform set_config('request.jwt.claim.sub', x::text, true);
  begin
    perform public.submit_checkin(lk, '{"connected":"更靠近了"}'::jsonb);
    perform pg_temp.ok(false, '局外人填不進去');
  exception when others then perform pg_temp.ok(true, '局外人填不進去'); end;
  begin
    perform public.checkin_summary(lk);
    perform pg_temp.ok(false, '局外人讀不到摘要');
  exception when others then perform pg_temp.ok(true, '局外人讀不到摘要'); end;

  -- 只有本人能改自己的分享設定
  perform set_config('request.jwt.claim.sub', b::text, true);
  begin
    perform public.set_checkin_share(
      (select id from public.relationship_checkins where user_id = a limit 1), true);
    perform pg_temp.ok(false, '不能替對方按下分享');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%只有本人%',
      '不能替對方按下分享（替別人決定要不要公開自己的感受是最不能允許的事）', sqlerrm);
  end;

  raise notice '=== 健康檢查測試結束 ===';
end $$;
