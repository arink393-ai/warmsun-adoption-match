#!/usr/bin/env node
/* data/relationship-topics.json 是八個生活場景的唯一來源。
   這支程式做兩件事：
     gen-topics.mjs           重新產生 js/relationship-topics.js
     gen-topics.mjs --check   檢查產生物與規則庫有沒有跟來源漂移（漂移就 exit 1）

   為什麼不是讓網頁直接 fetch 那份 JSON：暖陽是純靜態站，測試是用 file:// 開的，
   file:// 下 fetch 會被 CORS 擋掉。所以產生一支 <script src> 就能載入的 .js，
   兩個頁面都用得到，也不需要任何 build server。

   --check 真正在防的是這件事：選項字串在 JSON 改了一個字、SQL 規則沒跟著改，
   那條規則就從此永遠不會命中——不會報錯、不會有紅字，畫面上完全看不出來。 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'data/relationship-topics.json');
const OUT = join(ROOT, 'js/relationship-topics.js');
const SCHEMA = join(ROOT, 'supabase-schema.sql');

const data = JSON.parse(readFileSync(SRC, 'utf8'));

function render(d) {
  return `/* 自動產生，不要手改。來源：data/relationship-topics.json
   重新產生：node tools/gen-topics.mjs
   檢查有沒有漂移：node tools/gen-topics.mjs --check

   長期關係最容易磨損的八個生活場景。第二階段結構化問診、初診規則庫與
   AI 診療室共用這一份——選項字串就是規則庫比對的字面值，差一個字，
   那條規則會從此永遠不命中而且畫面上看不出來。 */
window.RELATIONSHIP_TOPICS = ${JSON.stringify(
    { version: d.version, importance_levels: d.importance_levels, topics: d.topics },
    null, 2
  )};
`;
}

/* 選項匯出成 SQL，給 tests/pgtest-topics.sql 拿去跟規則庫的最終狀態比對。 */
const lit = s => "'" + String(s).replace(/'/g, "''") + "'";
function renderOptSql(d) {
  const optRows = d.topics.flatMap(t =>
    t.fields.flatMap(f => f.opts.map(o => `(${lit(f.col)},${lit(o)})`)));
  const colRows = d.topics.flatMap(t =>
    t.fields.map(f => `(${lit(f.col)},${lit(t.topic)},${f.kind === 'multi'})`));
  return `-- 自動產生，不要手改。來源：data/relationship-topics.json
-- 重新產生：node tools/gen-topics.mjs
-- 由 tests/pgtest-topics.sql 載入，用來比對規則庫「最終狀態」實際比對的字串。
create temporary table topic_opts (col text, opt text);
insert into topic_opts (col, opt) values
  ${optRows.join(',\n  ')};
create temporary table topic_cols (col text, topic text, is_multi boolean);
insert into topic_cols (col, topic, is_multi) values
  ${colRows.join(',\n  ')};
`;
}

function check() {
  const problems = [];
  const cols = new Map();          // col -> Set(合法選項)
  const colMeta = new Map();       // col -> 欄位定義本身
  const seenTopic = new Set();
  for (const t of data.topics) {
    if (seenTopic.has(t.topic)) problems.push(`topic 重複：${t.topic}`);
    seenTopic.add(t.topic);
    for (const f of t.fields) {
      if (cols.has(f.col)) problems.push(`欄位重複出現在兩個題組：${f.col}`);
      cols.set(f.col, new Set(f.opts));
      colMeta.set(f.col, f);
    }
  }

  // ① 產生物有沒有跟來源漂移
  let current = '';
  try { current = readFileSync(OUT, 'utf8'); } catch { /* 還沒產生過 */ }
  if (current !== render(data))
    problems.push('js/relationship-topics.js 跟 data/relationship-topics.json 不一致，請跑 node tools/gen-topics.mjs');

  const sql = readFileSync(SCHEMA, 'utf8');

  // ② 每個欄位都要在 schema 裡宣告過（沒宣告的話規則讀到的永遠是 null）
  for (const col of cols.keys()) {
    const declared = new RegExp(
      `add column if not exists\\s+${col}\\s`, 'i').test(sql);
    if (!declared) problems.push(`欄位沒有在 schema 裡宣告：${col}`);
  }

  // ③ 每個欄位都要有一個「揭露決定」。
  //    get_visible_match_profiles() 是黑名單制，漏一個就是預設公開——這個坑踩過四次，
  //    所以改成由程式盯著：要嘛在黑名單裡，要嘛在 JSON 裡寫明 public:true 與理由。
  //    沒有第三種選項；忘了想就會被擋下來，而不是安靜地公開出去。
  const stripBlock = sql.match(/to_jsonb\(p\) - array\[([\s\S]*?)\]::text\[\]/);
  if (!stripBlock) problems.push('找不到遮罩黑名單，無法檢查欄位有沒有外流');
  else for (const [col, meta] of colMeta) {
    const masked = stripBlock[1].includes(`'${col}'`);
    if (meta.public && masked)
      problems.push(`宣告是公開欄位、卻又在遮罩黑名單裡，兩邊說法不一致：${col}`);
    if (!meta.public && !masked)
      problems.push(`欄位不在遮罩黑名單裡，等於第 0 層就公開：${col}`
        + '（真的要公開的話，請在 JSON 裡標 public:true 並寫出理由）');
    if (meta.public && !meta.public_reason)
      problems.push(`標了 public:true 但沒有寫理由：${col}`);
  }

  /* ④ 「規則比對的字串一定要是選項裡真的有的字」以及「每個欄位都要有規則在讀」
     這兩項不在這裡驗，在 tests/pgtest-topics.sql 上驗。

     原因：schema 是一份可以重跑的檔案，同一條規則會先在第 18 節建立、再被第 20
     或第 23 節改寫。靜態讀檔看到的是所有歷史版本，不是規則庫的最終狀態——
     拿舊版本去比對只會報一堆假警報，然後大家就開始忽略這支檢查。
     真正的最終狀態只有資料庫知道，所以那兩項改成在真的 Postgres 上跑。

     這裡負責把選項匯出成 SQL，讓那份測試讀得到。 */
  let currentOpts = '';
  try { currentOpts = readFileSync(join(ROOT, 'data/topic-options.sql'), 'utf8'); } catch { /* 還沒產生過 */ }
  if (currentOpts !== renderOptSql(data))
    problems.push('data/topic-options.sql 跟來源不一致，請跑 node tools/gen-topics.mjs');

  if (problems.length) {
    console.error('❌ 八個生活場景的資料來源有漂移：');
    problems.forEach(p => console.error('   ・' + p));
    process.exit(1);
  }
  console.log(`✅ ${data.topics.length} 個題組、${cols.size} 個欄位：`
    + '產生物、schema 欄位宣告、揭露決定都跟來源一致'
    + '（規則比對的字串在 tests/pgtest-topics.sql 上驗）');
}

if (process.argv.includes('--check')) check();
else {
  writeFileSync(OUT, render(data));
  writeFileSync(join(ROOT, 'data/topic-options.sql'), renderOptSql(data));
  console.log('已產生 js/relationship-topics.js 與 data/topic-options.sql');
}
