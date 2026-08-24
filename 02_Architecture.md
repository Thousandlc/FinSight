# 知数 · FinSight — Architecture

> 文档角色：系统架构长期真相源  
> 版本：v1.0  
> 更新日期：2026-08-24
> 状态：Active  
> 原则：本文记录“当前确认架构 + 已确定的演进方向”，不把聊天中的临时建议视作实现事实。

---

## 1. 架构目标

FinSight 的架构优先保证：

1. **财务计算正确**
2. **AI 不成为财务事实源**
3. **隐私边界清晰**
4. **AI Provider 可替换**
5. **远程 AI 故障不破坏核心财务功能**
6. **能够对 Answer 做审计与验证**
7. **中国 iOS MVP 可以渐进演进，而不过早复杂化**

---

## 2. 当前系统分层

当前体系可以抽象为：

```text
┌──────────────────────────────────────────────┐
│                    UI                        │
│ Home / Transactions / Debt / Accounts / AI │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│             Application / Service            │
│ HomeOverviewService                         │
│ FinancialAssistantService                   │
│ FinancialContextBuilder                     │
│ Privacy / Consent Services                  │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│                Domain Engines                │
│ FinancialSummaryEngine                      │
│ CashFlowEngine                              │
│ DebtCenterCalculator                        │
│ PurchaseScenarioEngine                      │
│ Risk / Insight deterministic logic          │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│               Domain Models                  │
│ Transaction / Account / Debt / ...          │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│             Repository / Data                │
│ Local JSON Store                            │
│ App-private retained original-image binaries │
└──────────────────────────────────────────────┘
```

AI 是旁路能力，而不是数据层：

```text
Domain Data
   ↓
FinancialContextBuilder
   ↓
FinancialContext
   ↓
FactPack / MonthlySummaryFacts / InsightFacts
   ↓
FinancialAssistantContextMapper
   ↓
FinancialAssistantContextDTO
   ↓
AssistantRequestDTO
   ↓
Serializer
   ↓
Provider
   ↓
AssistantAnswerDraft / Model DTO
   ↓
AssistantAnswerValidator
   ↓
AssistantAnswer
   ↓
UI
```

---

## 3. 客户端模块

历史代码资料中存在如下模块命名：

- `YoushuUI`
- `YoushuDomain`
- `YoushuData`
- `YoushuAI`

这些属于改名前 legacy 技术标识。

正式产品名已变更为 FinSight，但是否已经完成 package / module / bundle / directory 的技术重命名，必须以仓库为准。

### 当前原则

不为了“名字好看”破坏：

- Swift module import
- persisted store path
- bundle identifier
- migration compatibility
- CI
- XcodeGen

技术改名必须作为独立迁移任务处理。

---

## 4. UI 架构

当前主要 UI：

```text
TabView
├── 首页
├── 账单
├── 债务
├── 账户
│   └── 隐私与 AI
└── AI
```

### Home

核心链路：

```text
HomeOverviewService.loadOverview
        ↓
FinancialContextBuilder / repository facts
        ↓
FinancialSummaryEngine
        ↓
CashFlowEngine.projectAllHorizons
        ↓
HomeOverview
        ↓
CashFlowPresentation
        ↓
CashFlowSectionView / CashFlowDetailView
```

CashFlowPresentation 只负责：

**Domain Model → UI Display Model**

不得在 Presentation / View 中重新进行财务计算。

### AI 页面

回答卡片只渲染经过验证的：

- title
- body
- sources / facts
- navigation destination

不得直接渲染未经 Domain Validator 的 Provider raw output。

---

## 5. Domain 数据原则

### 5.1 底层事实

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

### 5.2 派生结果

```text
FinancialSummary
CashFlowProjection
CashFlowRisk
DebtPressure
FinancialRiskAssessment
Insight
Assistant FactPack
```

核心规则：

> **事实存储，结论计算。**

除非存在明确业务原因，不应把可由当前事实稳定重新计算的结果反向当成用户事实。

---

## 6. 确定性财务引擎

已知核心 Engine：

### FinancialSummaryEngine

负责当前月等聚合指标：

- income
- expense
- repayment
- balance / summary metrics

### CashFlowEngine

负责：

- 7 天
- 30 天
- 60 天
- 90 天

未来现金流预测。

### DebtCenterCalculator

负责债务中心的确定性计算。

### PurchaseScenarioEngine

用于消费场景评估。

已发现历史上 `ask()` 路径存在重复 evaluate 的问题；该类重复计算应逐步消除，但不得为了去重破坏结果一致性。

---

## 7. FinancialContext

`FinancialContext` 是 Domain 侧财务上下文聚合结果。

它可以包含比远程 AI 真正需要的数据更多，因此：

**禁止直接把完整 FinancialContext 发送给 Provider。**

历史审计确认：

- Home 与 Assistant 使用同源 Engine。
- Home 会使用 7/30/60/90 等多个现金流窗口。
- Assistant Context 重点使用 30 天 slice。
- Assistant 可独立运行 `CashFlowEngine.project(30)`，而非依赖 Home UI 缓存。

这保证：

- AI 不依赖某个页面先加载
- Service 层可独立测试
- Domain 计算仍是事实来源

未来如果为了性能缓存，缓存只能优化执行，不应改变事实源。

---

## 8. AI Context 边界

### 8.1 正确链路

```text
FinancialContext / FactPack
        ↓
FinancialAssistantContextMapper
        ↓
FinancialAssistantContextDTO
        ↓
AssistantRequestDTO
        ↓
Provider
```

### 8.2 DTO 目标

DTO 只包含 AI 完成任务所需字段。

允许：

- 聚合收入 / 支出
- 现金流结果
- 债务压力
- 已授权关键金额
- top categories（有限数量）
- goals / budgets 的安全视图
- question
- intent

禁止默认发送：

- Domain UUID
- source*Ids
- 原始 Repository Model
- merchant 明细
- note
- 原始截图
- 无任务必要性的敏感字段

---

## 9. AssistantRequestDTO

Provider 接口统一接收 `AssistantRequestDTO`。

目标：

1. Provider 不依赖 iOS Domain Model。
2. 请求格式可序列化、快照测试。
3. Bailian / 未来其他 Provider 可复用相同 transport contract。
4. 便于 Gateway 做 schema、auth、version、logging control。

---

## 10. Provider 与 Gateway

### 10.1 Provider 抽象

App 侧至少存在两类 Provider：

```text
MockAIProvider
RemoteFinancialAIProvider
```

历史 MVP 默认曾为 Mock。

Remote 路径：

```text
iOS
 ↓
RemoteFinancialAIProvider
 ↓
FinSight AI Gateway
 ↓
Bailian / Qwen
```

### 10.2 Gateway

Go Gateway 的核心 API 历史路径：

```text
POST /v1/ai/financial-assistant
```

并包含健康检查：

```text
/health
/ready
```

最新已知内部部署服务名：

```text
finsight-ai-gateway
```

### 10.3 Provider Key

Bailian API Key 只应存在于 Server/Gateway 安全环境。

**不得嵌入 iOS App。**

---

## 11. Structured Output

早期 `keyFactValue` 使用 conditional schema：

```text
allOf + if / then
```

根据 `type` 切换 required fields。该方式在 **Bailian model-generation** 中出现 polymorphic shape drift / `typeMismatch`。

### 三层 schema（2026-08-19 Baseline Audit — 不要混为一谈）

#### A. Bailian model-generation schema

- LLM 输出 **source-only keyFact references**（label / kind / source）。
- **不得**要求 LLM 生成 embedded KeyFact value。
- **不得**依赖 conditional polymorphic generated value（ADR-017）。

#### B. Gateway canonical materialization

- Gateway 从 authorized deterministic facts materialize canonical values。
- `ModelKeyFactValueDTO` 属于 materialization / response transport，**非 LLM 生成**。
- Materializer 是 trust-boundary 组件（见 ADR-031）。

#### C. Gateway → iOS response schema

- iOS-facing `AssistantAnswerDraft` 含已 materialize 的 values。
- 可有独立 deterministic response contract（例如 response JSON schema 中的 polymorphic value shape）。
- **不自动构成 ADR-017 conflict**（ADR-017 针对 A 层 model-generation）。

### 端到端链路（C2B）

```text
Deterministic FactPack
        ↓
AI-safe request
        ↓
Bailian（source-only keyFact references）
        ↓
Gateway materializer
        ↓
AssistantAnswerDraft
        ↓
AssistantAnswerValidator
        ↓
AssistantAnswer
```

原则：

> **Provider / LLM 不拥有 canonical financial values。**  
> **Provider Transport DTO 不是 iOS Domain Model。**

Structured Output 的目标首先是稳定 model-generation，然后在 Gateway materialization 与 Domain Validator 层做语义验证。

---

## 12. Assistant Answer 双层结构

### Provider 输出

```text
AssistantAnswerDraft
```

或 Provider-specific model draft DTO。

### Domain 结果

```text
AssistantAnswer
```

### 转换链路

```text
Provider Raw Output
      ↓
Decode / Model DTO
      ↓
AssistantAnswerDraft
      ↓
AssistantAnswerValidator
      ↓
AssistantAnswer
```

Validator 至少负责：

- title / body 非空
- 金额必须来自合法 fact pack
- citedFactKeys 合法
- disclaimer 规则
- unknowns / confidence 等契约
- 不允许 inventedAmount
- 不允许引用不存在的财务事实

### Persisted Insight — Trust / Freshness / Consent（三个独立维度）

Stored Insight 架构由三个 **彼此独立** 的维度组成。不得混为一谈。

#### Trust

**问题：** AI 内容在写入 persistence 前是否经过验证？

**机制：**

```text
Provider Draft
→ AssistantAnswerValidator
→ persisted validated snapshot
```

**状态：** **VERIFIED SAFE**（2026-08-20）

Production-reachable AI insight persistence 采用 **validate-on-write → trusted persisted read**：

```text
Untrusted Provider Draft
        ↓
AssistantAnswerValidator
        ↓
Validated Domain Result（flattened title/body 等）
        ↓
FinancialInsight persistence
        ↓
Trusted persisted snapshot
        ↓
Home / AI UI read
```

要点：

- **Validation boundary 位于 write 前** — 仅 validated content 可 upsert 到 `FinancialInsight` repository。
- **Persisted validated snapshot 在 read path 不要求重复 Validator** — fresh stored `.summary` 可直接 trust。
- **Repository read 本身不是 Provider trust boundary** — read 不 re-validate 在当前 architecture 下合理，前提是 write path 已 gate。
- **ADR-020 deterministic fallback 不进入 persistence** — `modelName == "deterministic"` 的 Home fallback 为 ephemeral。

Production write paths（已验证）：

1. `FinancialAssistantService.generateMonthlySummaryWithRiskAssessment`
2. `FinancialAssistantService.refreshProactiveInsights`

Regression：`StoredInsightTrustBoundaryTests`。

#### Freshness

**问题：** persisted monthly summary 是否仍然对应当前 deterministic financial facts / policy？

**机制：**

```text
Current MonthlySummaryFacts
+
FinancialRiskAssessment
+
policyVersion
        ↓
freshness metadata（opaque SHA-256 digest）
        ↓
compare persisted metadata
```

**状态：** **IMPLEMENTED / ADR-032**（2026-08-20）

Home 对 stored `.summary` 的判断：

```text
current metadata match → fresh
digest mismatch → stale
policyVersion mismatch → stale
legacy metadata == nil → stale / unverifiable
unsupported freshness schema → stale / unverifiable
```

所有 stale / unverifiable 按 **cache miss** 处理。read 时 **不删除** stale record。

不得使用 `generatedAt` / TTL 作为 freshness correctness 的主要机制。

raw canonical financial-fact token **仅运行时存在，不持久化**。

#### Consent Eligibility

**问题：** Home 当前是否允许使用 financial-context AI enrichment？

**机制：**

```text
AIDataConsentService
→ allowFinancialContextToAI
```

**状态：** **IMPLEMENTED / ADR-032**（2026-08-20）

Consent revoke **不等于** delete historical insights。Consent **不进入** freshness digest。

Proactive historical insights **不属于** Home monthly-summary freshness contract。

### Home Two-Gate Architecture（ADR-032）

```text
Home deterministic state
        ↓
Consent Gate
├─ denied
│   → deterministic summary
│   → 不显示 stored AI summary
│   → 不调用 Provider
│
└─ allowed
    ↓
Freshness Gate
    ├─ fresh
    │   → trusted persisted summary
    │
    └─ stale / legacy / unsupported
        → AI generation
            ├─ validated AI success
            └─ ADR-020 deterministic fallback
```

明确：

- Trust 由 write boundary 保证，不靠 read-time Validator；
- stale **不等于** untrusted；
- Consent denied **不等于** delete；
- Consent 不进入 fingerprint；
- proactive historical insights 不属于 Home monthly-summary freshness contract；
- `generatedAt` / TTL 不作为 correctness mechanism。

Regression：`HomeOverviewFreshnessTests`、`HomeOverviewConsentLifecycleTests`、`FinancialRiskConsentClosureTests`。

---

## 13. 金额安全模型

核心原则：

```text
LLM 不产生新的财务金额。
```

如果 AI body 中出现：

```text
¥2000
```

Validator 必须能在允许金额集合 / FactPack 中找到合法来源。

历史上出现过：

```text
safeBalance = ¥2000
```

由确定性 explanation 写入文案，但没有进入对应 `InsightFactPack.amounts`，最终触发 `inventedAmount("2000")`。

这说明：

> **即使金额来自确定性代码，只要它进入 AI 文案，就必须进入可审计 FactPack。**

不得通过弱化 Validator 来掩盖事实来源缺失。

---

## 14. Consent 架构

核心模型：

```text
AIDataConsent
```

已知字段：

```text
allowScreenshotImageToAI
allowDebtScanImageToAI
allowFinancialContextToAI
retainOriginalImages
```

门禁由 Service 层执行，而不是只依赖 UI 隐藏按钮。

当前生产可达的统一设置链：

`	ext
账户
→ PrivacyAISettingsView
→ PrivacyAISettingsViewModel
→ AIDataConsentService
→ persisted AIDataConsent
`

四个字段均可独立管理。截图、债务扫描、AI Assistant 的情境式首次授权仍走同一 persisted source。不存在 UI-only shadow consent state。缺失 persisted consent 时仍为 **deny-by-default**。

原则：

```text
UI consent
   ↓
Domain / Service enforcement
   ↓
Mapper determines payload
   ↓
Provider
```

撤销授权后，新请求必须遵守最新状态。

### Import Provenance Architecture（ADR-036 — ACCEPTED / IMPLEMENTED — VERIFIED 2026-08-24）

> **Status:** ADR-036 remains implemented. ADR-037 Step 3 production Transaction recognition is Apple-verified on candidate `67de996dc817ba9114479f613f0c83292f1e8240`; real accuracy remains **NOT ESTABLISHED**. Recognition Quality harness ≠ OCR quality.

**Implemented flow:**

```text
Input bytes
        ↓
Local full-file SHA-256 fingerprint(s)
        ↓
Exact-source provenance lookup
        ↓
Recognition Provider (current port: TransactionExtracting / DebtScanning batch)
        ↓
Transient / unpersisted recognition result
        ↓
Application operation-currentness gate (generation / cancel-and-replace)
        ├─ stale / cancelled before Application acceptance
        │     → discard in memory
        │     → no durable MediaArtifact
        │     → no AIRecognitionRecord
        │     → no retained binary
        └─ current → Application acceptance → eligible recognition/media metadata persist
        ↓
User review / edit
        ↓
User confirmation
        ↓
Authoritative financial fact persist (Transaction / Debt)
        ↓
ConfirmedImportProvenance upsert (local durable; excluded from Backup v1)
```

Provenance write failure after financial persist is a **secondary / degraded** outcome: the financial fact remains authoritative.

**Transaction exact-source semantics (implemented):**

```text
exact previously-confirmed screenshot
→ local provenance match
→ warning before recognition
→ view existing Transaction(s)
→ explicit user override may continue
```

```text
exact-source match  !=  semantic financial duplicate
```

No merchant / amount / date heuristic exists.

**Debt exact-batch semantics (implemented):**

```text
exact previously-confirmed Debt scan batch
→ prior-scan / reconciliation signal
→ related Debts may be surfaced
→ explicit user continuation allowed
```

```text
prior scan              != automatic duplicate Debt
batch-level provenance  != image→Debt causality
```

No automatic field-level merge.

**Key boundaries (current runtime):**

| Concept | Role |
|---------|------|
| `ConfirmedImportProvenance` | Local durable **confirmed-import** memory; not a financial fact |
| `AIRecognitionRecord` | Optional workflow/audit metadata **after** Application acceptance |
| `MediaArtifact` | Media lifecycle / retention; **not** provenance authority |
| `sourceImageId` | Media lifecycle id; **not** cryptographic exact-input fingerprint |

**Production Provider reality (ADR-037 Step 3):**

```text
Production TransactionExtracting: AppleVisionTransactionRecognizer
Production DebtScanning:          MockAIProvider (UNCHANGED)
Production FinancialAssisting:    existing Mock/remote router (UNCHANGED)
Real Transaction pixel recognition: IMPLEMENTED / PRODUCTION COMPOSITION WIRED
Real Debt pixel recognition:        NOT IMPLEMENTED
```

### Transaction Recognition v1 Contract（ADR-037 — ACCEPTED / IMPLEMENTED / VERIFIED 2026-08-24）

Transaction 单图 Application / Domain outcome 已定义：

```text
recognized
unsupported
unreadable
failure
```

`recognized` 仅表示得到可审核的 `TransactionDraft`，不表示 Transaction 已持久化、用户已确认、
字段已全部正确或 provenance 已写入。金额等关键字段仍由 Recognition Quality harness 独立评测。

Step 3 production composition 保持以下依赖方向：

```text
on-device pixel recognizer (Apple Vision adapter; Infrastructure-only)
→ platform-neutral RecognizedTextSpan
→ deterministic TransactionRecognizedTextParsing
→ TransactionRecognitionOutcome / reviewable TransactionDraft
→ existing Application currentness gate
→ user review and confirmation
→ authoritative Transaction persist
→ ConfirmedImportProvenance
```

Apple Vision framework types 不得进入 shared Domain / Application contract。确定性 parser 不得调用远程
LLM / Gateway、持久化 Transaction、写 provenance 或绕过用户确认。Raw OCR text 默认仅为 transient data；
不进入 Store、Backup v1、observability 或 AI financial-context DTO。

```text
Recognition Result != Transaction
```

Apple Vision implementation 与真实 pixel-reading Transaction recognizer 已接入 production `TransactionExtracting`；
`DebtScanning` 与 `FinancialAssisting` 未切换。真实 accuracy baseline 尚未建立。ADR-036 exact-source provenance、
currentness 与写入顺序不变；识别仍在本机完成且不远程传输图片。

**Current batch abstraction (unchanged):**

```text
DebtScanning.scanDebts(from: [BillDocument]) → [DebtCandidate]
```

```text
Transaction single-image Application / Domain outcomes: DEFINED — ADR-037
Debt per-image Provider outcomes: DEFERRED UNTIL REAL DEBT PIXEL-READING PROVIDER
Provider-specific finer-grained recognition taxonomy: NOT FROZEN BY ADR-037
```

**Explicitly deferred (ADR-036):**

- Debt per-image Provider outcome taxonomy until a **real Debt pixel-reading recognizer** exists
- Debt field-level reconciliation/merge rules
- Semantic Transaction duplicate detection
- Portable provenance across Backup v1 restore (requires future Backup v2 / ADR)
- One-call-per-document Debt scanning as default architecture

### Production Consent Wiring（Step 5A — 2026-08-20）

Production Home 始终通过：

```text
FinSightApp
→ AppDependencies（non-optional AIDataConsentService）
→ OverviewServiceContainer
→ HomeOverviewService
```

当不存在 persisted consent record 时：**deny-by-default**（`fetchOrDefault → .deniedDefault`）。

`HomeOverviewService(consentService: nil)` 及 Container optional 默认值 **仅用于 test/dev composition**；当前 production 不可达。未来新增 production composition 时 **必须** 注入真实 `AIDataConsentService`。

### Home financial-context eligibility（ADR-032）

`allowFinancialContextToAI` 同时控制：

1. 是否允许新的 financial-context Provider transmission；
2. 是否允许 persisted AI monthly summary 作为当前 Home AI enrichment 展示。

Consent denied 时：使用 deterministic Home summary；不展示 stored AI summary；不调用 Provider；**保留** historical persisted insights。

Consent 与 Freshness 是 Home current AI summary 的两个独立 gate（见 §12 Home Two-Gate Architecture）。

### Unified Privacy & AI Settings（IMPLEMENTED / VERIFIED 2026-08-21）

生产导航：

`	ext
账户
→ 隐私与 AI
`

Settings UI 管理全部四个 AIDataConsent 字段；情境式 consent sheets 继续存在，但写入同一 canonical service。

### Original-image retention（IMPLEMENTED / VERIFIED 2026-08-21）

`	ext
AIDataConsent.retainOriginalImages
→ MediaLifecycleService
→ DirectoryMediaBinaryStore
→ app-private retained originals
`

生产根语义（相对 live store，不暴露绝对 runtime path）：

`	ext
Application Support/Youshu/media-originals/
`

语义：

`	ext
false → no persistent original binary
true  → .userRetained original may persist
disable → preference false first → purge retained originals
`

Apple-specific filesystem properties（与 ADR-033 Backup exclusion 分离）：

`	ext
iOS file protection applied by DirectoryMediaBinaryStore
Apple filesystem backup exclusion applied to retained-original storage
`

- FinSight Backup v1 excludes media by **payload contract**（ADR-033）
- Apple filesystem backup exclusion is a **separate platform storage property**

Image AI consent ≠ image retention.

### Local full-data wipe（ADR-034 — IMPLEMENTED / VERIFIED 2026-08-21）

`	ext
PrivacyAISettingsView
→ deletion confirmation
→ PrivacyDataService
   ├─ user-scoped media binary cleanup
   └─ users.delete / YoushuStore.deleteUser cascade
→ PrivacyWipeResult
→ ApplicationPrivacyWipeReset
→ bootstrap + applicationDataRevision + transient reset
`

Outcomes:

`	ext
complete
mediaCleanupIncomplete
persistentDeletionIncomplete
`

Monotonic privacy semantics：once sensitive data is successfully deleted, it is not recreated merely to simulate rollback. Successful persistent deletion bootstraps a valid new/empty session. External .finsightbackup files are not targeted.

---

## 15. 数据持久化

### 15.1 Live JSON Document Store（当前 live persistence）

当前已知实现：

```text
JSON Document Store
schema v5
```

支持历史：

```text
v1 → v5 migration
```

`FinancialInsight.freshnessMetadata` 为 **optional** 字段。legacy JSON 记录缺少该字段时安全 decode 为 nil。**ADR-032 不需要 schema migration。**

Live store 路径（legacy 命名，**不得随意 rename**）：

```text
Application Support/Youshu/youshu-store.json
```

Backup / Restore v1 **不迁移、不重命名** live store path。ADR-022 仍有效。

正式 FinSight 技术改名若涉及 store path，需要：

1. 检测 legacy store。
2. 安全迁移。
3. 校验数据。
4. 成功后再切换。
5. 保留 rollback / recovery 策略。

**ADR-034 不改变 live store path。** Live schema 后经 ADR-036 升至 **v5**；wipe 仍级联移除当前用户 provenance。

### 15.2 App-private retained original-image storage

Retained originals are an **additional local storage layer**, not a replacement for JSON Store and not a Backup v1 payload.

`	ext
Application Support/Youshu/media-originals/
`

JSON Store 继续保存 MediaArtifact metadata；eligible binaries 仅在 
etainOriginalImages == true 时由 DirectoryMediaBinaryStore 落盘。

这与 ADR-033 Backup exclusion 是不同合同：Backup v1 按 payload 排除 media；Apple filesystem backup exclusion 是平台存储属性。

### 15.3 Manual Portable Backup v1（ADR-033 — IMPLEMENTED / VERIFIED 2026-08-21）

Backup v1 是在 JSON Store 之上的 **portable recovery layer**，不是 Cloud Sync，也不是 human-readable Export。

**Create architecture：**

```text
YoushuStore current financial facts
        ↓
BackupSnapshotMapper
        ↓
BackupPayloadV1（financial-facts transport model）
        ↓
BackupCodec.encode（PBKDF2-HMAC-SHA256 / 600k / AES-256-GCM）
        ↓
encrypted Data
        ↓
.finsightbackup（UTType: app.finsight.backup）
        ↓
Files exporter
```

**Restore architecture：**

```text
Files importer（.finsightbackup only）
        ↓
BackupImportFileReader（bounded ≤64 MiB, security-scoped read）
        ↓
immutable encrypted Data（held in flow engine）
        ↓
BackupRestorePreflightService（decode / validate / preview — no store mutation）
        ↓
destructive confirmation
        ↓
BackupRestoreService（re-decode / re-validate same encrypted Data）
        ↓
YoushuStore.replaceSnapshotForRestore（write → disk re-read → verify → rollback on failure）
        ↓
ApplicationRestoreRefresh（session + ViewModels + presentation subtree）
```

**关键边界：**

- Backup ≠ Export ≠ Cloud Sync / multi-device live sync
- Restore = **FULL REPLACE**（非 merge）
- External file remains untrusted until full validation + transactional commit
- Same encrypted bytes preflight → commit；URL 不在 preview 后重读
- Excluded from backup/restore carry-forward：`FinancialInsight`, `AIDataConsent`, `AIRecognitionRecord`, `MediaArtifact`, `PendingDebtLink`, `SuspectedDebt`, **`ConfirmedImportProvenance`（ADR-036）**；restore 后 `debtImportInProgress = false`；AI consent → deniedDefault
- Restore 后 provenance **重置为空**（intentional Backup v1 行为）
- Derived read models（Summary / CashFlow / Risk / HomeOverview 等）restore 后重算，不是 backup facts

### 15.4 Remaining persistence gaps

**已解决（v1 scope）：**

- manual encrypted Backup creation
- transactional full-replace Restore
- Files-based portable artifact（`.finsightbackup`）

**仍开放：**

- 无 automatic backup
- 无 CloudKit / live multi-device sync
- 无 human-readable Export
- 卸载仍可能丢失 **未外置保存** 的 live local data
- 换机 / 数据恢复 **仅当用户曾创建并保留 backup** 时才有 recovery path — 不等于 device migration 已完全无风险
- physical-device Files restore smoke：**NOT RUN**（pre-release manual gate）
- 大数据量 JSON Store 性能仍 unverified

Manual portable Backup **降低** device-loss / migration 风险，但 **不使** local persistence 自动 durable。

---

## 16. Risk Policy（已实现核心架构）

> **Implementation status（2026-08-19）：`IMPLEMENTED` / regression-covered — 非 production-grade**

当前仓库已落地核心 deterministic Risk Policy 链路：

```text
Financial Data
      ↓
Deterministic Engines / FinancialContextBuilder
      ↓
FinancialRiskAssessmentService
      ↓
FinancialRiskPolicyEngine.evaluate
      ↓
FinancialRiskAssessment
      ↓
MonthlySummaryFacts / AI Context / Gateway envelope
      ↓
MonthlySummaryPolicyProjection（deterministic warnings/actions ownership — monthly summary 路径）
      ↓
Qwen explanation / narrative（可选）
      ↓
AssistantAnswerValidator
      ↓
UI
```

Regression coverage（仓库实测）：

- `FinancialRiskEvaluationGoldenParityTests` — **29-case golden parity**
- `FinancialRiskPolicyEngineTests` / `FinancialRiskProductionWiringTests` 等

重点原则：

**Warnings / actions 的风险事实来源应优先来自 deterministic assessment，而不是由 LLM 自由生成。**

AI 可以：解释、总结、组织语言。  
AI 不应该决定：资金缺口是否真实、债务是否逾期、金额是否真实、风险规则是否满足。

### 仍未完成 / 未来演进

- 非 monthly-summary AI 路径（ask / insight / purchase）的 policy ownership 仍主要 mock / 局部
- FinancialRiskPolicy live policy tuning 未验证（ADR-035 已关闭 AI error taxonomy / observability；不含 risk-policy live tuning）
- 不要写 production-ready / production-grade（本轮无额外证据）

---

## 17. 错误降级

### Home failure boundary（ADR-020 — FIXED 2026-08-19）

| 层 | 角色 | 失败行为 |
|----|------|----------|
| **Core Home pipeline** | Repositories → deterministic engines → `HomeOverview` metrics | **Required** — failure → Home load failure |
| **AI monthly summary enrichment** | Consent-gated optional remote/mock summary | **Optional** — generation/Validator failure → deterministic fallback; Home 仍可用 |
| **Monthly-summary cache write** | Home stale-cache `FinancialInsight.summary` upsert after Validator | **Optional** — persist failure → Home 仍可用；已校验 AI 摘要可 ephemeral 展示；`outcome=degraded` |

当前实现链路（ADR-020 + ADR-032）：

```text
Deterministic Home
  → Consent Gate
  → Freshness Gate
  → optional AI monthly-summary enrichment
  → success: validated AI summary
      → stale cache replace upsert (best-effort)
          → upsert success: durable fresh cache
          → upsert failure: ephemeral validated summary, durable state unchanged
  → generation/Validator failure: local deterministic summary (modelName = "deterministic")
  → HomeOverview → UI (.content)
```

Deterministic fallback 特性：

- 无 remote AI 调用（fallback 路径不再发送数据）
- UI 不重新计算财务金额
- 无 invented amount
- 不 bypass Provider Validator（fallback 不是 Provider 输出，而是 `CashFlowExplanationBuilder` 确定性文案）

Home availability policy 在 **`HomeOverviewService`**，不在 Provider。  
`FinancialAssisting` **不再包含** `allowsDeterministicFallbackOnAIFailure`。

Regression：`HomeOverviewAIFailureIsolationTests`、`HomeOverviewCachePersistenceIsolationTests`。

### 其他能力降级目标

| 能力 | Remote AI 失败时 |
|---|---|
| Transaction CRUD | 必须继续 |
| Account CRUD | 必须继续 |
| Debt CRUD | 必须继续 |
| Repayment | 必须继续 |
| CashFlow | 必须继续 |
| Home deterministic metrics | 必须继续 |
| AI answer（Assistant 页） | 可失败并提示 |
| AI monthly summary（Home enrichment） | fallback，不得拖垮首页 — **已实现** |

2026-08-19 Baseline Audit 曾发现 remote mode 下 AI monthly summary 可能让整个 Home load 失败；**当前实现已修复**（ADR-020 Step 3）。

---

## 18. Observability

> **Production Observability & Error Taxonomy → IMPLEMENTED / VERIFIED — 2026-08-22（ADR-035）**

Swift + Go 共享 taxonomy parity fixture：`contracts/observability_taxonomy_defaults.json`（无 codegen）。

Canonical production contract（Swift `YoushuFoundation` + Gateway `observability` package）：

```text
failureStage
errorCode
failureClass
retryability
outcome
```

Outcomes：`success` / `degraded` / `failed` / `cancelled`。

Trust-boundary stages remain distinct:

```text
providerStructuredOutput
≠ factMaterialization
≠ assistantValidation
```

Correlation：one logical iOS AI operation → one opaque `requestId` → iOS observability event + `X-Youshu-Request-Id` → Gateway `event=ai_request`（one terminal event per HTTP attempt）。iOS retry 保持同一 logical `requestId`。Header 名不变，不是品牌迁移。

Gateway 记录 allowlisted metadata（requestId / operation / outcome / durationMs / retryCount / provider·model·status / failureStage / errorCode / failureClass / retryability / schemaStage / token usage when returned / gatewayVersion）。

iOS 观察 consent / requestSerialization / clientTransport / clientResponseDecode / assistantValidation / insightPersistence，以及 Gateway envelope 的 stable `errorCode`。iOS **不**从 public envelope 伪造 Gateway-internal `failureStage`；跨系统 join 用 `requestId`。

Token usage：Gateway 在 Bailian 实际返回时记录；iOS 不重复（public success envelope 不暴露 usage）。**cost 缺席**（无价格表 / 估算成本）。

Production sinks：iOS `ObservabilityLogSink` 与 Gateway `SafeLog` 均为 **local structured production-safe logs**。Observability/logging 失败不得拖垮 AI/业务操作。ADR-035 **不包含** remote aggregation / dashboard。

禁止记录：原始财务 payload、prompt、question/body、merchant、note、financial UUID/sourceIds、原始截图、Provider raw response、API Key、Authorization / client token、任意 localized error string。Debug-only raw dump 必须显式开关，且不可进入 production default。Observability **不是**新的 Consent 或 AI 数据传输通道。

Home degraded（澄清 ADR-020 / ADR-032，不取代）：Provider / Validator 失败 → deterministic fallback → Home available → `degraded`；optional monthly-summary cache persist 失败 → 已校验 ephemeral AI 摘要 → Home available → `insightPersistence` / `persistenceFailure` / `degraded`（不伪造 freshness，不把 stale cache 写成 fresh）；core repository / deterministic 失败 → Home failure。

ADR-035 **不表示**：public Gateway production-ready、真实 Bailian production smoke 已完成、remote aggregation 已部署、iOS 公网 production AI wiring 已完成、ICP 约束解除。

---

## 19. 部署边界

截至 2026-08-19，当前合规约束为：

**ICP备案尚未完成期间，仅允许 ECS 内部部署。**

禁止：

- 配置公网 DNS
- 对公网开放 80
- 对公网开放 443
- 对公网开放 8080
- 通过其他端口或反代绕过备案
- iOS production remote wiring
- 真实 Bailian production smoke

当前 Gateway 即使内部配置为 provider=bailian，也不等于已经完成真实生产调用验收。

---

## 20. 架构不可轻易回退项

后续 Chat / Cursor 修改不得无理由回退以下原则：

1. Domain 与 Provider DTO 隔离。
2. Provider 统一接收 transport request DTO。
3. AI 不计算核心财务金额。
4. Answer 必须经过 Validator。
5. AI payload 最小化。
6. Consent 在 Service 层有真实门禁。
7. Structured Output 优先固定 shape，而非重新引入不稳定 polymorphic schema。
8. UI 不做核心财务计算。
9. Core finance 不依赖 remote AI 可用性。
10. legacy `Youshu` 技术命名迁移必须考虑数据与兼容性。

---

## 21. 目标架构一句话

**FinSight 的系统架构应始终保持：财务事实由本地 Domain 掌握，财务结论由确定性 Engine 计算，远程 AI 只接触最小化安全上下文并负责表达，最终输出再由 Domain Validator 与 Policy 守门。**
