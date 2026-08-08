import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigin = Deno.env.get("SITE_ORIGIN") ?? "https://arink393-ai.github.io";
const cors = (req: Request) => ({
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(req), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json(req, { error: "尚未登入" }, 401);

    const actor = authData.user;
    const { data: actorProfile } = await admin.from("match_profiles")
      .select("is_admin,account_status").eq("id", actor.id).maybeSingle();
    if (!actorProfile?.is_admin || actorProfile.account_status !== "active") {
      return json(req, { error: "需要管理員權限" }, 403);
    }

    const { action, user_id: userId, reason = "" } = await req.json();
    if (!userId || userId === actor.id) return json(req, { error: "不可對自己的管理員帳號執行此操作" }, 400);
    if (!String(reason).trim() && !["restore", "posting_unlock"].includes(action)) {
      return json(req, { error: "請填寫處理原因" }, 400);
    }

    if (action === "posting_lock" || action === "posting_unlock") {
      const locked = action === "posting_lock";
      const { error } = await admin.from("match_profiles").update({
        posting_locked: locked,
        moderation_reason: locked ? String(reason).slice(0, 500) : "",
        moderated_at: new Date().toISOString(), moderated_by: actor.id,
      }).eq("id", userId);
      if (error) throw error;
    } else if (action === "suspend") {
      const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: "876000h" });
      if (error) throw error;
      await admin.from("match_profiles").update({ account_status: "suspended", posting_locked: true,
        moderation_reason: String(reason).slice(0, 500), moderated_at: new Date().toISOString(), moderated_by: actor.id }).eq("id", userId);
    } else if (action === "restore") {
      const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: "none" });
      if (error) throw error;
      await admin.from("match_profiles").update({ account_status: "active", posting_locked: false,
        moderation_reason: "", moderated_at: new Date().toISOString(), moderated_by: actor.id }).eq("id", userId);
    } else if (action === "delete") {
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) throw error;
    } else {
      return json(req, { error: "不支援的管理操作" }, 400);
    }

    await admin.from("match_moderation_actions").insert({
      actor_id: actor.id, target_id: userId, action, reason: String(reason).slice(0, 500),
    });
    return json(req, { ok: true });
  } catch (error) {
    return json(req, { error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
