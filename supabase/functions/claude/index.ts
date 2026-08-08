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

function cors(req: Request) {
  const configured = Deno.env.get("SITE_ORIGIN") ?? "";
  return {
    "Access-Control-Allow-Origin": configured || req.headers.get("Origin") || "null",
    "Access-Control-Allow-Headers": "authorization, content-type, apikey",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

Deno.serve(async (req) => {
  const CORS = cors(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: CORS });

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

    const service = createClient(
      Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data: profile } = await service.from("match_profiles")
      .select("account_status,posting_locked").eq("id", user.id).maybeSingle();
    if (!profile || profile.account_status !== "active" || profile.posting_locked) {
      return new Response(JSON.stringify({ error: { message: "你的 AI 使用權限目前受限" } }), {
        status: 403, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count } = await service.from("match_ai_requests").select("id", { count: "exact", head: true })
      .eq("user_id", user.id).gte("created_at", since);
    if ((count ?? 0) >= 20) {
      return new Response(JSON.stringify({ error: { message: "AI 使用次數已達每小時上限，請稍後再試" } }), {
        status: 429, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    if (!Array.isArray(body.messages) || JSON.stringify(body.messages).length > 30000) {
      return new Response(JSON.stringify({ error: { message: "請求內容不合法或過長" } }), {
        status: 400, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    await service.from("match_ai_requests").insert({ user_id: user.id });

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5",
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
