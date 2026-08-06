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

  // ── AI 輔助評分（選用，需部署 supabase/functions/claude） ──
  function hasClaudeProxy() {
    return !!window.CLAUDE_PROXY_URL;
  }
  async function askClaude(prompt) {
    if (!window.CLAUDE_PROXY_URL) throw new Error('尚未設定 AI 代理網址（js/config.js 的 CLAUDE_PROXY_URL）');
    const { data: { session } } = await sb.auth.getSession();
    if (!session) throw new Error('尚未登入');
    const res = await fetch(window.CLAUDE_PROXY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + session.access_token },
      body: JSON.stringify({
        model: 'claude-sonnet-5',
        max_tokens: 700,
        messages: [{ role: 'user', content: prompt }]
      })
    });
    const data = await res.json();
    if (!res.ok) throw new Error((data.error && data.error.message) || 'AI 請求失敗');
    const text = data.content && data.content[0] && data.content[0].text;
    if (!text) throw new Error('AI 沒有回傳內容');
    return text;
  }

  window.DB = {
    sb,
    signUpEmail, signInEmail, signInGoogle, signOut, getUser, onAuthChange,
    ensureProfile, getMyProfile, saveMyProfile, getProfile, listProfiles,
    listOutbox, listInbox, findApplicationTo, createApplication, updateApplication,
    hasClaudeProxy, askClaude, spendCredit, topupCredit
  };
})();
