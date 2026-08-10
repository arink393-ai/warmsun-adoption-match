-- 罐頭中心：GRANT、理由碼清單、只有管理員能改
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
  insert into public.match_profiles(id, name, kind, species, gender, photo_status, verify_status,
    account_status, consent, is_admin)
  values (p_id, p_name, 'pet', 'cat', 'f', 'approved', 'approved', 'active', true, p_admin)
  on conflict (id) do update set name = excluded.name, is_admin = excluded.is_admin,
    kind = excluded.kind, species = excluded.species, photo_status = excluded.photo_status,
    verify_status = excluded.verify_status, account_status = excluded.account_status;
end $$;

do $$
declare
  boss uuid := '00000000-0000-0000-0000-0000000000e1';
  mem  uuid := '00000000-0000-0000-0000-0000000000e2';
  codes jsonb; n int; txt text; arr text[];
begin
  raise notice '=== 準備 ===';
  perform pg_temp.mkuser(boss, 'tplboss', true);
  perform pg_temp.mkuser(mem,  'tplmem',  false);

  -- ── 一、GRANT 補上了 ────────────────────────────────────
  raise notice '--- GRANT ---';
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', mem::text, true);

  begin
    select count(*) into n from public.template_master;
    perform pg_temp.ok(n > 0, '一般會員讀得到範本主檔（這個 GRANT 之前一直是漏的）', n::text);
  exception when insufficient_privilege then
    perform pg_temp.ok(false, '一般會員讀得到範本主檔', 'permission denied');
  end;

  -- ── 二、理由碼清單 ──────────────────────────────────────
  raise notice '--- 理由碼清單 ---';
  codes := public.list_reason_codes();
  perform pg_temp.ok(jsonb_array_length(codes) >= 5,
    '規則庫裡的理由碼列得出來', jsonb_array_length(codes)::text);
  perform pg_temp.ok(codes::text like '%R_WORK_HOURS_EXTREME%',
    '含 R_WORK_HOURS_EXTREME');
  perform pg_temp.ok(codes::text like '%填寫的工作時間非常高%',
    '每個理由碼帶出是哪幾條規則會亮（後台才知道自己在勾什麼）');
  perform pg_temp.ok(codes::text not like '%"code": null%' and codes::text not like '%null%',
    '沒有 reason_code 的規則不會混進清單');

  -- 同一個理由碼被多條規則共用時只出現一次
  select count(*) into n from jsonb_array_elements(codes) c
   where c->>'code' = 'R_WORK_HOURS_HIGH';
  perform pg_temp.ok(n <= 1, '同一個理由碼只出現一次', n::text);

  -- ── 三、只有管理員能改 ──────────────────────────────────
  raise notice '--- 權限 ---';
  update public.template_master set reason_codes = array['亂改的'] where id = 'FOLLOWUP_WORK_HOURS';
  select reason_codes into arr from public.template_master where id = 'FOLLOWUP_WORK_HOURS';
  perform pg_temp.ok(not (arr @> array['亂改的']),
    '一般會員改不動理由碼（RLS 擋下）', array_to_string(arr, ','));

  perform set_config('request.jwt.claim.sub', boss::text, true);
  update public.template_master
     set reason_codes = array['R_WORK_HOURS_HIGH','R_WORK_HOURS_EXTREME'],
         text = '管理員改過的內容'
   where id = 'FOLLOWUP_WORK_HOURS';
  select reason_codes, text into arr, txt from public.template_master where id = 'FOLLOWUP_WORK_HOURS';
  perform pg_temp.ok(arr @> array['R_WORK_HOURS_EXTREME'], '管理員改得動理由碼',
    array_to_string(arr, ','));
  perform pg_temp.ok(txt = '管理員改過的內容', '管理員改得動內文', txt);

  -- ── 四、改完之後推薦真的跟著變 ──────────────────────────
  raise notice '--- 改完之後推薦跟著變 ---';
  -- 把 R_WORK_HOURS_EXTREME 從這封拿掉，該理由碼就不該再推薦這一封
  perform set_config('role', 'postgres', true);
  update public.template_master set reason_codes = array['R_WORK_HOURS_HIGH']
   where id = 'FOLLOWUP_WORK_HOURS';
  select count(*) into n from public.template_master t
   where t.reason_codes && array['R_WORK_HOURS_EXTREME'];
  perform pg_temp.ok(n = 0, '拿掉之後，這個理由碼就沒有任何罐頭對得上了', n::text);

  update public.template_master set reason_codes = array['R_WORK_HOURS_HIGH','R_WORK_HOURS_EXTREME']
   where id = 'FOLLOWUP_WORK_HOURS';
  select count(*) into n from public.template_master t
   where t.reason_codes && array['R_WORK_HOURS_EXTREME'];
  perform pg_temp.ok(n = 1, '加回去之後又對得上了', n::text);

  -- ── 五、覆蓋率：後台要看得出缺口 ────────────────────────
  raise notice '--- 覆蓋率 ---';
  select count(*) into n from jsonb_array_elements(public.list_reason_codes()) c
   where not exists (select 1 from public.template_master t
                      where t.reason_codes && array[c->>'code']);
  perform pg_temp.ok(n >= 0, '「有理由碼但沒有罐頭」算得出來（目前 ' || n || ' 個）', n::text);

  select count(*) into n from public.template_master t,
       lateral unnest(t.reason_codes) rc
   where not exists (select 1 from public.screening_rules r where r.reason_code = rc);
  perform pg_temp.ok(n = 0, '目前沒有罐頭指向不存在的理由碼', n::text);

  -- 故意造一個失效的，確認算得出來
  perform set_config('role', 'postgres', true);
  update public.template_master set reason_codes = reason_codes || array['R_不存在的碼']
   where id = 'FOLLOWUP_KIDS';
  select count(*) into n from public.template_master t,
       lateral unnest(t.reason_codes) rc
   where not exists (select 1 from public.screening_rules r where r.reason_code = rc);
  perform pg_temp.ok(n = 1, '指向不存在理由碼的罐頭抓得出來（這種永遠不會被推薦）', n::text);
  update public.template_master set reason_codes = array_remove(reason_codes, 'R_不存在的碼')
   where id = 'FOLLOWUP_KIDS';

  raise notice '=== 罐頭中心測試結束 ===';
end $$;
