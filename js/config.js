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
window.SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
window.SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';
