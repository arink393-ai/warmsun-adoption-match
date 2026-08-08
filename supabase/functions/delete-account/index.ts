import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const origin = Deno.env.get("SITE_ORIGIN") || "https://arink393-ai.github.io";
  const headers = { "Access-Control-Allow-Origin": origin, "Access-Control-Allow-Headers": "authorization, content-type, apikey", "Content-Type": "application/json", "Vary": "Origin" };
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers });
  try {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data.user) return new Response(JSON.stringify({ error: "尚未登入" }), { status: 401, headers });
    const body = await req.json();
    if (body.confirm !== "DELETE") return new Response(JSON.stringify({ error: "缺少刪除確認" }), { status: 400, headers });
    const id = data.user.id;
    await Promise.all([
      admin.storage.from("avatars").remove([`${id}/avatar.jpg`]),
      admin.storage.from("verify").remove([`${id}/verify.jpg`]),
      admin.storage.from("stage-photos").remove([`${id}/stage1.jpg`, `${id}/stage2.jpg`]),
    ]);
    const deleted = await admin.auth.admin.deleteUser(id);
    if (deleted.error) throw deleted.error;
    return new Response(JSON.stringify({ ok: true }), { headers });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), { status: 500, headers });
  }
});
