# 知数 · FinSight — Data Model

> 文档角色：核心数据模型与数据语义真相源  
> 版本：v1.0  
> 更新日期：2026-08-21  
> 状态：Active  
> 注意：本文强调“业务语义与边界”，具体 Swift 字段名、optional 状态与 schema version 以代码仓库为最终依据。

---

## 1. 数据模型总原则

FinSight 的数据分为三类：

### A. 用户财务事实

用户真实发生或确认的数据：

```text
Transaction
Account
Debt
RepaymentPlan
Bill（产品 / Domain 目标 — 当前未实现 persisted entity）
Asset
Goal
Budget
```

### B. 确定性计算结果

根据事实由 Domain Engine 计算：

```text
FinancialSummary
CashFlowProjection
CashFlowRisk
DebtCenterSummary
DebtPressure
FinancialRiskAssessment
PurchaseScenario
```

### C. AI Transport / Presentation

用于 AI 输入、AI 输出与 UI 展示：

```text
FinancialAssistantContextDTO
AssistantRequestDTO
ModelAssistantAnswerDraftDTO
AssistantAnswerDraft
AssistantAnswer
FinancialInsight（persisted validated snapshot）
CashFlowPresentation
```

**C 类模型不得反向污染 A 类事实模型。**

---

## 2. Transaction

### 角色

`Transaction` 是 FinSight 最底层、最重要的财务事实之一。

### 典型语义

- amount
- direction / type
  - income
  - expense
  - transfer（若实现）
  - repayment（也可能通过 category / relation 表达）
- occurredAt
- account
- category
- merchant / counterparty（可选）
- note（可选）
- source
- createdAt / updatedAt

### 来源

- screenshot import
- manual input
- statement import
- debt repayment discovery
- future supported source

### 规则

1. AI 识别结果不是 Transaction 本身。
2. AI Draft 必须经过用户确认 / 合法化后才能成为 Transaction。
3. 删除或修改 Transaction 后，相关 summary / cash flow 应重新计算。
4. 发送给远程 AI 时，不应默认携带 merchant / note / internal ID。

---

## 3. Imported Transaction Draft

截图识别阶段应有独立的 Draft 概念。

```text
Screenshot
   ↓
Recognition
   ↓
ImportedTransactionDraft
   ↓
User Confirm
   ↓
Transaction
```

Draft 可能包含：

- detected amount
- detected direction
- detected merchant
- detected date
- detected category
- confidence
- source image reference（短期）
- warnings

原则：

**识别结果可以错，账本事实不能未经确认地“假装正确”。**

---

## 4. Account

### 角色

表示用户的资金容器与可用资金来源。

### 可能类型

- cash
- bank
- wallet
- investment / asset-like
- credit-related（需谨慎与 Debt 去重）

### 核心字段语义

- name
- type
- balance
- currencyCode（中国 MVP 主要 CNY）
- archived
- safeBalance
- metadata

### 计算边界

`availableFunds` 等汇总不应在 UI 直接相加。

应通过 Domain Engine / Summary Service 统一计算。

历史上下文中，availableFunds 仅考虑符合条件的非 archived 资产类账户。

---

## 5. Debt

### 角色

表示用户对外承担的一项持续债务。

Debt 不是 Transaction。

Transaction 描述：

> 一笔钱发生了什么。

Debt 描述：

> 用户当前还欠什么，以及未来需要承担什么。

### 关键字段语义

- creditor / lender
- productName
- debtType
- outstandingBalance
- currentAmountDue
- minimumPayment
- plannedPayment
- dueDate
- statementDate
- interest / fee（已知时）
- status
- dataState / completeness
- source

### source 可能包括

- screenshot
- PDF / statement
- AI inferred draft
- user input
- transaction discovery
- future official synchronization

---

## 6. DebtDataState / 数据完整性

FinSight 的债务设计必须允许“不完整但有用”。

建议语义：

```text
knownNoDebt
knownDebt
partial
missing
```

或代码中等价的 Domain 状态。

### knownNoDebt

已经完成足够范围的债务建立流程，当前已知无债务。

### knownDebt

已有一项或多项可用债务记录，关键数据完整度达到要求。

### partial

知道用户存在债务，但：

- 余额未知
- 本期应还未知
- 到期日未知
- 仅识别部分平台

### missing

无法对债务状况作可靠判断。

该状态必须影响：

- Risk Assessment
- AI confidence
- unknowns
- UI 提示

不能把 missing 当成“0 债务”。

---

## 7. RepaymentPlan

表示未来债务还款结构。

可能包含：

- debt reference
- scheduled amount
- due date
- minimum payment
- planned payment
- recurrence / installment
- status

CashFlowEngine 应将已知未来还款纳入预测。

---

## 8. Bill

> **Implementation status（2026-08-19）：`PRODUCT / DOMAIN TARGET — NOT CURRENTLY IMPLEMENTED`**

Bill 用于表达债务 / 信用产品的 **某一期账单**（产品 / Domain 目标语义）。

可能包含（目标模型）：

- debt reference
- billing period
- statement date
- due date
- current amount due
- minimum payment
- bill status
- source

Debt 是长期对象；Bill 是周期对象。

### 当前仓库真实状态

- **Persisted `Bill` Domain Entity：不存在。**
- **`BillDocument`**：存在于 `ValueObjects/`，是 **扫描 / import 输入 VO**，不是 persisted Bill。
- **当前真实债务相关 persisted 实现：`Debt` + `RepaymentPlan`**（及 DebtEvent / 相关 facts）。

不要删除未来 Bill 产品设计；只明确 **current implementation status**。

---

## 9. Debt Event / Repayment Transaction

还款动作可能同时影响：

```text
Transaction
Debt outstandingBalance
RepaymentPlan status
```

（`Bill status` 属于未来 Bill 实体目标；当前未实现 persisted Bill。）

因此必须由 Domain Service 保证一致性。

典型黄金账本思路：

```text
初始资金 10000
支出 2000
债务 5000
还款 1000
↓
可用资金 7000
债务余额 4000
```

避免出现：

- 账户扣了钱但债务没下降
- 债务下降但没有现金流影响
- 还款在支出中被重复计算

---

## 10. FinancialSummary

由 `FinancialSummaryEngine` 产生。

典型当前月指标：

- income
- expense
- repayment
- net
- availableFunds
- asset / debt overview

FinancialSummary 是派生值。

不能作为 AI 自由计算对象。

---

## 11. CashFlowProjection

核心窗口：

```text
7d
30d
60d
90d
```

可能包含：

- horizon
- startBalance
- endingBalance
- minimumBalance
- minimumBalanceDate
- inflows
- outflows
- debtPayments
- risk
- drivers

### 输入事实

```text
当前可用资金
+ 已知未来收入
- 固定支出
- 债务还款
- 已知计划支出
```

### 规则

- Forecast 是确定性 Engine 结果。
- AI 只能解释已有 projection。
- Home 可持有多 horizon。
- Assistant Context 可以只映射任务需要的 horizon，例如 30 天。

---

## 12. CashFlowRisk

描述预测现金流的风险，而不是自由文本。

可能字段：

- level
- primaryRisk
- date
- minimumBalance
- drivers
- reasonCode

UI 可以把它映射成：

```text
CashFlowPresentation
```

Presentation 只负责格式化，不重新判断风险。

---

## 13. FinancialContext

这是 Domain 层面向“财务理解”的聚合对象。

它可以包含：

- current month summary
- accounts
- debts
- debt pressure
- cashFlow30
- budgets
- goals
- assets
- completeness
- primaryPressure
- hasDebts

重要：

**FinancialContext ≠ AI Request DTO。**

完整 FinancialContext 可以用于本地逻辑。

发送远程 AI 前必须映射。

---

## 14. FactPack

FactPack 的作用是建立：

> AI 文案中的每个关键事实究竟从哪里来。

可能存在：

- `AnswerFactPack`
- `InsightFactPack`
- `MonthlySummaryFacts`

### 允许金额集合

如果 Provider 输出：

```text
“你的安全余额是 ¥2000”
```

那么 `2000` 必须可以追溯到：

- FactPack.amounts
- 合法 key fact
- deterministic source

否则 Validator 应拒绝。

---

## 14.1 FinancialInsight（Persisted Snapshot）

### 角色

`FinancialInsight` 是 **persisted Domain snapshot**，用于 Home AI 摘要 cache 与 AI 页主动洞察历史列表。

它不是 untrusted Provider transport DTO，也不是完整的 structured `AssistantAnswer`。

### Production AI-created insight 链路（2026-08-20 — trust boundary VERIFIED SAFE）

```text
Provider Draft
→ AssistantAnswerValidator
→ validated content（title / body 等）
→ FinancialInsight
→ JSON Store（YoushuSnapshot.insights）
```

Proactive insight 另由 deterministic `InsightFactPack` 提供 fact 来源，AI 仅润色表述；写入前同样经 Validator。

### 当前持久化字段（flattened validated content）

- `type`（`summary` / `cashFlow` / `debtRisk` / `spendingPattern` / `actionSuggestion`）
- `title`
- `body`（含 disclaimer / unknowns 等 composed 文本）
- `sourceTransactionIds` / `sourceDebtIds` / `sourceAccountIds`（proactive 路径；monthly summary 当前常为空）
- `modelName`
- `generatedAt` / `createdAt`
- `freshnessMetadata: FinancialInsightFreshnessMetadata?`（monthly summary 路径；optional）

### FinancialInsightFreshnessMetadata（ADR-032）

Monthly summary 可选择性携带 freshness provenance：

- `schemaVersion` — freshness metadata schema version
- `policyVersion` — `FinancialRiskAssessment.policyVersion` at write time
- `digest` — opaque SHA-256 over canonical freshness input

`digest` 是 **opaque SHA-256**。原始 canonical source token 为 **transient only**，**不会持久化**。

Freshness 输入基于 deterministic：

```text
MonthlySummaryFacts
+
FinancialRiskAssessment
+
policyVersion
```

**不包含：** AI body/title、`generatedAt`、Consent 状态、UUID、merchant/note、原始截图。

Freshness metadata 属于 **C 类 persisted snapshot metadata**，**不是** A 类 financial fact；不得成为核心财务计算的事实输入。

### Compatibility

`freshnessMetadata` 是 optional。legacy summary 没有 metadata 时：

- 仍然是 **合法 stored history**
- **不能证明 current freshness** → Home current **cache miss**

Proactive insights 在 ADR-032 下通常 `freshnessMetadata == nil`（historical semantics，不要求 monthly-summary freshness contract）。

ADR-020 deterministic fallback：**not persisted**（`modelName == "deterministic"`）。

JSON Store 保持 **schema v4**；optional field 在当前 Codable / store convention 下 **不需要 migration**。

### Read 语义（current implementation — ADR-032）

Home current AI summary：

```text
allowFinancialContextToAI?
├─ NO
│   → deterministic current summary
│   → 不展示 persisted AI monthly summary
│   → 不发送新的 financial-context Provider 请求
│
└─ YES
    ↓
latest stored `.summary`
    ↓
freshness metadata current?
    ├─ YES
    │   → trusted persisted summary（no read-time Validator）
    │
    └─ NO / nil / unsupported
        → cache miss
        → generate / ADR-020 deterministic fallback
```

明确：

- **No read-time Validator**
- stale / legacy record **不会被 read 时删除**
- Consent revoke **隐藏** current Home AI summary，**不删除** historical `FinancialInsight`
- Consent re-enable：仍 fresh → reuse；stale → regenerate

---

## 15. FinancialAssistantContextDTO

这是 AI-safe view。

### 设计原则

只包含聚合、必要、已授权的数据。

示意：

```text
summary
├── income
├── expense
├── repayment
└── net

cashFlow
├── horizon
├── projectedBalance
├── minimumBalance
└── risk

debt
├── totalOutstanding
├── currentDue
├── minimumPayment
├── debtToIncome
└── completeness

spending
└── topCategories[]

goals[]
budgets[]

question
├── text
└── intent
```

不得默认包含：

- UUID
- merchant
- note
- raw screenshot
- sourceIds

---

## 16. AssistantRequestDTO

用于 Provider transport。

职责：

- 版本化请求格式
- question
- intent
- safe financial context
- fact keys / facts
- schema-required metadata

Provider 只依赖此 DTO，而不依赖 iOS Domain Object Graph。

---

## 17. Structured Output — 三层 ownership（C2B）

不要混淆以下三层 transport / schema（见 ADR-031）。本节取代旧版「Model 直接输出 embedded value」描述。

### A. Bailian model-generation（source-only）

LLM structured output 的 model draft keyFact **只含 source reference**（label / kind / source）。**不要求 LLM 输出 embedded KeyFact value。** Bailian model-generation schema **不得**依赖 conditional polymorphic generated value（ADR-017）。

### B. Gateway canonical materialization

Gateway 从 authorized deterministic facts materialize canonical value（money / text / percent / date）。`ModelKeyFactValueDTO` 属于 **materialization / response transport**，**不是** Bailian model-generated value。

### C. iOS-facing AssistantAnswerDraft

Gateway → iOS 响应含已 materialize 的 keyFact values，再进入 Validator。Gateway → iOS response contract 可有独立 schema；**不自动构成 ADR-017 conflict**。

---

## 18. ModelKeyFactValueDTO（Gateway materialization）

历史方案曾让 Provider 直接输出 polymorphic keyFactValue（allOf + if / then），已废弃于 model-generation 阶段。当前 **固定 nullable shape** 用于 Gateway materialization：

```json
{
  "type": "money|text|percent|date",
  "amount": null,
  "currencyCode": null,
  "textValue": null,
  "percentValue": null,
  "dateValue": null
}
```

由 Gateway 从 authorized facts 填入对应字段，**非 LLM 自由生成**。

---

## 19. ModelKeyFactDTO & ModelAssistantAnswerDraftDTO

### ModelKeyFactDTO（Bailian model output）

Model-side key fact — **source-only reference**（label / kind / source）。**不含** `value: ModelKeyFactValueDTO`（旧描述已过时）。

### ModelAssistantAnswerDraftDTO

Bailian model-generation transport envelope：

```text
Remote JSON (source-only keyFacts)
  ↓
ModelAssistantAnswerDraftDTO
  ↓
Gateway materializer
  ↓
AssistantAnswerDraft (iOS-facing, with values)
  ↓
Map / validate in iOS Domain
```

它不是最终可展示答案。

---

## 20. AssistantAnswerDraft

Provider 输出进入 Domain validation 前的语义模型。

可能包含：

- title
- body
- disclaimer
- unknowns
- confidence
- citedFactKeys
- keyFacts
- destination

任何字段都不能因为“来自 LLM”就默认可信。

---

## 21. AssistantAnswer

经过 Validator 后才允许交给 UI。

```text
AssistantAnswerDraft
      ↓
AssistantAnswerValidator
      ↓
AssistantAnswer
```

这是 AI 结果从“不可信输入”变成“可展示 Domain Object”的边界。

---

## 22. AIDataConsent

核心字段：

```text
allowScreenshotImageToAI: Bool
allowDebtScanImageToAI: Bool
allowFinancialContextToAI: Bool
retainOriginalImages: Bool
```

四个字段均为 production user-controllable。缺失 persisted consent 时：`fetchOrDefault` → `deniedDefault`。

### 数据语义

#### allowScreenshotImageToAI / allowDebtScanImageToAI

这两个字段控制 **未来 AI 图片处理资格**（交易截图识别 / 债务账单扫描）。

它们 **不等于** 原图保留。授权识别或扫描不会自动保存原图。

#### allowFinancialContextToAI

允许发送最小化聚合财务上下文。

对 Home current AI enrichment（ADR-032）同时控制：

1. 是否允许新的 financial-context Provider transmission；
2. 是否允许 persisted AI monthly summary 作为当前 Home AI enrichment 展示。

Consent revoke **不自动删除** historical `FinancialInsight` records；仅阻止当前 Home 展示与新的 transmission。

该规则 **不扩展** 到 screenshot consent 或 debt scan consent 的独立 payload 语义（仍由各自字段与 Service gate 控制）。

#### retainOriginalImages

独立于图片 AI 传输授权。

```text
default false
independent of image AI transmission permission
true  = permit app-private original-image retention
false = no persistent original binary
true → false = stop future retention + purge prior user-retained originals
```

---

## 22.1 Media lifecycle

Persisted media 由两部分组成：

```text
MediaArtifact metadata（JSON Store）
+
DirectoryMediaBinaryStore retained binary（app-private filesystem）
```

Retained originals **不是** financial facts。Backup v1 仍排除 `MediaArtifact` / original images（ADR-033）。JSON Store 保持 schema v4；ADR-034 不要求 schema migration。

---

## 23. FinancialRiskAssessment（已实现）

> **Implementation status（2026-08-19）：`IMPLEMENTED` / regression-covered（非 production-grade）**

当前 Domain 模型（`ReadModels/FinancialRiskModels.swift`）：

```text
FinancialRiskAssessment
├── overallLevel
├── signals[]
├── dataCompleteness / debtDataState
├── policyVersion
└── evaluatedAt
```

由：

```text
FinancialRiskAssessmentService
  → FinancialRiskPolicyInputBuilder
  → FinancialRiskPolicyEngine.evaluate
```

基于各确定性 Engine 输出生成。

Regression：`FinancialRiskEvaluationGoldenParityTests`（29-case golden parity）等。

LLM 可以解释 Assessment，但不负责创造 Assessment。

Warnings / actions 在 monthly summary 路径上由 `MonthlySummaryPolicyProjection` 等 **deterministic policy ownership** 参与合并（ADR-028 部分落地）。

---

## 24. Data Persistence

当前持久化：

```text
JSON Store
schema v4
```

支持：

```text
v1 → v4 migration
```

`FinancialInsight.freshnessMetadata` 为 optional。legacy 记录缺少该字段时安全 decode 为 nil。**ADR-032 不需要 schema migration。**

**JSON Store remains schema v4. ADR-034 requires no schema migration.**

历史 store：

```text
Application Support/Youshu/youshu-store.json
```

由于产品改名：

**该路径目前视作 legacy persistent identifier。**

迁移到 FinSight 路径前必须有数据迁移方案，不能简单 rename。

---

## 24.1 BackupPayloadV1 — Portable Backup Transport Model（ADR-033）

> **Implementation status（2026-08-21）：`IMPLEMENTED` / Apple-CI VERIFIED**

`BackupPayloadV1` 是 **portable backup transport model**，用于 encrypted `.finsightbackup` artifact 内的语义 payload。

它 **不是**：

- Domain financial fact 的 live persistence 形态
- raw `YoushuSnapshot`
- JSON Store schema v4 的直接镜像

Backup format version（`BackupPayloadV1.formatVersion`）**独立 versioning**；`sourceStoreSchemaVersion` 仅为 provenance metadata，**不是** restore compatibility authority。

### Backed-up entities（`BackupFinancialDataV1`）

```text
BackupUserV1
Account
Transaction
Debt
DebtEvent
RepaymentPlan
Asset
Goal
Budget
Subscription
```

关系重建所需的 UUID 可保留在加密 artifact 内。

### Explicit exclusions（intentional — not data loss bug）

Backup v1 **不** backup / restore / carry forward：

```text
FinancialInsight
AIDataConsent
AIRecognitionRecord
MediaArtifact
PendingDebtLink
SuspectedDebt
```

Restore candidate 语义：

```text
JSON Store schema v4 candidate
excluded collections → empty
User.debtImportInProgress → false
AIDataConsent absence → fetchOrDefault → deniedDefault
```

Historical AI insight **不** 通过 backup 迁移。Restore **不** 触发 remote AI generation。

Derived read models（`FinancialSummary`, `CashFlowProjection`, `FinancialRiskAssessment`, `HomeOverview` 等）**不是** backup facts；restore 后由 engines 自 restored facts 重算。

### Encryption envelope（transport layer）

Backup file = authenticated encrypted envelope（PBKDF2-HMAC-SHA256 / 600,000 / AES-256-GCM；whole file ≤ 64 MiB）。Passphrase 不持久化；exact string 为 crypto input（no trim/normalization）。

---

## 25. 数据生命周期

### Screenshot

当前实现语义：

```text
select image
→ image AI consent gate
→ in-memory recognition processing
→ Imported Draft
→ user confirmation
→ Transaction / Debt

retainOriginalImages == false
→ no persistent original binary

retainOriginalImages == true
→ eligible original may remain as user-retained media
```

AI 处理 **不意味着** 一定发生远程发送；是否发送取决于当前 consent 与实际 Provider 路径。授权识别 ≠ 保留原图。

### Financial Facts

用户明确创建 / 确认后持久化。

### AI Request

短生命周期，不作为财务事实持久化。

### AI Answer / FinancialInsight

Validated AI monthly summary 与 proactive insights 可持久化为 `FinancialInsight`（validate-on-write）。

ADR-032 freshness metadata 标识 monthly summary 是否仍对应当前 deterministic facts / policy。

ADR-020 deterministic Home fallback **不持久化**。

即使持久化 historical insight：

- 不能成为财务计算输入的唯一事实
- stale summary 在 Home read 时按 cache miss 处理（不删除 record）

---

## 26. 删除与恢复

必须区分三条生命周期，不得混用：

### Consent revoke

权限 / 生命周期变化，**不是** historical AI 删除。

Financial-context revoke：停止新的 financial-context AI 使用与当前 Home enrichment；**不自动删除** historical `FinancialInsight`。

### Full local wipe（ADR-034 — IMPLEMENTED / VERIFIED 2026-08-21）

当前用户本地数据删除，采用 monotonic privacy semantics：

```text
current-user financial data
AI consent
historical insight
recognition/media metadata
retained original binaries
→ deleted
```

```text
external .finsightbackup
→ not deleted
```

Post-wipe：

```text
deleted current user
→ application bootstrap
→ valid clean/new session
→ consent deny-default
```

Wipe **不是** Restore full-replace。成功 persistent deletion 后建立新/空会话；失败不得假装已换成干净会话。部分原图清理失败可区分且可重试，且不得回滚已删除的财务数据。

### Backup / Restore（ADR-033）

Backup v1 提供 **manual encrypted portable backup + full-replace restore** — 不是 merge，不是 Export，不是 Cloud Sync，也不是 local wipe。

Restore 后：财务事实恢复；`AIDataConsent` / `FinancialInsight` / `MediaArtifact` / retained originals **不** 从 backup 恢复。

仍开放：

- 删除单笔 Transaction / Account / Debt（既有实体删除）
- human-readable Export
- automatic / cloud backup

---

## 27. 数据模型不可违反的约束

1. Transaction 是事实，不是 AI 结论。
2. Debt 是长期负债对象，不等于某笔支出。
3. missing debt data 不能当成 zero debt。
4. CashFlow 是确定性计算结果。
5. FinancialContext 不可直接作为远程 AI payload。
6. AI DTO 不暴露无必要 UUID / merchant / note / screenshot。
7. Provider Draft 不可直接进入 UI。
8. AI 出现的金额必须可追溯到合法 FactPack。
9. legacy store rename 必须保证历史用户数据迁移。
10. UI / Presentation 不承担核心财务计算。
