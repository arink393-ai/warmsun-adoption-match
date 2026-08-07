// ============================================================
// 暖陽動物之家｜共用 Supabase 存取層
// 給 index.html（公開配對站）與 dashboard.html（個人後台）共用。
// 需要先載入：
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="js/config.js"></script>
//   <script src="js/supabase-client.js"></script>
// ============================================================
(function () {
  if (!window.supabase || !window.SUPABASE_URL) {
    console.error('Supabase 尚未載入，請確認 config.js 與 supabase-js CDN 都有引入');
    return;
  }
  const sb = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);

  // ── Auth ──────────────────────────────────────────────
  async function signUpEmail(email, password, name) {
    const { data, error } = await sb.auth.signUp({
      email, password, options: { data: { name: name || '' } }
    });
    if (error) throw error;
    return data;
  }
  async function signInEmail(email, password) {
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  }
  async function signInGoogle() {
    const { data, error } = await sb.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin + window.location.pathname }
    });
    if (error) throw error;
    return data;
  }
  async function signOut() {
    const { error } = await sb.auth.signOut();
    if (error) throw error;
  }
  async function getUser() {
    const { data } = await sb.auth.getUser();
    return data ? data.user : null;
  }
  function onAuthChange(cb) {
    sb.auth.onAuthStateChange((_event, session) => cb(session ? session.user : null));
  }

  // ── Profiles ──────────────────────────────────────────
  async function ensureProfile() {
    const user = await getUser();
    if (!user) return null;
    let { data, error } = await sb.from('profiles').select('*').eq('id', user.id).maybeSingle();
    if (error) throw error;
    if (!data) {
      const ins = await sb.from('profiles').insert({ id: user.id }).select().single();
      if (ins.error) throw ins.error;
      data = ins.data;
    }
    return data;
  }
  async function getMyProfile() {
    const user = await getUser();
    if (!user) return null;
    const { data, error } = await sb.from('profiles').select('*').eq('id', user.id).maybeSingle();
    if (error) throw error;
    return data;
  }
  async function saveMyProfile(patch) {
    const user = await getUser();
    if (!user) throw new Error('尚未登入');
    const { data, error } = await sb.from('profiles')
      .update(patch).eq('id', user.id).select().single();
    if (error) throw error;
    return data;
  }
  async function getProfile(id) {
    const { data, error } = await sb.from('profiles').select('*').eq('id', id).maybeSingle();
    if (error) throw error;
    return data;
  }
  // 管理員專用：更新別人的那一筆（審核通過/退回、發獎勵點數）。
  // 非管理員呼叫這個會被 RLS 擋下來，不會真的改到別人的資料。
  async function adminUpdateProfile(id, patch) {
    const { data, error } = await sb.from('profiles')
      .update(patch).eq('id', id).select().single();
    if (error) throw error;
    return data;
  }
  // 管理員專用：列出所有待審核（照片或驗證照還沒通過）的登記
  async function adminListPending() {
    const { data, error } = await sb.from('profiles').select('*')
      .or('photo_status.eq.checking,photo_status.eq.pending,verify_status.eq.pending')
      .order('updated_at', { ascending: true });
    if (error) throw error;
    return data || [];
  }
  // 管理員專用：列出所有登記（全站統計用）
  async function adminListAllProfiles() {
    const { data, error } = await sb.from('profiles').select('*');
    if (error) throw error;
    return data || [];
  }
  // 管理員專用：列出所有申請（全站統計用）
  async function adminListAllApplications() {
    const { data, error } = await sb.from('applications').select('*');
    if (error) throw error;
    return data || [];
  }
  // 管理員專用：移除違規登記，並清掉這個人牽涉的所有申請
  async function adminRemoveProfile(id) {
    const del1 = await sb.from('applications').delete()
      .or(`from_user.eq.${id},to_user.eq.${id}`);
    if (del1.error) throw del1.error;
    const del2 = await sb.from('profiles').delete().eq('id', id);
    if (del2.error) throw del2.error;
  }

  // ── 診療點數（模擬付費，用來限流 AI 呼叫） ──
  async function spendCredit(amount, why) {
    const p = await getMyProfile();
    if (!p || p.credits < amount) return { ok: false, profile: p };
    const log = (Array.isArray(p.credit_log) ? p.credit_log.slice() : []);
    log.unshift({ at: new Date().toISOString(), t: why, d: -amount });
    const profile = await saveMyProfile({ credits: p.credits - amount, credit_log: log.slice(0, 50) });
    return { ok: true, profile };
  }
  async function topupCredit(amount, why) {
    const p = await getMyProfile();
    const log = (Array.isArray(p.credit_log) ? p.credit_log.slice() : []);
    log.unshift({ at: new Date().toISOString(), t: why, d: amount });
    return await saveMyProfile({ credits: (p.credits || 0) + amount, credit_log: log.slice(0, 50) });
  }
  async function listProfiles() {
    const user = await getUser();
    const { data, error } = await sb.from('profiles').select('*')
      .neq('id', user ? user.id : '00000000-0000-0000-0000-000000000000')
      .order('updated_at', { ascending: false });
    if (error) throw error;
    // 只列出已經完成登記的人（kind/species/name 都有填）
    return (data || []).filter(p => p.kind && p.species && p.name);
  }

  // ── Applications ──────────────────────────────────────
  async function listOutbox() {
    const user = await getUser();
    const { data, error } = await sb.from('applications').select('*')
      .eq('from_user', user.id).order('updated_at', { ascending: false });
    if (error) throw error;
    return data || [];
  }
  async function listInbox() {
    const user = await getUser();
    const { data, error } = await sb.from('applications').select('*')
      .eq('to_user', user.id).order('updated_at', { ascending: false });
    if (error) throw error;
    return data || [];
  }
  async function findApplicationTo(toId) {
    const user = await getUser();
    const { data, error } = await sb.from('applications').select('*')
      .eq('from_user', user.id).eq('to_user', toId).maybeSingle();
    if (error) throw error;
    return data;
  }
  async function createApplication(toId, a1, extra) {
    const user = await getUser();
    const { data, error } = await sb.from('applications').insert(Object.assign({
      from_user: user.id, to_user: toId, stage: 1, status: 'open', a1
    }, extra || {})).select().single();
    if (error) throw error;
    return data;
  }
  async function updateApplication(id, patch) {
    const { data, error } = await sb.from('applications')
      .update(patch).eq('id', id).select().single();
    if (error) throw error;
    return data;
  }

  // ── AI 輔助評分／照片初審（選用，需部署 supabase/functions/claude） ──
  function hasClaudeProxy() {
    return !!window.CLAUDE_PROXY_URL;
  }
  async function askClaudeRaw(messages, opts) {
    if (!window.CLAUDE_PROXY_URL) throw new Error('尚未設定 AI 代理網址（js/config.js 的 CLAUDE_PROXY_URL）');
    const { data: { session } } = await sb.auth.getSession();
    if (!session) throw new Error('尚未登入');
    const res = await fetch(window.CLAUDE_PROXY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + session.access_token },
      body: JSON.stringify(Object.assign({ model: 'claude-sonnet-5', max_tokens: 700, messages }, opts || {}))
    });
    const data = await res.json();
    if (!res.ok) throw new Error((data.error && data.error.message) || 'AI 請求失敗');
    const text = data.content && data.content[0] && data.content[0].text;
    if (!text) throw new Error('AI 沒有回傳內容');
    return text;
  }
  async function askClaude(prompt) {
    return askClaudeRaw([{ role: 'user', content: prompt }]);
  }

  // ── Storage：大頭照（公開）／驗證照（私密，審核完即刪） ──
  function dataUrlToBlob(dataUrl) {
    const [head, b64] = dataUrl.split(',');
    const mime = (head.match(/data:(.*);base64/) || [])[1] || 'image/jpeg';
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new Blob([bytes], { type: mime });
  }
  function avatarUrl(userId, cacheBust) {
    const base = `${window.SUPABASE_URL}/storage/v1/object/public/avatars/${userId}/avatar.jpg`;
    return cacheBust ? `${base}?t=${encodeURIComponent(cacheBust)}` : base;
  }
  async function uploadAvatar(dataUrl) {
    const user = await getUser();
    if (!user) throw new Error('尚未登入');
    const path = `${user.id}/avatar.jpg`;
    const { error } = await sb.storage.from('avatars')
      .upload(path, dataUrlToBlob(dataUrl), { upsert: true, contentType: 'image/jpeg' });
    if (error) throw error;
    return avatarUrl(user.id, Date.now());
  }
  async function uploadVerifyPhoto(dataUrl) {
    const user = await getUser();
    if (!user) throw new Error('尚未登入');
    const path = `${user.id}/verify.jpg`;
    const { error } = await sb.storage.from('verify')
      .upload(path, dataUrlToBlob(dataUrl), { upsert: true, contentType: 'image/jpeg' });
    if (error) throw error;
    return path;
  }
  async function getVerifySignedUrl(userId) {
    const { data, error } = await sb.storage.from('verify')
      .createSignedUrl(`${userId}/verify.jpg`, 120);
    if (error) throw error;
    return data.signedUrl;
  }
  async function deleteVerifyPhoto(userId) {
    const { error } = await sb.storage.from('verify').remove([`${userId}/verify.jpg`]);
    if (error) throw error;
  }

  // ── 檢舉 ──────────────────────────────────────────────
  async function submitReport(targetId, why) {
    const user = await getUser();
    if (!user) throw new Error('尚未登入');
    const { error } = await sb.from('reports').insert({ target_id: targetId, by_id: user.id, why });
    if (error) throw error;
  }
  async function adminListReports() {
    const { data, error } = await sb.from('reports').select('*').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
  }
  async function adminMarkReportDone(id) {
    const { error } = await sb.from('reports').update({ done: true }).eq('id', id);
    if (error) throw error;
  }

  // ── 罐頭回覆範本（所有會員都有一份，預設值來自 template_master） ──
  async function getTemplateMaster() {
    const { data, error } = await sb.from('template_master').select('*').order('id');
    if (error) throw error;
    return data || [];
  }
  async function adminSaveTemplateMaster(id, text) {
    const { error } = await sb.from('template_master').update({ text }).eq('id', id);
    if (error) throw error;
  }

  // ── owner_kv：私人工具（暖陽動物之家回覆助手）專用儲存 ──
  async function ownerKvGet(key) {
    const user = await getUser();
    if (!user) return null;
    const { data, error } = await sb.from('owner_kv').select('v')
      .eq('owner_id', user.id).eq('k', key).maybeSingle();
    if (error) throw error;
    return data ? { key, value: data.v } : null;
  }
  async function ownerKvSet(key, value) {
    const user = await getUser();
    if (!user) throw new Error('尚未登入');
    const { error } = await sb.from('owner_kv')
      .upsert({ owner_id: user.id, k: key, v: String(value) }, { onConflict: 'owner_id,k' });
    if (error) throw error;
    return { key, value };
  }
  async function ownerKvDelete(key) {
    const user = await getUser();
    if (!user) return;
    const { error } = await sb.from('owner_kv').delete().eq('owner_id', user.id).eq('k', key);
    if (error) throw error;
  }

  window.DB = {
    sb,
    signUpEmail, signInEmail, signInGoogle, signOut, getUser, onAuthChange,
    ensureProfile, getMyProfile, saveMyProfile, getProfile, listProfiles,
    adminUpdateProfile, adminListPending, adminListAllProfiles, adminListAllApplications, adminRemoveProfile,
    listOutbox, listInbox, findApplicationTo, createApplication, updateApplication,
    hasClaudeProxy, askClaude, askClaudeRaw, spendCredit, topupCredit,
    avatarUrl, uploadAvatar, uploadVerifyPhoto, getVerifySignedUrl, deleteVerifyPhoto,
    submitReport, adminListReports, adminMarkReportDone,
    getTemplateMaster, adminSaveTemplateMaster,
    ownerKvGet, ownerKvSet, ownerKvDelete
  };
})();
