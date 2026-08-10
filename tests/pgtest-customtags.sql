-- 自訂選項：興趣、個性、物種、性別
--
-- 這一份守的是一件事：**這四個欄位在佈告欄上是第 0 層公開的。**
-- 開放自由輸入等於開了一條「把任何文字放到所有人都看得到的地方」的管道，
-- 而暖陽整套四層揭露就是為了讓聯絡方式要走完三階段、雙方同意才交換。
-- 一個叫「我的興趣」的欄位如果可以填「IG: xxx_1234」，整套流程就被繞過去了，
-- 而且是使用者自己繞的，不會有人來檢舉。
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
-- 一、聯絡方式的偵測
-- ════════════════════════════════════════════════════════════
do $$
begin
  raise notice '=== 聯絡方式偵測 ===';

  -- 正常的標籤不能被誤擋，不然這個功能等於沒開放
  perform pg_temp.ok(not public.looks_like_contact('攝影'), '「攝影」不是聯絡方式');
  perform pg_temp.ok(not public.looks_like_contact('戶外／登山'), '「戶外／登山」不是聯絡方式');
  perform pg_temp.ok(not public.looks_like_contact('ISTJ 型的人'), '含英文字母的一般標籤不會被誤擋');
  perform pg_temp.ok(not public.looks_like_contact('每天喝 3 杯咖啡'), '含數字的一般標籤不會被誤擋');
  perform pg_temp.ok(not public.looks_like_contact('非二元'), '自訂性別不會被誤擋');
  perform pg_temp.ok(not public.looks_like_contact('鸚鵡（玄鳳）'), '自訂物種不會被誤擋');

  -- 真的是聯絡方式的要擋下來
  perform pg_temp.ok(public.looks_like_contact('me@example.com'), 'email 擋下來');
  perform pg_temp.ok(public.looks_like_contact('0912345678'), '手機號碼擋下來');
  perform pg_temp.ok(public.looks_like_contact('0912-345-678'), '有分隔線的手機號碼也擋');
  perform pg_temp.ok(public.looks_like_contact('LINE ID: abcd'), 'LINE ID 擋下來');
  perform pg_temp.ok(public.looks_like_contact('加賴 id abcd'), '「加賴」也擋');
  perform pg_temp.ok(public.looks_like_contact('IG @mycoolname'), 'IG 帳號擋下來');
  perform pg_temp.ok(public.looks_like_contact('@mycoolname'), '單純的 @帳號 也擋');
  perform pg_temp.ok(public.looks_like_contact('https://instagram.com/x'), '網址擋下來');

  raise notice '=== 偵測結束 ===';
end $$;

-- ════════════════════════════════════════════════════════════
-- 二、清洗
-- ════════════════════════════════════════════════════════════
do $$
declare j jsonb;
begin
  raise notice '--- 清洗 ---';
  j := public.clean_tags('["攝影","攝影","  攝影  ",""]'::jsonb);
  perform pg_temp.ok(jsonb_array_length(j) = 1, '重複與空白修剪後只留一個', j::text);

  j := public.clean_tags('["爬 山"]'::jsonb);
  perform pg_temp.ok(j->>0 = '爬 山', '字中間的空白保留（不亂動使用者寫的字）', j::text);

  j := public.clean_tags('["換\n行"]'::jsonb);
  perform pg_temp.ok((j->>0) !~ E'\n', '換行被收成空白（卡片版面靠它排版）', j::text);

  j := public.clean_tags('["這個標籤實在是有夠長超過十二個字了啦","攝影"]'::jsonb);
  perform pg_temp.ok(jsonb_array_length(j) = 1 and j->>0 = '攝影',
    '超過長度的整個丟掉，短的留著', j::text);

  j := public.clean_tags(to_jsonb(array(select '標籤' || i from generate_series(1,40) i)));
  perform pg_temp.ok(jsonb_array_length(j) = 20, '最多留 20 個', jsonb_array_length(j)::text);

  j := public.clean_tags('"不是陣列"'::jsonb);
  perform pg_temp.ok(j = '[]'::jsonb, '不是陣列的輸入不會炸掉，回空陣列', j::text);
  j := public.clean_tags(null);
  perform pg_temp.ok(j = '[]'::jsonb, 'null 也不會炸掉', j::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 三、存檔時真的擋得住
-- ════════════════════════════════════════════════════════════
do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000cf01';
  p public.match_profiles;
begin
  raise notice '--- 存檔 ---';
  insert into auth.users(id, email) values (a, 'ct@t.local') on conflict do nothing;
  insert into public.match_profiles(id, name, kind, species, gender, consent)
    values (a, '自訂測試', 'pet', 'cat', 'f', true)
    on conflict (id) do update set name = excluded.name;

  -- 自訂標籤存得進去
  update public.match_profiles
     set interests = '["攝影","陶藝","獨木舟"]'::jsonb,
         personality = '["三分鐘熱度但很認真"]'::jsonb
   where id = a;
  select * into p from public.match_profiles where id = a;
  perform pg_temp.ok(jsonb_array_length(p.interests) = 3, '自訂興趣存得進去', p.interests::text);
  perform pg_temp.ok(p.personality->>0 = '三分鐘熱度但很認真',
    '自訂個性標籤存得進去（原文不會被改）', p.personality::text);

  -- 自訂物種與性別
  update public.match_profiles set species = '玄鳳鸚鵡', gender = '非二元' where id = a;
  select * into p from public.match_profiles where id = a;
  perform pg_temp.ok(p.species = '玄鳳鸚鵡', '自訂物種存得進去', p.species);
  perform pg_temp.ok(p.gender = '非二元', '自訂性別存得進去', p.gender);

  -- 聯絡方式擋下來，而且是報錯不是靜靜丟掉
  begin
    update public.match_profiles set interests = '["攝影","IG @mycoolname"]'::jsonb where id = a;
    perform pg_temp.ok(false, '興趣標籤裡的聯絡方式被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%聯絡方式%',
      '興趣標籤裡的聯絡方式被擋下來，而且訊息說得出原因', sqlerrm);
  end;

  begin
    update public.match_profiles set personality = '["0912345678"]'::jsonb where id = a;
    perform pg_temp.ok(false, '個性標籤裡的手機號碼被擋下來');
  exception when others then perform pg_temp.ok(true, '個性標籤裡的手機號碼被擋下來'); end;

  begin
    update public.match_profiles set species = 'line id abcd' where id = a;
    perform pg_temp.ok(false, '物種欄位裡的聯絡方式被擋下來');
  exception when others then perform pg_temp.ok(true, '物種欄位裡的聯絡方式被擋下來'); end;

  begin
    update public.match_profiles set gender = 'me@example.com' where id = a;
    perform pg_temp.ok(false, '性別欄位裡的聯絡方式被擋下來');
  exception when others then perform pg_temp.ok(true, '性別欄位裡的聯絡方式被擋下來'); end;

  -- 擋下來之後，原本的值沒有被改掉
  select * into p from public.match_profiles where id = a;
  perform pg_temp.ok(p.species = '玄鳳鸚鵡' and p.gender = '非二元',
    '被擋下來的那次更新整筆都沒生效（不會存進去一半）',
    p.species || '／' || p.gender);

  -- 太長的自訂物種
  begin
    update public.match_profiles set species = '這個物種名稱實在是有夠長超過十二個字' where id = a;
    perform pg_temp.ok(false, '太長的自訂物種被擋下來');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%12%', '太長的自訂物種被擋下來，而且說出上限', sqlerrm);
  end;

  /* 太長的標籤要**報錯**，不是靜靜丟掉。
     第一版把 clean_tags 排在檢查前面，結果「IG @mycoolname」因為超過 12 個字
     先被長度過濾掉，聯絡方式的檢查根本沒跑到——使用者以為存好了，
     實際上那一項消失了，而且他不知道為什麼。 */
  begin
    update public.match_profiles set interests = '["這個興趣標籤實在有夠長超過限制"]'::jsonb where id = a;
    perform pg_temp.ok(false, '太長的標籤會報錯而不是靜靜消失');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%12 個字%',
      '太長的標籤會報錯而不是靜靜消失，而且說得出上限與替代做法', sqlerrm);
  end;

  -- 而且長的聯絡方式一樣擋得住（不會因為太長就先被丟掉而漏檢）
  begin
    update public.match_profiles
       set interests = '["請加我的 IG @mycoolname_2026"]'::jsonb where id = a;
    perform pg_temp.ok(false, '很長的聯絡方式也擋得住');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%聯絡方式%',
      '很長的聯絡方式也擋得住，而且報的是「聯絡方式」不是「太長」', sqlerrm);
  end;

  -- 太多也要報錯
  begin
    update public.match_profiles
       set interests = to_jsonb(array(select '興趣' || i from generate_series(1,25) i))
     where id = a;
    perform pg_temp.ok(false, '超過 20 個標籤會報錯');
  exception when others then
    perform pg_temp.ok(sqlerrm like '%20 個%', '超過 20 個標籤會報錯而不是靜靜砍掉', sqlerrm);
  end;

  -- 清洗在存檔時也有作用
  update public.match_profiles set interests = '["攝影","攝影","  攝影  "]'::jsonb where id = a;
  select * into p from public.match_profiles where id = a;
  perform pg_temp.ok(jsonb_array_length(p.interests) = 1,
    '存檔時會去掉重複（前端漏擋也不會存進三個一樣的）', p.interests::text);
end $$;

-- ════════════════════════════════════════════════════════════
-- 四、全站熱門的自訂標籤
-- ════════════════════════════════════════════════════════════
do $$
declare
  u uuid; q jsonb; i int;
begin
  raise notice '--- 熱門自訂標籤 ---';
  -- 四個人都填了「陶藝」，只有一個人填「獨木舟」
  for i in 1..4 loop
    u := ('00000000-0000-0000-0000-00000000c1' || lpad(i::text, 2, '0'))::uuid;
    insert into auth.users(id, email) values (u, 'tag' || i || '@t.local') on conflict do nothing;
    insert into public.match_profiles(id, name, kind, species, gender, consent, account_status, interests)
      values (u, '人' || i, 'pet', 'cat', 'f', true, 'active',
              case when i = 1 then '["陶藝","獨木舟"]'::jsonb else '["陶藝"]'::jsonb end)
      on conflict (id) do update set interests = excluded.interests, account_status = 'active';
  end loop;

  perform set_config('request.jwt.claim.sub', ('00000000-0000-0000-0000-00000000c101')::text, true);
  q := public.popular_custom_tags('interests', 3);
  perform pg_temp.ok(q::text like '%陶藝%', '四個人都在用的標籤會被推薦給後來的人', q::text);

  /* 只有一個人在用的標籤不會被端出來——那等於用一個標籤反向指認一個人。 */
  perform pg_temp.ok(q::text not like '%獨木舟%',
    '只有一個人在用的標籤不會出現（那等於用標籤反向指認一個人）', q::text);

  begin
    perform public.popular_custom_tags('bio', 3);
    perform pg_temp.ok(false, '不支援的欄位叫不動');
  exception when others then perform pg_temp.ok(true, '不支援的欄位叫不動（不能拿它去讀別欄）'); end;

  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.popular_custom_tags('interests', 3);
    perform pg_temp.ok(false, '沒登入讀不到');
  exception when others then perform pg_temp.ok(true, '沒登入讀不到'); end;

  raise notice '=== 自訂選項測試結束 ===';
end $$;
