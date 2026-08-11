// 暖陽動物之家 · 待審通知寄信（Supabase Edge Function）
//
// 它做的事只有一件：把 public.owner_notifications 裡還沒寄出的那幾筆，
// 合併成一封信寄到站方信箱，然後標記成已寄出。
//
// ── 為什麼是這個形狀 ──────────────────────────────────────
// 資料庫端只負責「記下有這件事要通知」（schema 第 35 節的 outbox），
// 真正寄信在這裡。所以**這支函式沒部署、或寄信服務掛掉，網站一樣完全正常**，
// 只是 owner_notifications 的 pending 會累積，而管理後台看得到那個數字。
//
// ── 部署 ────────────────────────────────────────────────
// 1. supabase functions deploy notify-owner
// 2. 設定三個 secret（RESEND_API_KEY 到 https://resend.com 免費申請）：
//      supabase secrets set RESEND_API_KEY=re_xxxxx
//      supabase secrets set NOTIFY_TO=warmsun.shelter@gmail.com
//      supabase secrets set NOTIFY_FROM="暖陽動物之家 <onboarding@resend.dev>"
//    （NOTIFY_FROM 用 resend.dev 那個網域可以直接寄，不必先驗證自己的網域；
//      之後有自己的網域再換掉。）
// 3. 讓它定時跑。兩種都可以，選一種：
//    (a) Supabase Dashboard → Integrations → Cron
//        新增一個排程，每 15 分鐘呼叫這支函式一次。
//    (b) 任何外部排程（例如 GitHub Actions 的 schedule）去 POST 這個網址。
//    沒有排程的話，也可以在 Database Webhooks 設定成
//    「owner_notifications 有 INSERT 就呼叫這支函式」——那是即時的，
//    但每一筆一封信，量大時會很吵。建議用排程，一次寄一封摘要。
//
// ── 授權 ────────────────────────────────────────────────
// 這支函式用 service_role 讀寫 outbox，所以**不能讓任何人隨便呼叫**。
// 呼叫時必須帶 Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>，
// 或帶 x-notify-secret: <NOTIFY_SECRET>（自己設一組亂數）。
// 兩個都沒設對就直接 401。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const KIND_LABEL: Record<string, string> = {
  report: "🚨 檢舉",
  feedback: "💬 意見回饋",
  story: "💛 故事審核",
  photo_review: "📷 大頭照審核",
  verify_review: "🪪 身分驗證審核",
};

function authorized(req: Request): boolean {
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const secret = Deno.env.get("NOTIFY_SECRET") ?? "";
  const auth = req.headers.get("Authorization") ?? "";
  const given = req.headers.get("x-notify-secret") ?? "";
  if (svc && auth === `Bearer ${svc}`) return true;
  if (secret && given === secret) return true;
  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type, x-notify-secret",
      },
    });
  }
  if (!authorized(req)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const to = Deno.env.get("NOTIFY_TO");
  const from = Deno.env.get("NOTIFY_FROM") ?? "暖陽動物之家 <onboarding@resend.dev>";
  const resend = Deno.env.get("RESEND_API_KEY");
  if (!url || !key) {
    return new Response(JSON.stringify({ error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 沒設定" }),
      { status: 500, headers: { "Content-Type": "application/json" } });
  }
  const sb = createClient(url, key);

  const { data: rows, error } = await sb.rpc("pending_owner_notifications", { p_limit: 50 });
  if (error) {
    return new Response(JSON.stringify({ error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } });
  }
  const list = (rows ?? []) as Array<{
    id: string; kind: string; subject: string; body: string; created_at: string;
  }>;
  if (list.length === 0) {
    return new Response(JSON.stringify({ sent: 0, note: "沒有待寄的通知" }),
      { headers: { "Content-Type": "application/json" } });
  }

  // 沒設定寄信服務時不要把 outbox 標記成已寄出——
  // 標了就等於把那些通知永遠丟掉，而且沒有人會發現。
  if (!resend || !to) {
    return new Response(JSON.stringify({
      pending: list.length,
      error: "RESEND_API_KEY 或 NOTIFY_TO 沒設定，這幾筆先留著沒有寄出",
    }), { status: 500, headers: { "Content-Type": "application/json" } });
  }

  const byKind = new Map<string, typeof list>();
  for (const n of list) {
    if (!byKind.has(n.kind)) byKind.set(n.kind, [] as typeof list);
    byKind.get(n.kind)!.push(n);
  }
  const esc = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const sections = [...byKind.entries()].map(([kind, items]) =>
    `<h3 style="font-size:15px;margin:18px 0 6px">${KIND_LABEL[kind] ?? kind}（${items.length}）</h3>`
    + items.map((n) =>
      `<div style="border-left:2px solid #A06F24;padding:2px 0 2px 10px;margin:8px 0">
         <div><b>${esc(n.subject)}</b></div>
         ${n.body ? `<div style="color:#555;white-space:pre-wrap">${esc(n.body)}</div>` : ""}
         <div style="color:#888;font-size:12px">${new Date(n.created_at).toLocaleString("zh-TW")}</div>
       </div>`).join("")).join("");

  const subject = `暖陽動物之家：${list.length} 件待處理`;
  const html = `<div style="font-family:system-ui,sans-serif;line-height:1.7;color:#222">
      <p>目前有 <b>${list.length}</b> 件事情等著處理。到管理後台看：</p>
      ${sections}
      <p style="color:#888;font-size:12px;margin-top:20px">
        這封信是自動寄的。檢舉的處理時效是 3 個工作日。</p>
    </div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${resend}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: [to], subject, html }),
  });
  const ids = list.map((n) => n.id);
  if (!res.ok) {
    const text = await res.text();
    // 失敗就記下來並累加 attempts，不標記成已寄出（第 5 次之後就不再重試）
    await sb.rpc("mark_owner_notifications_failed", { p_ids: ids, p_error: text.slice(0, 500) });
    return new Response(JSON.stringify({ error: "寄信失敗", detail: text.slice(0, 300) }),
      { status: 502, headers: { "Content-Type": "application/json" } });
  }
  await sb.rpc("mark_owner_notifications_sent", { p_ids: ids });
  return new Response(JSON.stringify({ sent: ids.length }),
    { headers: { "Content-Type": "application/json" } });
});
