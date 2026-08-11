#!/usr/bin/env node
// supabase-schema.sql 的靜態檢查
//
// 只檢查一件事，但那一件事很難用別的方式抓到：
//   **同一個 constraint 名稱不可以在檔案裡被定義兩次。**
//
// 為什麼：整份 schema 是設計成可以重複貼的（README 一直寫「重貼一次即可」）。
// 如果一個 check 的允許值清單在第 24 節寫一份、第 30 節又寫一份，
// 而前面那份比較窄，會發生這件事：
//   ・第一次貼 → 完全正常（第 30 節那份最後生效）
//   ・第二次貼 → 第 24 節那份把清單改窄，而第 30 節上一輪插進去的資料違反它 → 23514
// 症狀是「第二次貼才炸」，錯誤訊息只說「某些列違反約束」，
// 完全看不出是兩個地方各定義了一份。
//
// 這個檢查在真的跑資料庫之前就會擋下來，跑法：
//   node tools/check-schema.mjs

import { readFileSync } from 'node:fs';

const file = 'supabase-schema.sql';
const src = readFileSync(new URL('../' + file, import.meta.url), 'utf8');

const lines = src.split('\n');
const seen = new Map();          // name -> [行號…]
const re = /^\s*alter\s+table\s+\S+\s+add\s+constraint\s+([a-z0-9_]+)/i;

lines.forEach((line, i) => {
  const m = line.match(re);
  if (!m) return;
  const name = m[1];
  if (!seen.has(name)) seen.set(name, []);
  seen.get(name).push(i + 1);
});

const dupes = [...seen.entries()].filter(([, at]) => at.length > 1);
if (dupes.length) {
  console.error('❌ 同一個 constraint 被定義了不只一次：\n');
  for (const [name, at] of dupes) {
    console.error(`   ${name}`);
    for (const n of at) console.error(`     ${file}:${n}  ${lines[n - 1].trim()}`);
    console.error('');
  }
  console.error('   把它們合併成一份（放在最早出現的那一節），後面的章節只寫 insert。');
  console.error('   兩份並存的話，整份 schema 貼第二次就會炸——而第一次完全正常。\n');
  process.exit(1);
}

console.log(`✅ ${seen.size} 個 constraint，每一個都只有一個定義處`
  + '（整份 schema 可以重複貼）');
