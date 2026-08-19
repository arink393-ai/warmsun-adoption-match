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
// ── 部署：不需要安裝 CLI ─────────────────────────────────
// 「supabase functions deploy」是 CLI 指令，沒裝 CLI 當然找不到。
// **在 Supabase 後台直接貼程式碼就可以了**，完整步驟寫在 README 第 46 節。
// 摘要：
//   1. Dashboard → Edge Functions → 建一支叫 notify-owner 的函式，
//      把這個檔案整份貼進去，Deploy。
//   2. **把這支函式的「Verify JWT」關掉。** 這是一定會踩到的坑：
//      平台預設會先驗 JWT，排程與 Webhook 帶的不是使用者 JWT，
//      會在我們自己的檢查跑到之前就被擋成 401。
//      關掉之後改由下面的 x-notify-secret 把關（所以那個一定要設）。
//   3. 設定 secrets（Edge Functions → Secrets）：
//        RESEND_API_KEY = re_xxxxx        （https://resend.com 免費申請）
//        NOTIFY_TO      = warmsun.shelter@gmail.com
//        NOTIFY_FROM    = 暖陽動物之家 <onboarding@resend.dev>
//        NOTIFY_SECRET  = 自己產一組亂數
//      NOTIFY_FROM 用 resend.dev 那個網域可以直接寄，不必先驗證自己的網域。
//      SUPABASE_URL 與 SUPABASE_SERVICE_ROLE_KEY 是平台自動注入的，不用自己設。
//   4. 讓它定時跑：Dashboard → Integrations → Cron，每 15 分鐘呼叫一次，
//      並在 HTTP headers 加上 x-notify-secret: <你設的那組>。
//      （也可以用 Database Webhooks 設成「owner_notifications 有 INSERT 就呼叫」，
//        那是即時的。這支函式每次都會把待寄的全部合成一封，所以不會重複寄。）
//
// ── 授權 ────────────────────────────────────────────────
// 這支函式用 service_role 讀寫 outbox，所以**不能讓任何人隨便呼叫**。
// 呼叫時必須帶 Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>，
// 或帶 x-notify-secret: <NOTIFY_SECRET>（自己設一組亂數）。
// 兩個都沒設對就直接 401。
// ⚠️ 把 Verify JWT 關掉之後，**這個檢查就是唯一的一道門**，NOTIFY_SECRET 不能不設。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const KIND_LABEL: Record<string, string> = {
  report: "🚨 檢舉",
  feedback: "💬 意見回饋",
  story: "💛 故事審核",
  photo_review: "📷 大頭照審核",
  verify_review: "🪪 身分驗證審核",
};

/* 每一個回應都要帶 CORS 標頭。
   第一版只在 OPTIONS 帶，正式回應沒帶——結果是用瀏覽器測的時候，
   函式其實跑成功了，瀏覽器卻把回應丟掉並報一個看起來像壞掉的 CORS 錯誤。
   把驗證擋在 x-notify-secret，開放 CORS 不會讓任何人多拿到東西。 */
const CORS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-notify-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: CORS });

/* 比對前兩邊都 trim。
   把密鑰貼進 Supabase 的 Secrets 欄位時很容易多帶一個換行或空白，
   而那種錯完全看不出來——畫面上兩串長得一模一樣，就是不相等。
   密鑰的前後空白不帶任何意義，直接吃掉比讓人查半天好。 */
const norm = (v: string | null) => (v ?? "").trim();

function authorized(req: Request): boolean {
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const secret = norm(Deno.env.get("NOTIFY_SECRET") ?? "");
  const auth = req.headers.get("Authorization") ?? "";
  const given = norm(req.headers.get("x-notify-secret"));
  /* 也接受 ?secret=... 。
     用途是**測試**：自訂標頭（x-notify-secret）會讓瀏覽器先送一個 OPTIONS 預檢，
     而預檢依規格不帶任何自訂標頭，卡在那裡的時候錯誤訊息會指向 CORS，
     跟真正的原因（授權）長得完全不一樣，很難查。
     用網址參數就不會有預檢，一次就知道函式到底活著沒有。
     ⚠️ 網址會進瀏覽器紀錄與伺服器 log，所以**排程請用標頭那一種**。 */
  const qs = norm(new URL(req.url).searchParams.get("secret"));
  if (svc && auth === `Bearer ${svc}`) return true;
  if (secret && (given === secret || qs === secret)) return true;
  return false;
}

/* 401 的時候回一點**不洩漏密鑰**的線索。
   只回「有沒有收到」「長度多少」「伺服器那邊有沒有設」——
   長度是呼叫端自己送的，本來就知道；設定與否是布林值。
   沒有這些，「我明明填了」跟「我根本沒送」看起來一模一樣。 */
function authDetail(req: Request) {
  const secret = Deno.env.get("NOTIFY_SECRET") ?? "";
  const header = norm(req.headers.get("x-notify-secret"));
  const qs = norm(new URL(req.url).searchParams.get("secret"));
  return {
    收到_x_notify_secret_標頭: header.length > 0,
    收到_secret_網址參數: qs.length > 0,
    你送出的長度: header.length || qs.length,
    伺服器有設定_NOTIFY_SECRET: secret.trim().length > 0,
    伺服器的值長度: secret.trim().length,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!authorized(req)) {
    /* 注意：看得到這一段就代表函式真的跑起來了，
       所以**不可能**是 Verify JWT 的問題——那會被閘道擋在這之前。
       第一版的 hint 把兩件事寫在一起，反而害人往錯的方向查。 */
    return reply({
      error: "unauthorized",
      hint: "密鑰沒對上。看得到這段訊息就代表函式本身是活的，跟 Verify JWT 無關。",
      診斷: authDetail(req),
    }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const to = Deno.env.get("NOTIFY_TO");
  const from = Deno.env.get("NOTIFY_FROM") ?? "暖陽動物之家 <onboarding@resend.dev>";
  const resend = Deno.env.get("RESEND_API_KEY");
  if (!url || !key) {
    return reply({ error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 沒設定" }, 500);
  }
  const sb = createClient(url, key);

  const { data: rows, error } = await sb.rpc("pending_owner_notifications", { p_limit: 50 });
  if (error) {
    return reply({ error: error.message,
      hint: "找不到 RPC 的話，代表最新的 supabase-schema.sql 還沒貼進 SQL Editor" }, 500);
  }
  const list = (rows ?? []) as Array<{
    id: string; kind: string; subject: string; body: string; created_at: string;
  }>;
  if (list.length === 0) {
    return reply({ sent: 0, note: "沒有待寄的通知（這也算成功：去網站送一則意見回饋再測一次）" });
  }

  // 沒設定寄信服務時不要把 outbox 標記成已寄出——
  // 標了就等於把那些通知永遠丟掉，而且沒有人會發現。
  if (!resend || !to) {
    return reply({ pending: list.length,
      error: "RESEND_API_KEY 或 NOTIFY_TO 沒設定，這幾筆先留著沒有寄出" }, 500);
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
    return reply({ error: "寄信失敗（Resend 退件）", detail: text.slice(0, 300) }, 502);
  }
  await sb.rpc("mark_owner_notifications_sent", { p_ids: ids });
  return reply({ sent: ids.length });
});
