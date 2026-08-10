# 主治醫師初診規則庫 ＋ 申請者 CRM｜資料規格 V1.0

這份文件只做三件事，不寫程式：

1. 定義 `screening_rules` / `screening_results` 的資料格式
2. 定義 CRM 狀態機（哪些是存的、哪些是算出來的）
3. 把 58 條規則逐條對到**現在資料庫裡真的存在的欄位**，指出哪些現在就能寫、哪些要先補欄位

結論先講：**58 條規則裡有 11 條現在就能實作，6 條是「禁止觸發」的原則（不用資料只要測試），
41 條要先補欄位。** 缺的欄位集中在四個題組（生活節奏、家庭與居住、關係結構、財務模式），
再加上一個貫穿全部的 **Dealbreaker 嚴重度**。詳見第 5、6 節。

---

## 1. 四個先決定的架構問題

這四點會影響後面所有設計，所以放在最前面。

### 1.1 初診必須在伺服器端跑，回傳只有燈號

初診要比對雙方的完整資料（含還沒揭露的收入、生育規劃、負債），但**這些值不能傳到前端**。
四層漸進式揭露是靠 `get_visible_match_profiles()` 在資料庫端把欄位打掉才成立的，如果初診
在前端算，等於把整套遮罩繞過去。

所以初診是一支 `security definer` 函式：

```
run_screening(p_from uuid, p_to uuid) → screening_results
```

它讀得到兩邊的原始資料，但**回傳值裡永遠不含對方的欄位值**，只有燈號、分類、理由碼與文案。

### 1.2 還沒提出申請時只給「數量」，申請之後才給細節

這是上一點的延伸，而且是很容易漏掉的洩漏路徑。假設佈告欄（第 0 層）就顯示

> 🔴 生育規劃存在不可妥協的差異

那等於在第 0 層洩漏了對方的 `kids_plan`——第 0 層本來連精確年齡都看不到。

所以初診結果分兩種呈現：

| 位置 | 揭露層級 | 看得到什麼 |
|---|---|---|
| 佈告欄卡片 | 第 0 層 | **只有數量**：🟢 8 項　🟡 3 項　🔴 1 項　⚪ 6 項 |
| 申請詳情（雙方已有申請關係） | 第 1 層以上 | 分類 ＋ 理由 ＋ 建議問診題 |
| 管理後台 CRM | 管理員 | 全部，含 🚨 |

第 0 層看到「🔴 1 項」仍然有價值——它告訴你「值得申請看看是什麼」或「先看別人」，但不會
告訴你那一項是什麼。每一條規則因此要標 `min_stage`（這條的細節最早可以在第幾層顯示），
預設等於它讀取的欄位裡**揭露層級最深的那一個**。

### 1.3 🚨 安全事件與一般初診完全分離

R056–R058 不能走同一條輸出管線：

- 🚨 **只寫進管理後台**，不進 `screening_results` 給會員看的那一份，也不影響任何燈號統計。
- 被檢舉的人**不會知道**自己被標記（跟現在封鎖不通知對方的設計一致）。
- 🚨 的效果是**提高人工審查優先順序**，不是自動處分。

技術上：`screening_results.audience` 欄位分 `member` / `admin`，RLS 只讓管理員讀 `admin` 那些。

### 1.4 Dealbreaker 嚴重度是獨立於「值」的一個維度

有 9 條規則寫著「🟡 或 🔴，依重要性設定」（R020、R025、R034、R044…），還有 8 條 🔴 規則
要求**雙方都標為不可妥協**才成立（R007、R009、R012、R018、R022、R027、R031、R039、R041、R042）。

這代表每個題目要存兩件事：**你的答案**，以及**這件事對你有多重要**。

現在資料庫完全沒有「重要度」這個維度——`req_marital` / `req_kids` / `req_habits` 只有值，
沒有強度。**沒有這個維度，58 條規則裡所有的 🔴 都做不出來**，只能全部降級成 🟡。

建議用一個 jsonb 欄位而不是新開一張表：

```sql
alter table public.match_profiles
  add column if not exists dealbreakers jsonb not null default '{}'::jsonb;
```

```json
{
  "kids_plan":            "non_negotiable",
  "marriage_intent":      "discussable",
  "relationship_structure":"non_negotiable",
  "partner_debt":         "none",
  "cohabit_with_parents": "discussable"
}
```

三個值：`none`（沒特別意見）／`discussable`（在意，可討論）／`non_negotiable`（不可妥協）。
key 用**題組代號**，跟規則裡的 `topic` 對得起來。預設全部 `none`——沒填就是沒意見，
不會憑空產生 🔴。

> 這一欄本身要不要公開？建議**不公開值、只公開有幾項**（「這個人有 3 項不可妥協條件」），
> 細項在第一階段後開放。理由跟 1.2 一樣。

---

## 2. `screening_rules` 資料格式

規則是**資料不是程式**——這樣加第 59 條規則不用改前端、不用重新部署，管理後台就能改文案。

```sql
create table if not exists public.screening_rules (
  code         text primary key,              -- 'R002'
  topic        text not null,                 -- 'work_hours'，對得到 dealbreakers 的 key
  category     text not null,                 -- 'workload' / 'family' / 'safety' …
  outcome      text not null                  -- 這條命中時的燈號
                 check (outcome in ('green','yellow','red','unknown','safety','never')),
  priority     smallint not null default 50,  -- 同色時的排序，小的排前面
  min_stage    smallint not null default 1,   -- 細節最早可以在第幾層顯示（見 1.2）
  audience     text not null default 'member' check (audience in ('member','admin')),
  cond         jsonb not null,                -- 條件式，見下
  escalate     jsonb,                         -- 升級成 red 的條件（「依重要性設定」用）
  requires     text[] not null default '{}',  -- 需要哪些欄位；缺一個就直接判 unknown
  reason_code  text,                          -- 'R_WORK_HOURS_HIGH'，接罐頭中心
  title        text not null default '',
  body         text not null default '',
  ask          jsonb not null default '[]'::jsonb,  -- 建議問診題
  enabled      boolean not null default true,
  updated_at   timestamptz default now()
);
```

### 條件式（`cond`）

刻意做得很小，只夠表達這 58 條，不做成通用運算式語言：

```jsonc
{ "all": [ ... ] }      // 全部成立
{ "any": [ ... ] }      // 任一成立
{ "not": { ... } }
{ "field": "<ref>", "op": "<op>", "value": <any> }
```

`<ref>` 的前綴固定三種：

| 前綴 | 意思 |
|---|---|
| `applicant.` | 申請人（`applications.from_user`） |
| `recipient.` | 收件人（`applications.to_user`） |
| `answers.` | 第一／二階段的回答（`application_answers`） |

`<op>`：`eq` `ne` `in` `not_in` `between` `gt` `gte` `lt` `lte` `is_null` `not_null`
`contains`（jsonb 陣列含某值）`same` `differs`（跟另一個 ref 比）。

R002 長這樣：

```json
{
  "code": "R002", "topic": "work_hours", "category": "workload",
  "outcome": "yellow", "priority": 20, "min_stage": 2,
  "cond": { "all": [
    { "field": "applicant.weekly_work_hours", "op": "between", "value": [60, 79] }
  ]},
  "requires": ["applicant.weekly_work_hours"],
  "reason_code": "R_WORK_HOURS_HIGH",
  "title": "工作時間較長",
  "body": "平日可安排的相處與休息時間可能較有限。",
  "ask": ["工作較忙的時期，你通常怎麼安排自己的休息與伴侶相處時間？"]
}
```

需要「雙方都不可妥協才 🔴」的 R012：

```json
{
  "code": "R012", "topic": "kids_plan", "category": "life_plan",
  "outcome": "red", "priority": 5, "min_stage": 2,
  "cond": { "all": [
    { "field": "applicant.kids_plan", "op": "in", "value": ["想要小孩"] },
    { "field": "recipient.kids_plan", "op": "in", "value": ["不想要小孩", "已有小孩，不打算再生"] },
    { "field": "applicant.dealbreakers.kids_plan", "op": "eq", "value": "non_negotiable" },
    { "field": "recipient.dealbreakers.kids_plan", "op": "eq", "value": "non_negotiable" }
  ]},
  "requires": ["applicant.kids_plan", "recipient.kids_plan"],
  "title": "雙方生育規劃存在不可妥協的差異"
}
```

「🟡／🔴 依重要性」的 R025 用 `escalate`：

```json
{
  "code": "R025", "topic": "partner_debt", "outcome": "yellow",
  "cond": { "all": [
    { "field": "recipient.req_partner_debt", "op": "eq", "value": "不接受伴侶有負債" },
    { "field": "applicant.debt", "op": "in", "value": ["有，可負擔範圍內", "有，目前壓力較大"] }
  ]},
  "escalate": { "field": "recipient.dealbreakers.partner_debt", "op": "eq", "value": "non_negotiable" }
}
```

### 兩條引擎層的硬規定

**（a）`requires` 缺任何一個欄位 → 直接判 `unknown`（⚪），不評估 `cond`。**
這樣才不會把「沒填」誤讀成「填了否定的值」。R001、R013、R021 這種 ⚪ 規則因此不用另外寫，
是引擎行為。

**（b）`outcome='never'` 是禁止規則。** R047–R054 存成 `never`，`cond` 寫明「這些欄位不得
產生燈號」。引擎啟動時檢查：**沒有任何 enabled 規則的 `cond`/`requires` 引用到禁止欄位**，
違反就拒絕啟動。這比寫在註解裡可靠——它讓 R047「MBTI 不產生黃燈」變成一個會擋下部署的斷言，
而不是一句大家都會忘記的約定。

禁止欄位清單：`mbti`、`height_cm`、`weight_kg`、`education`、`income`、`health`、
`health_tags`、以及 `age` 的直接相減。

---

## 3. `screening_results` 資料格式

```sql
create table if not exists public.screening_results (
  id          bigserial primary key,
  app_id      uuid references public.applications(id) on delete cascade,
  from_user   uuid not null,          -- 沒有 app 時（佈告欄預覽初診）也能算
  to_user     uuid not null,
  audience    text not null default 'member' check (audience in ('member','admin')),
  ran_at      timestamptz not null default now(),
  rules_ver   text not null default 'v1',
  inputs_seen smallint not null default 0,   -- 「目前取得 14 項有效資料」
  green       smallint not null default 0,
  yellow      smallint not null default 0,
  red         smallint not null default 0,
  unknown     smallint not null default 0,
  safety      smallint not null default 0,
  findings    jsonb not null default '[]'::jsonb,
  unique (app_id, audience)
);
```

`findings` 一筆：

```json
{
  "code": "R004", "topic": "work_hours", "outcome": "yellow",
  "min_stage": 2, "priority": 10,
  "title": "填寫的工作時間非常高",
  "body": "一週 120 小時，建議先確認是否包含待命、通勤、研究／準備時間，或僅為特殊期間。",
  "ask": ["120 小時的工作時數是平時常態，還是近期特殊狀況？"],
  "reason_code": "R_WORK_HOURS_EXTREME"
}
```

**快取策略**：初診是純函式（同樣的輸入永遠同樣的輸出），所以存結果、雙方任一方
`match_profiles.updated_at` 或 `application_answers` 變動就作廢重算。不需要排程。

**成本 NT$0**，所以「待初診」在 CRM 看板上永遠應該是 0——申請一送出就同步跑完。
那一格存在只是為了讓引擎壞掉時看得出來。

---

## 4. CRM 狀態機

### 4.1 原則：能算的就不要存

`applications` 現在已經有 `stage`(1/2/3)、`status`(open/rejected)、`stage2_paid`、
`unlock_from`、`unlock_to`。看板那九格裡有七格**完全可以從現有欄位算出來**，不需要新增
狀態欄位——多存一份就多一份不同步的風險。

| 看板 | 判定條件 | 需要新欄位？ |
|---|---|---|
| 📨 新申請 | `stage=1 ∧ open ∧ opened_at is null` | `opened_at` |
| 🩺 待初診 | `screening_results` 沒有這筆 | — |
| 📋 第一階段待審 | `stage=1 ∧ open ∧ opened_at not null` | `opened_at` |
| 💬 第二階段 | `stage=2 ∧ open` | — |
| 👀 日常觀察 | `stage=3 ∧ open ∧ ¬unlock_from ∧ ¬unlock_to` | — |
| ❤️ 等待雙向解鎖 | `stage=3 ∧ (unlock_from ⊕ unlock_to)` | — |
| 🌱 完成認養手續 | `stage=3 ∧ unlock_from ∧ unlock_to` | — |
| 💤 逾期 | `open ∧ now() - last_activity_at > 7d` | `last_activity_at` |
| 🏠 已婉拒／結案 | `status='rejected'` | `closed_reason` |

第二階段再細分三個子狀態（都算得出來，不用存）：
待出題 `¬stage2_paid` → 待作答 `stage2_paid ∧ answers.a2 is null` → 待審 `a2 not null`。

### 4.2 要新增的欄位（只有四個）

```sql
alter table public.applications
  add column if not exists opened_at        timestamptz,   -- 收件人第一次打開這份申請
  add column if not exists last_activity_at timestamptz,   -- 任一方最後一次動作（算逾期用）
  add column if not exists closed_reason    text,          -- 結案原因，見下
  add column if not exists crm_tags         jsonb not null default '[]'::jsonb;
```

`closed_reason` 建議的固定值：`declined_stage1` / `declined_stage2` / `declined_stage3` /
`withdrawn_by_applicant` / `expired` / `blocked` / `safety`。**這欄不給申請人看**——
「你在第幾階段被婉拒」對被拒的人沒有幫助，但對站方看漏斗很重要。RLS 要擋掉。

`crm_tags` 是志工自己貼的標籤（`["需補件","已電話確認"]`），不進規則引擎。

### 4.3 合法轉移

```
                    ┌──────────────────────────────► rejected（任何階段，任一方，隨時）
                    │
新申請 ──opened_at──► 第一階段待審 ──advance──► 第二階段 ──advance_stage3──► 日常觀察
                                                   │                          │
                                            send_stage2                 unlock_stage3
                                            submit_stage2               consent_unlock_to
                                                                              ▼
                                                                    雙方同意 → 完成
```

三個不變式，值得寫成資料庫層的 check 或 trigger：

1. **stage 只能往前，不能倒退**（現在沒有擋，`guard_application_privileged()` 可以加）
2. **`unlock_*` 只能由本人設，而且要帶 `p_safety_ack=true`**（已經做到了）
3. **`rejected` 是終態**——不能從 rejected 回到 open。要重新開始只能是新的一筆申請，
   但 `unique (from_user, to_user)` 會擋住。這是刻意的：被婉拒之後不能一直重送。

### 4.4 時間軸

看板跟時間軸都需要「什麼時候發生了什麼」，但現在只有 `created_at` / `updated_at`。

```sql
create table if not exists public.application_events (
  id        bigserial primary key,
  app_id    uuid not null references public.applications(id) on delete cascade,
  at        timestamptz not null default now(),
  actor     uuid,                    -- null = 系統
  kind      text not null,           -- 見下
  detail    jsonb not null default '{}'::jsonb
);
```

`kind`：`applied` `answered_1` `screened` `opened` `advanced_2` `sent_q2` `answered_2`
`advanced_3` `unlocked_from` `unlocked_to` `exchanged` `noted` `messaged` `declined`
`refunded` `priority_invite` `reported` `blocked`。

**全部由既有的 RPC 在成功之後寫入**（`apply_to`、`send_stage2`、`submit_stage2`、
`advance_stage3`、`unlock_stage3`、`consent_unlock_to`、`refund_application`…），
不要讓前端寫——前端寫的時間軸沒有稽核價值。

`last_activity_at` 就是 `max(at)`，可以用 trigger 同步回 `applications` 避免每次算。

### 4.5 志工筆記與罐頭

- 志工筆記：`application_private_notes` **已經存在**，直接用。
- 罐頭連動：`template_master` 現在只有 `id/name/text`，要加

```sql
alter table public.template_master
  add column if not exists reason_codes text[] not null default '{}',
  add column if not exists stage        smallint;
```

這樣「黃燈 → reason_code → 推薦罐頭」是一個 `where reason_codes && array[...]` 的查詢，
不用 AI，也不用寫死對照表。

---

## 5. 58 條規則 × 現有欄位對照

圖例：**✅ 現在就能做**｜**🟠 部分可做**（能出 🟡 但出不了 🔴，因為缺嚴重度）｜**❌ 缺欄位**｜**📏 禁止規則**

### A. 資料合理性（工時）

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R001 工時未填 ⚪ | `weekly_work_hours is null` | ❌ `work_hours` 是自由文字（`"例：45 小時"`），不能可靠解析 |
| R002 60–79 🟡 | 同上，數值 | ❌ 同上 |
| R003 80–99 🟡 | 同上 | ❌ |
| R004 ≥100 🟡高優先 | 同上 | ❌ |
| R005 >168 ⚪異常 | 同上 | ❌ |

> **缺 1 個欄位就解決 5 條規則**：`weekly_work_hours smallint`。
> 現有的 `work_hours text` 建議保留作顯示用（有人想寫「45（含通勤）」），
> 但規則只讀數值欄。這是投報率最高的一個欄位。

### B～E. 關係期待、婚姻、生育、已有孩子

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R006 關係方向不同 🟡 | `relationship_goal` 雙方 | 🟠 欄位有（4 選項），但缺「目前不尋找長期關係」這個選項 |
| R007 長期 vs 不找長期 🔴 | 上 ＋ 雙方 `dealbreakers.relationship_goal` | ❌ 缺選項＋缺嚴重度 |
| R008 婚姻期待不同 🟡 | **結婚意願** | ❌ `marital` 是婚姻**狀態**（未婚/離婚/喪偶），不是意願。完全沒有這個欄位 |
| R009 一定結婚 vs 終身不婚 🔴 | 上 ＋ 嚴重度 | ❌ |
| R010 想生 vs 未決定 🟡 | `kids_plan` 雙方 | ✅ 選項齊全（想要／不確定／不想要／已有不再生） |
| R011 不生 vs 未決定 🟡 | 同上 | ✅ |
| R012 一定要 vs 明確不生 🔴 | 上 ＋ 雙方嚴重度 | 🟠 值有了，缺嚴重度 |
| R013 有孩子＋對方未填接受度 ⚪ | `has_kids` ＋ `req_kids` | ✅ |
| R014 有孩子＋對方不接受 🔴 | 同上 | ✅ **唯一一條現在就完整可做的 🔴** |

### F. 寵物

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R015 有寵物＋對方未填 🟡 | `has_pets`、`pet_acceptance` | ❌ 兩個都不存在 |
| R016 寵物不可放棄 vs 無法共同生活 🔴 | 上 ＋ 嚴重度 | ❌ |

> 這裡有點諷刺：整個站用動物認養當比喻，卻沒有任何一個關於真實寵物的結構化欄位。
> `DEFAULT_Q1` 第三題「你能接受對方家裡有寵物，並一起照顧嗎？」是自由文字，規則讀不到。

### G～H. 居住與遠距

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R017 與父母同住 vs 希望獨立 🟡 | `living` ＋ `req_living` | 🟠 `living` 有，`req_living` 缺 |
| R018 婚後必須同住 vs 無法接受 🔴 | `cohabit_with_parents` 雙方 ＋ 嚴重度 | ❌ 「目前住哪」≠「婚後打算住哪」 |
| R019 跨城市但都能搬 🟢 | `area` ＋ `relocation` | 🟠 `area` 有，`relocation` 缺 |
| R020 跨城市且都不搬 🟡/🔴 | 同上 ＋ 嚴重度 | ❌ |
| R021 一方接受遠距一方未設 ⚪ | `long_distance_ok` | ❌ |
| R022 只能遠距 vs 不接受 🔴 | 同上 ＋ 嚴重度 | ❌ |

### I. 財務

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R023 收入差距 → 不觸發 | — | 📏 禁止規則，`income` 進禁止清單 |
| R024 有負債 → 單獨不觸發 | — | 📏 禁止規則 |
| R025 對方不接受負債 🟡/🔴 | `debt` ＋ `req_partner_debt` ＋ 嚴重度 | 🟠 `debt` 有（三選項），`req_partner_debt` 缺 |
| R026 雙方都要財務獨立 🟢 | `finance_style` | ❌ |
| R027 完全共同 vs 完全獨立 🔴 | 同上 ＋ 雙方嚴重度 | ❌ |

### J～L. 作息、聯絡頻率、獨處

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R028 早睡 vs 夜貓 → 不自動黃燈 | — | 📏 |
| R029 作息差＋都要固定陪伴 🟡 | `chronotype` ＋ `daily_together_need` | ❌ `stars.routine`（作息規律 1–5）不等於早鳥／夜貓 |
| R030 每天 vs 幾天一次 🟡 | `contact_frequency` | ❌ |
| R031 每天是必要 vs 不希望每日 🔴 | 同上 ＋ 嚴重度 | ❌ |
| R032 高獨處 vs 高陪伴 🟡 | `alone_time_need` | 🟠 可用現有 `stars.indep`（獨立程度 1–5）近似：一方 ≥4、另一方 ≤2 → 🟡。**建議先這樣做**，之後再補專門欄位 |

### M～O. 社交、家務、原生家庭

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R033 聚會頻率差異 → 不觸發 | — | 📏 |
| R034 常帶朋友回家 vs 不接受 🟡/🔴 | `guests_at_home` ＋ `req_guests` | ❌ |
| R035 家務期待差異 🟡 | `housework_split` | ❌ |
| R036 性別分工 vs 必須平等 🔴 | `housework_gendered` ＋ 嚴重度 | ❌ |
| R037 回家頻率差異 → 不自動黃燈 | — | 📏 |
| R038 期待每週參與 vs 不願 🟡 | `family_visit_freq` ＋ `req_family_involvement` | ❌ |
| R039 父母參與重大決策 vs 必須獨立 🔴 | `parents_in_decisions` ＋ 雙方嚴重度 | ❌ |

### P～R. 宗教、關係結構、前任

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R040 宗教不同 → 不觸發 | — | 📏 |
| R041 要求改宗 vs 不願 🔴 | `religion`、`req_conversion`、`conversion_ok` ＋ 嚴重度 | ❌ |
| R042 單偶 vs 開放式 🔴 | `relationship_structure` ＋ 雙方嚴重度 | ❌ |
| R043 與前任有聯繫 → 不自動黃燈 | — | 📏 |
| R044 每天密切互動＋對方列紅線 🟡/🔴 | `ex_contact_freq` ＋ `req_ex_contact` | ❌ **建議不要做成表單欄位**——這題沒有人會誠實填。留給第二階段題庫與付費 AI 語意分析 |

### S. 衝突節奏

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R045 當下處理 vs 需要冷靜 🟡 | `conflict_style` | ❌ 有自由文字題（`DEFAULT_Q1` 第 4 題），規則讀不到 |
| R046 都接受「告知後暫停」🟢 | 同上，需要一個**專屬選項** | ❌ |

> R046 的選項一定要獨立存在，不能跟「需要冷靜」合併：
> 「**我會先說一聲再暫停，之後回來處理**」跟冷暴力是相反的東西，而 `taboo` 欄位裡最常出現的
> 就是「冷暴力」。把這兩者混在一起，等於用一條規則去指控一個人。

### T. 不作為風險評分（📏 全部是禁止規則）

| 規則 | 內容 | 現況 |
|---|---|---|
| R047 | MBTI 不產生黃燈 | 📏 `mbti` 進禁止清單 |
| R048 | 身高差異不產生黃燈 | 📏 `height_cm` |
| R049 | 體重／BMI 不產生黃燈 | 📏 `weight_kg` |
| R050 | 學歷差距不產生黃燈 | 📏 `education` |
| R051 | 收入高低不產生黃燈 | 📏 `income` |
| R052 | 年齡差本身不產生黃燈 | 📏 `age` 直接相減禁止；只檢查 `req_age_min/max`（✅ 欄位已有） |

這六條不需要任何新欄位，實作成第 2 節（b）的啟動檢查 ＋ 一個「餵進極端輸入也不能亮燈」的測試。

### U. 健康資料

| 規則 | 內容 | 現況 |
|---|---|---|
| R053 | 疾病不得自動亮黃燈 | 📏 `health`、`health_tags` 進禁止清單 |
| R054 | 健康資料不得降低匹配度 | 📏 同上 |
| R055 | 本人選擇在第二階段說明 → ⚪ | ✅ 可從既有 `health_when='stage2'` ＋ `health` 非空推導，**不用新欄位** |

> R055 有一個必須補的限制：這個 ⚪ **只能在使用者自己選的階段之後才出現**。
> 如果第 0 層就顯示「有一項本人希望在適當階段說明的資訊」，等於在對方選擇揭露之前
> 就先昭告「這個人有健康的事」——那正是 R053/R054 想避免的貼標籤。
> 所以這條的 `min_stage` 必須跟著 `health_when` 動，不是固定值。

### V. 安全（全部 `audience='admin'`）

| 規則 | 需要的輸入 | 現況 |
|---|---|---|
| R056 暴力／恐嚇／騷擾檢舉 🚨 | `reports` | ✅ 表已存在（`target_id`/`by_id`/`why`/`done`） |
| R057 多位互不相關會員檢舉相似行為 🚨 | `reports` 聚合 ＋ 檢舉人之間無關聯 | 🟠 可做，但要先定義「互不相關」（建議：彼此沒有申請關係、沒有互相封鎖）。另外 `why` 是自由文字，要分類得加 `reports.category` |
| R058 自由文字偵測 ⚪ | `bio`、`wants`、`taboo`、`answers` | ✅ 欄位都在 |

> R058 最重要的是輸出**只能是 ⚪ 而且只進管理後台**。
> 「我無法接受冷暴力」和「我生氣就會冷暴力」在關鍵字比對下完全一樣——
> 規則引擎不該分辨，也不該假裝分辨得出來。它只負責把這筆排到人工前面。

---

## 6. 缺的欄位總表

### 6.1 第一優先：一個欄位換五條規則

| 欄位 | 型別 | 放在登記表哪裡 | 解鎖 |
|---|---|---|---|
| `weekly_work_hours` | `smallint` | 第 4 步（已有 `work_hours` 文字欄旁邊） | R001–R005 |

### 6.2 第二優先：Dealbreaker 嚴重度

| 欄位 | 型別 | 位置 | 解鎖 |
|---|---|---|---|
| `dealbreakers` | `jsonb` | 第 5 步「希望遇到誰」，每個題組一個三選一 | **所有 🔴（10 條）＋ 9 條「依重要性」** |

沒有這個，58 條規則最多只能做到「全部黃燈」，而全部黃燈等於沒有分級。

### 6.3 第三優先：四個新題組

每個題組 3–5 題，都是單選，加起來約 16 個欄位：

**① 生活節奏**（R029–R032、R045、R046）
`chronotype`、`contact_frequency`、`daily_together_need`、`alone_time_need`、`conflict_style`

**② 家庭與居住**（R017–R022、R038、R039）
`relocation`、`long_distance_ok`、`cohabit_with_parents`、`req_living`、
`family_visit_freq`、`req_family_involvement`、`parents_in_decisions`

**③ 關係結構與人生規劃**（R006–R009、R042）
`marriage_intent`、`relationship_structure`、`relationship_goal` 增加一個選項

**④ 財務模式與寵物**（R015、R016、R025–R027）
`finance_style`、`req_partner_debt`、`has_pets`、`pet_acceptance`

### 6.4 建議不要做成表單欄位

| 規則 | 原因 |
|---|---|
| R034 帶朋友回家 | 頻率沒有人估得準，且很少是真的分手原因 |
| R035 / R036 家務 | 表單上人人都選「平均分攤」。放第二階段情境題，交給 AI 讀落差 |
| R041 宗教改宗 | 極少數案例，但問卷上出現會讓所有人不舒服。留給自由文字 |
| R044 前任聯繫 | 沒有人會誠實填 |

這四條先留在規則庫裡但 `enabled=false`，等第二階段題庫有結構化答案再打開。

### 6.5 登記表會變多長？

現在五步精靈已經有四十幾個欄位，再加 16 個是真的問題。建議：

- 新題組**全部選填**，全部預設「沒特別意見」
- 不放進第 4 步，另開**第 6 步「你的不可妥協」**，而且**明確標示可以跳過**
- 跳過的代價要說清楚：「跳過的話，主治醫師初診只能給你 ⚪ 資料不足，看不出核心衝突」
- **完整度不計入送審必填**——初診是給你的服務，不是你欠站方的作業

---

## 6.6 已完成：第 1、2 步

| # | 內容 | 狀態 |
|---|---|---|
| 1 | `weekly_work_hours` ＋ 兩張表 ＋ 引擎 ＋ 14 條規則 | ✅ 已實作 |
| 2 | 禁止規則 R047–R054 ＋ 檢查 ＋ 測試 | ✅ 已實作 |

實作時跟規格有三處出入，都是實作過程中發現規格想得不夠細：

**（a）禁止清單改成從資料推導，不是寫死。** 規格說「引擎啟動時檢查」，但 Postgres 沒有
「啟動」這件事。改成兩層：`screening_rules` 上的 trigger 在**寫入當下**就擋掉違規規則
（比啟動時檢查更早），`run_screening()` 每次執行前再掃一次整張表（萬一有人把 trigger 停掉）。
而且禁止清單是 `select ... where outcome='never'` 推出來的——**新增一條禁止規則就自動生效**，
R047–R054 因此是會 load-bearing 的資料，不是文件。

**（b）`screening_subject()` 當第二道防線。** 引擎讀不到完整的病歷卡，只讀得到一個
白名單過的 jsonb。學歷、收入、身高、體重、MBTI、健康告知內容**根本不在裡面**，
就算有人寫了引用它們的規則也只會拿到 null。健康只交出 `has_health_note`（布林）與
`health_when`（本人選的時機）。

**（c）`ran_at` 用 `clock_timestamp()` 不是 `now()`。** `now()` 是交易開始時間，
同一個交易裡永遠不前進，那樣「這份報告是什麼時候跑的」就分辨不出來，快取失效也驗不出來。

還有一個實作時才發現、規格沒寫到的坑：**新欄位會從佈告欄漏出去**。
`get_visible_match_profiles()` 是用 `to_jsonb(p) - array[...]` 做遮罩的——
黑名單制，所以**任何新加的欄位預設都是公開的**。`weekly_work_hours` 是第 2 層資料，
但因為沒列進黑名單，第 0 層就讀得到；`dealbreakers` 同理。兩個都補上了，
`dealbreakers` 完全不外流，只給 `dealbreaker_count`。
以後每加一個欄位都要問一次「它該在第幾層」。

## 6.7 已完成：第 3 步（CRM 時間軸與看板欄位）

| # | 內容 | 狀態 |
|---|---|---|
| 3 | `application_events` ＋ `opened_at`／`last_activity_at`／`closed_reason`／`crm_tags` | ✅ 已實作 |

跟規格的出入，同樣都是實作時才發現規格想得不夠細：

**（a）事件用 trigger 記，不是「既有的 RPC 在成功之後寫入」。**
規格原本寫要在九支 RPC 裡各補一行。實作時發現**婉拒根本不走 RPC**——它是前端直接對
`applications` 下 `update`（RLS 只開放給收件方）。靠 RPC 補寫會整條漏掉婉拒，
而婉拒正是漏斗上最需要記錄的一步。改成資料庫 trigger 之後，連「有人繞過前端直接改資料」
都記得到，稽核價值才成立。

**（b）`last_activity_at` 必須在 INSERT 時就設。**
規格只說它是「任一方最後一次動作」，實作第一版只在 UPDATE 時維護，結果新申請的
`last_activity_at` 是 null，而「逾期」的查詢是 `last_activity_at < now() - 7 天`——
null 永遠不會命中。也就是**最該被看到的那種申請（送出後三週沒人理）反而不會出現在逾期格**。
測試抓到的。

**（c）`closed_reason` 不需要另外遮，但要規定它能存什麼。**
規格說「這欄不給申請人看，RLS 要擋掉」。實際上 Postgres 沒辦法做欄位級的 RLS，
而且仔細想，`declined_stage1` 沒有洩漏任何新資訊——申請人本來就看得到自己的 `stage`
和 `status='rejected'`。所以改成：**這一欄只存申請人本來就知道的事**，由 trigger 自動填；
真正敏感的封鎖與安全事件**絕對不可以**寫進來（那會讓被封鎖的人推論出是誰封鎖了他），
一律走 `visibility='admin'` 的事件。

**（d）`mark_applications_opened()` 收一個陣列。**
收件匣一次顯示很多封，一封打一次 RPC 在「124 封申請一個志工」的情境下就是 124 次往返。

**（e）RLS 之外還要 GRANT。**
`application_events` 建好、RLS policy 也寫好，但沒有 `grant select ... to authenticated`，
結果是 `permission denied for table`——連自己那幾列都讀不到。RLS 決定「哪些列」，
GRANT 決定「能不能碰這張表」，兩個都要給。（`screening_results` 則刻意兩個都不給。）

**「打開」目前的語意。** 收件匣是把每一封的完整回答直接攤開顯示的，所以「畫出來」就等於
「志工看過了」，`mark_applications_opened()` 在收件匣渲染完之後送出一批。等第 4 步的 CRM
看板做出來（點進去才看得到內容的清單），這個呼叫就會搬到「點進某一封」的時候。

## 7. 建議的實作順序

| # | 做什麼 | 為什麼排這裡 |
|---|---|---|
| 1 | `weekly_work_hours` ＋ `screening_rules`/`screening_results` 兩張表 ＋ 引擎 ＋ R001–R005、R013、R014、R010、R011、R055 | 11 條規則、1 個新欄位，就能端出一份真的初診報告 |
| 2 | 禁止規則（R047–R054）＋ 啟動檢查 ＋ 測試 | 不用資料，但定義了系統的價值觀，愈早鎖愈好 |
| 3 | `application_events` ＋ 既有 RPC 補寫事件 ＋ `opened_at`/`last_activity_at`/`closed_reason` | CRM 看板與時間軸的前提；跟規則引擎互不相依，可以並行 |
| 4 | CRM 看板（九格 ＋ 五個快篩）＋ 申請者病例七區塊 | 這一步就能解決「一百多封申請一個志工」 |
| 5 | `dealbreakers` 欄位 ＋ 第 6 步表單 | 有了它，🔴 才存在 |
| 6 | 四個新題組 ＋ 其餘 41 條規則 | 純資料建置，可以分批 |
| 7 | `template_master.reason_codes` ＋ 罐頭推薦 | 要先有 reason_code 才有東西可以接 |
| 8 | R056–R058 安全規則進管理後台 | 需要先有 `reports.category` |
| 9 | 付費 AI 層改成讀初診結果（黃燈 → 客製問診、回答矛盾分析） | AI 的輸入品質取決於初診，所以放最後 |

**第 1、2 步做完就有可以上線的東西**：一份免費、API 成本 NT$0、看得出「這個人的工時是
120 小時而且你要求對方沒有小孩但他有」的初診報告。剩下的都是往上疊。

---

## 8. 兩個要一起改掉的舊東西

1. **README 目前還寫著 AI 會直接產生匹配百分比**。免費初診上線之後，這句要改成
   「免費：規則式初診／付費：AI 深度診療」。
2. **`applications.vet_scores`** 現在存的是 `{stage1, stage2, stage3, confidence}` 的分數。
   改版之後 AI 不該再輸出分數，而是輸出觀察與建議確認的問題。這欄要嘛改語意、要嘛廢掉——
   留著一個「62%」在資料庫裡，遲早有人把它畫回畫面上。
