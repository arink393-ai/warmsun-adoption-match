// 暖陽動物之家 · Claude API 代理（Supabase Edge Function）
//
// 為什麼需要它：Anthropic 的 API 金鑰不能放在網頁原始碼裡，
// 任何人打開瀏覽器開發者工具都看得到，會被拿去盜刷你的額度。
// 這支函式跑在 Supabase 的伺服器上，金鑰只存在那裡；前端只能
// 帶著自己的登入身分來呼叫，未登入者一律被拒絕。
//
// 部署步驟：
// 1. 安裝 Supabase CLI，在專案根目錄執行：
//      supabase functions deploy claude
//    （這個檔案已經放在 supabase/functions/claude/index.ts）
// 2. 設定金鑰（到 https://console.anthropic.com 取得）：
//      supabase secrets set ANTHROPIC_API_KEY=sk-ant-xxxxx
// 3. 把函式網址填進 js/config.js 的 CLAUDE_PROXY_URL：
//      https://<你的專案代號>.supabase.co/functions/v1/claude
//    留空則前端的「AI 建議評分」按鈕會自動停用，不影響其他功能。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",           // 上線後建議改成你的網域
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // ── 只有登入過的使用者可以呼叫，避免被別人白嫖額度 ──
    const auth = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: auth } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: { message: "尚未登入" } }), {
        status: 401,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: body.model ?? "claude-sonnet-5",
        max_tokens: Math.min(body.max_tokens ?? 1000, 2000),
        messages: body.messages ?? [],
      }),
    });

    const data = await res.json();
    return new Response(JSON.stringify(data), {
      status: res.status,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: { message: String(e) } }), {
      status: 500,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
