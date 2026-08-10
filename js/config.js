// ============================================================
// 暖陽動物之家｜Supabase 連線設定
//
// 1. 到你的 Supabase 專案 → Project Settings → API
// 2. 把「Project URL」貼到 SUPABASE_URL
// 3. 把「anon public」金鑰貼到 SUPABASE_ANON_KEY
//
// 這個檔案會被瀏覽器直接讀到，anon 金鑰本來就設計成可以公開，
// 真正的資料保護是 supabase-schema.sql 裡開的 RLS（沒登入者
// 一律進不去），不是靠隱藏這組金鑰。
// ============================================================
window.SUPABASE_URL = 'https://qjtthtqrqzrccxlgipdd.supabase.co';
window.SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFqdHRodHFycXpyY2N4bGdpcGRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5MTE2ODMsImV4cCI6MjA5ODQ4NzY4M30.lh56gBDzFlv4FKsgtqSKA9PZwwPQPf5zCom3FVX5dfQ';

// ============================================================
// （選用）AI 輔助評分代理網址
//
// 部署 supabase/functions/claude/index.ts 之後，把函式網址貼在這裡，
// 例如：https://YOUR-PROJECT.supabase.co/functions/v1/claude
// 留空 = 停用「AI 建議評分」功能，其他功能不受影響。
// ============================================================
window.CLAUDE_PROXY_URL = 'https://qjtthtqrqzrccxlgipdd.supabase.co/functions/v1/claude';

// ============================================================
// 站長本人的帳號 email
//
// 只有這個帳號看得到、進得去 shelter-review-assistant.html（私人工具）。
// 這裡是唯一的定義處——index.html 與 shelter-review-assistant.html 都讀這一行。
//
// 以前這個常數同時寫在那兩個 HTML 裡，README 還得提醒「兩邊記得改一致」。
// 需要提醒的設定就是不該存在兩份的設定：改了一邊忘了另一邊，結果是
// 「首頁看得到連結、點進去卻被擋」或反過來，而且完全沒有錯誤訊息。
//
// 沒設這一行的話，兩個頁面都會「關門」（連結不顯示、工具進不去），
// 不會退回任何預設值——猜錯帳號等於把門開給別人。
// ============================================================
window.OWNER_EMAIL = 'warmsun.shelter@gmail.com';
