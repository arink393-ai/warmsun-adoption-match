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
    // 一併把事件名稱交給頁面：TOKEN_REFRESHED 不該被當成一次新的登入導頁。
    sb.auth.onAuthStateChange((event, session) => cb(session ? session.user : null, event));
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

  // ── 診療點數：一律透過 Postgres 安全函式，前端連 SQL 都下不了（見 supabase-schema.sql 第 9 節） ──
  // p_action 對應資料庫 spend_credits_for() 裡的 case 分支；金額由伺服器決定，前端不能傳金額。
  async function spendCreditFor(action, detail) {
    const { data, error } = await sb.rpc('spend_credits_for', { p_action: action, p_detail: detail || null });
    if (error) return { ok: false, profile: await getMyProfile(), error };
    return { ok: true, profile: data };
  }
  // 提出認養申請：扣掛號費＋建立申請＋寫入受保護的答案表＋存進答題紀錄，同一個交易（見 apply_to()）
  async function applyTo(toId, answers, questions) {
    const { data, error } = await sb.rpc('apply_to', {
      p_to: toId, p_answers: answers, p_questions: questions || []
    });
    if (error) throw error;
    return data;
  }
  // 退回逾期未處理的掛號費：伺服器自己重新驗證天數／歸屬／是否已退過
  async function refundApplication(appId) {
    const { data, error } = await sb.rpc('refund_application', { p_app_id: appId });
    if (error) throw error;
    return data;
  }
  // 管理員專用：手動加點（人工儲值、活動贈點）。ref 給未來接金流回調用（訂單編號防重複加點）。
  async function adminAddCredits(targetId, amount, reason, ref) {
    const { data, error } = await sb.rpc('admin_add_credits', { target: targetId, amount, reason, ref: ref || null });
    if (error) throw error;
    return data;
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
  // 回答存在受保護的 application_answers（收件方付費解鎖後才讀得到，見 schema 第 10 節）。
  // 這裡一併撈出來攤平成 a.a1 / a.a2，畫面端就跟以前一樣用；沒解鎖時 RLS 會讓它是 null。
  const APP_SELECT = '*, application_answers(a1,a2)';
  function flattenApp(row) {
    if (!row) return row;
    const raw = row.application_answers;
    const ans = Array.isArray(raw) ? raw[0] : raw;
    row.a1 = ans ? ans.a1 : null;
    row.a2 = ans ? ans.a2 : null;
    delete row.application_answers;
    return row;
  }
  async function listOutbox() {
    const user = await getUser();
    const { data, error } = await sb.from('applications').select(APP_SELECT)
      .eq('from_user', user.id).order('updated_at', { ascending: false });
    if (error) throw error;
    return (data || []).map(flattenApp);
  }
  async function listInbox() {
    const user = await getUser();
    const { data, error } = await sb.from('applications').select(APP_SELECT)
      .eq('to_user', user.id).order('updated_at', { ascending: false });
    if (error) throw error;
    return (data || []).map(flattenApp);
  }
  async function findApplicationTo(toId) {
    const user = await getUser();
    const { data, error } = await sb.from('applications').select(APP_SELECT)
      .eq('from_user', user.id).eq('to_user', toId).maybeSingle();
    if (error) throw error;
    return flattenApp(data);
  }
  async function updateApplication(id, patch) {
    const { data, error } = await sb.from('applications')
      .update(patch).eq('id', id).select(APP_SELECT).single();
    if (error) throw error;
    return flattenApp(data);
  }
  // 收件方付費解鎖第一階段詳細回答（1 點，價格由伺服器決定）
  async function unlockA1(appId) {
    const { data, error } = await sb.rpc('unlock_a1', { p_app_id: appId });
    if (error) throw error;
    return data;
  }
  // 收件方付費發出第二階段問卷（2 點），同時把申請推進到第二階段
  async function sendStage2(appId, questions) {
    const { data, error } = await sb.rpc('send_stage2', { p_app_id: appId, p_questions: questions });
    if (error) throw error;
    return data;
  }
  // 申請人送出第二階段回答（一併存進自己的答題紀錄）
  async function submitStage2(appId, answers, questions) {
    const { data, error } = await sb.rpc('submit_stage2', {
      p_app_id: appId, p_answers: answers, p_questions: questions || []
    });
    if (error) throw error;
    return data;
  }
  // 通過第二階段、進入第三階段（不收費，但一樣由伺服器驗證）
  async function advanceStage3(appId) {
    const { data, error } = await sb.rpc('advance_stage3', { p_app_id: appId });
    if (error) throw error;
    return data;
  }
  // 第三階段：申請人付 3 點解鎖對方的日常觀察資訊
  async function unlockStage3(appId) {
    const { data, error } = await sb.rpc('unlock_stage3', { p_app_id: appId });
    if (error) throw error;
    return data;
  }
  // 第三階段：收件方免費同意解鎖
  async function consentUnlockTo(appId) {
    const { data, error } = await sb.rpc('consent_unlock_to', { p_app_id: appId });
    if (error) throw error;
    return data;
  }
  // 一鍵通關：對方開放的話，付 10 點直接跳到第三階段互相解鎖
  async function skipToUnlock(appId) {
    const { data, error } = await sb.rpc('skip_to_unlock', { p_app_id: appId });
    if (error) throw error;
    return data;
  }
  // 收回逾期未花完的一鍵通關獎勵點數（登入後呼叫一次，best-effort）
  async function settleBonusCredits() {
    try { await sb.rpc('settle_bonus_credits'); } catch (e) { /* 沒有的話就算了，不影響登入 */ }
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

  // ── 加碼照片（第一階段口罩照/側拍照、第二階段生活照）：私密 bucket，
  //    能不能讀由 storage policy 依申請進度判斷，這裡只負責上傳與拿簽名網址 ──
  async function uploadStagePhoto(stage, dataUrl) {
    const user = await getUser();
    if (!user) throw new Error('尚未登入');
    const path = `${user.id}/stage${stage}.jpg`;
    const { error } = await sb.storage.from('stage-photos')
      .upload(path, dataUrlToBlob(dataUrl), { upsert: true, contentType: 'image/jpeg' });
    if (error) throw error;
    return path;
  }
  async function getStagePhotoSignedUrl(ownerId, stage) {
    const { data, error } = await sb.storage.from('stage-photos')
      .createSignedUrl(`${ownerId}/stage${stage}.jpg`, 120);
    if (error) throw error;
    return data.signedUrl;
  }

  // ── 申請人的私人筆記（獨立資料表，只有寫的人讀得到，對方查不到） ──
  async function getPrivateNote(appId) {
    const { data, error } = await sb.from('application_private_notes')
      .select('note').eq('application_id', appId).maybeSingle();
    if (error) throw error;
    return data ? data.note : '';
  }
  async function savePrivateNote(appId, note) {
    const user = await getUser();
    if (!user) throw new Error('尚未登入');
    const { error } = await sb.from('application_private_notes')
      .upsert({ application_id: appId, owner_id: user.id, note }, { onConflict: 'application_id' });
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
    listOutbox, listInbox, findApplicationTo, updateApplication,
    applyTo, refundApplication, adminAddCredits,
    unlockA1, sendStage2, submitStage2, advanceStage3, unlockStage3, consentUnlockTo,
    skipToUnlock, settleBonusCredits,
    getPrivateNote, savePrivateNote,
    hasClaudeProxy, askClaude, askClaudeRaw, spendCreditFor,
    avatarUrl, uploadAvatar, uploadVerifyPhoto, getVerifySignedUrl, deleteVerifyPhoto,
    uploadStagePhoto, getStagePhotoSignedUrl,
    submitReport, adminListReports, adminMarkReportDone,
    getTemplateMaster, adminSaveTemplateMaster,
    ownerKvGet, ownerKvSet, ownerKvDelete
  };
})();
