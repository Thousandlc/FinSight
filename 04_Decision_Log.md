# 知数 · FinSight — Decision Log

> 文档角色：架构 / 产品重大决策记录（ADR Index）  
> 版本：v1.0  
> 更新日期：2026-08-21  
> 使用方式：以后任何与下列结论冲突的修改，都应先新增 ADR 说明“为什么改变”，而不是静默回退。

---

## ADR-001 — 产品仅面向中国市场

**状态：Accepted**

### 决策

FinSight 当前只服务中国用户，不考虑海外市场。

### 影响

优先：

- 微信
- 支付宝
- 中国银行卡 / 信用卡
- 花呗 / 消费贷 / 网贷
- 中国多平台借贷场景

不优先：

- Open Banking
- 海外银行卡聚合
- 国际化多币种
- 海外监管适配

---

## ADR-002 — iOS 为 MVP 首发平台

**状态：Accepted**

### 决策

MVP 使用 iOS 17+。

### 原因

目标先满足 iPhone 实际使用与快速验证。

---

## ADR-003 — iOS 自动记账采用“截图识别 + 用户确认”

**状态：Accepted**

### 决策

不依赖系统级读取微信 / 支付宝支付通知。

MVP：

```text
截图 / PhotosPicker
→ AI/OCR
→ Draft
→ 用户确认
→ Transaction
```

### 原因

iOS 系统限制下，这条路径可实现、可控且更符合隐私边界。

---

## ADR-004 — 债务升级为一级核心业务域

**状态：Accepted**

### 决策

债务不是附属功能。

重点支持中国用户“多借贷平台并行”的现实场景。

### 方向

- 批量截图
- AI 债务扫描
- 自动发现
- 渐进式建档
- RepaymentPlan
- Bill
- 债务压力
- 现金流联动
- AI 还债辅助

---

## ADR-005 — Transaction 是底层财务事实

**状态：Accepted**

### 决策

Transaction 表达已发生的资金事实。

Debt / Account / Asset 是财务对象。

Cash Flow / Health / Risk / Insight 属于派生状态或结论。

### 禁止

把 AI 生成文本当成财务事实源。

---

## ADR-006 — 财务核心金额由 Domain Engine 计算

**状态：Accepted / Critical**

### 决策

LLM 不负责：

- 收支合计
- 债务余额
- 现金流余额
- DTI
- 风险阈值判断
- 可用资金

由确定性 Engine 负责。

### 原则

```text
Engine = 算清楚
LLM = 说清楚
```

---

## ADR-007 — CashFlow 使用 7/30/60/90 天窗口

**状态：Accepted**

### 决策

Home 现金流预测核心 horizon：

- 7 天
- 30 天
- 60 天
- 90 天

### Assistant

Assistant 可以按任务只使用 30 天等必要 slice。

---

## ADR-008 — Presentation 层不进行财务计算

**状态：Accepted**

### 决策

`CashFlowPresentation` 等模型只负责：

```text
Domain → UI Display
```

不得重新计算财务规则。

---

## ADR-009 — AI 数据必须经过专用安全 DTO

**状态：Accepted / Critical**

### 决策

禁止：

```text
FinancialContext → Provider
```

采用：

```text
FinancialContext / FactPack
→ FinancialAssistantContextMapper
→ FinancialAssistantContextDTO
→ AssistantRequestDTO
→ Provider
```

### 原因

- 隐私最小化
- Provider 解耦
- schema 稳定
- 可测试
- 可审计

---

## ADR-010 — Provider 统一接收 AssistantRequestDTO

**状态：Accepted**

### 决策

Provider 不直接依赖 iOS Domain Model。

统一 transport contract。

---

## ADR-011 — 远程 AI 使用 Gateway，而非 iOS 直连 Bailian

**状态：Accepted / Security Critical**

### 决策

```text
iOS
→ FinSight AI Gateway
→ Bailian
```

### 禁止

Bailian Key 放入 iOS App。

---

## ADR-012 — Answer 使用 Draft → Validator → Domain Answer 双层模型

**状态：Accepted / Critical**

### 决策

```text
Provider
→ AssistantAnswerDraft
→ AssistantAnswerValidator
→ AssistantAnswer
→ UI
```

### 原因

LLM 输出属于不可信输入。

---

## ADR-013 — AI 金额必须可追溯

**状态：Accepted / Critical**

### 决策

AI 文案中的金额必须属于 FactPack / authorized facts。

否则触发 Validator error，例如：

```text
inventedAmount
```

### 经验

历史 `safeBalance` 金额虽然来自 deterministic explanation，但未加入 FactPack 时仍触发 validator。

结论：

> 来源正确还不够，必须可审计。

---

## ADR-014 — 不通过弱化 Validator 修复 FactPack 缺失

**状态：Accepted**

### 决策

遇到合法事实没有进入 FactPack，应修复 fact pipeline。

不优先使用：

- broad whitelist
- 关闭金额验证
- 允许 LLM 自由输出金额

---

## ADR-015 — AI Consent 细分管理

**状态：Accepted**

### 决策

使用 `AIDataConsent` 分别控制：

- screenshot image
- debt scan image
- financial context
- original image retention

### 原则

授权门禁必须存在于 Service / Domain flow，不仅是 UI。

---

## ADR-016 — 原图默认最小化保留

**状态：Accepted**

### 决策

`retainOriginalImages` 默认倾向 false。

原图只有在明确需要、已授权时才保留。

---

## ADR-017 — Structured Output 放弃 conditional polymorphic keyFactValue

**状态：Accepted**

### 背景

原 schema：

```text
allOf + if / then
```

按 type 动态要求不同字段。

Provider 生成阶段出现 shape drift / typeMismatch。

### 决策

改用固定 nullable shape：

```text
type
amount
currencyCode
textValue
percentValue
dateValue
```

全部字段固定 required，非对应字段 null。

### 禁止回退

除非通过实际 Provider 测试证明新的 polymorphic contract 足够稳定，并有回归测试。

---

## ADR-018 — Provider Transport DTO 与 Domain Model 隔离

**状态：Accepted**

### 决策

`ModelKeyFactValueDTO`、`ModelKeyFactDTO`、`ModelAssistantAnswerDraftDTO` 属于 Provider transport。

它们不是 iOS Domain Model。

### 原因

稳定 Provider schema 不应迫使 Domain Model 退化成 transport shape。

---

## ADR-019 — Home 与 Assistant 可共享 Engine，但不依赖 UI 缓存

**状态：Accepted**

### 决策

Home 与 Assistant 采用相同确定性 Engine 作为事实源。

Assistant Context 可以独立运行必要 Engine。

### 原因

Service 不依赖 UI 生命周期。

---

## ADR-020 — 远程 AI 不得阻断核心财务功能

**状态：Accepted / Implemented — RESOLVED 2026-08-19**

### 决策

AI outage 不得阻断：

- Transaction
- Account
- Debt
- Repayment
- CashFlow
- deterministic Home metrics

### 实现状态（2026-08-19）

**Implementation Status: RESOLVED / IMPLEMENTED**

修复方式：

- Home availability policy 归属 `HomeOverviewService` / application-domain orchestration。
- Provider 只报告 AI 成功/失败；**不再**决定 Home 是否 fallback。
- `FinancialAssisting` contract **已移除** `allowsDeterministicFallbackOnAIFailure`。
- Optional AI enrichment failure → `makeDeterministicSummary`（local deterministic fallback）。
- Core deterministic / repository failures **不被吞掉**，仍可导致 Home load failure。

验证：`HomeOverviewAIFailureIsolationTests` 覆盖：

- remote success
- remote failure + consent → deterministic fallback, Home 仍可用
- consent denied → 无 remote 调用
- core repository failure → Home load 仍失败
- mock provider regression

---

## ADR-021 — 本地持久化当前使用 JSON Store

**状态：Accepted for MVP**

### 决策

当前使用 JSON Document Store（已知 schema v4）。

SwiftData 尚未作为当前事实存储实现。

### 代价

- 大数据性能能力有限
- 无索引
- iCloud / 自动云备份 / 实时多设备同步 仍缺失

**更新（2026-08-21）：** 手动便携式加密 Backup v1 与 transactional full-replace Restore 已通过 ADR-033 落地；这不改变 JSON Store 仍是当前 live persistence 的事实，也不等于 iCloud 或自动备份已实现。

MVP 可接受，但需持续评估。

---

## ADR-022 — legacy Youshu store 不能简单重命名

**状态：Accepted**

### 背景

历史存储路径：

```text
Application Support/Youshu/youshu-store.json
```

### 决策

品牌改名 FinSight 不代表可以直接改变持久化路径。

如迁移：

1. 检测旧数据
2. copy / migrate
3. validate
4. commit new location
5. handle recovery

---

## ADR-023 — 正式产品名改为「知数 · FinSight」

**状态：Accepted**

### 决策

正式名称：

- 中文：知数
- 英文：FinSight

旧：

- 有数
- Youshu

不再用于新增正式品牌文案。

### 技术迁移

历史 `Youshu*` identifiers 是否保留或迁移，按兼容风险逐项决定，不做“大爆炸式 rename”。

---

## ADR-024 — FinSight AI Gateway 使用独立 Server 运行身份

**状态：Accepted**

### 当前已知

服务名：

```text
finsight-ai-gateway
```

生产环境运行用户：

```text
finsight
```

binary 与 env 权限应遵循最小权限原则。

---

## ADR-025 — ICP 备案完成前禁止公网暴露 Gateway

**状态：Accepted / Compliance Critical**

### 决策

ICP备案 pending 期间只做 ECS 内部部署。

禁止：

- 公网 DNS
- 公网 80
- 公网 443
- 公网 8080
- 其他绕过备案的公开访问方案
- iOS production wiring
- 真实 Bailian production smoke

### 说明

本决策是当前阶段硬约束。

备案完成后应新增新的 ADR / Release Decision，而不是静默解除。

---

## ADR-026 — Gateway health-ready 不等于 AI production-ready

**状态：Accepted**

### 决策

以下状态：

```text
systemd active
/health = 200
/ready = 200
provider = bailian
```

只证明 Gateway 进程 / readiness 达到对应定义。

不自动证明：

- 公网 HTTPS 可用
- iPhone 能访问
- 真实 Bailian 请求通过
- Production auth 正确
- Answer quality 达标
- 合规发布完成

---

## ADR-027 — 风险规则逐步集中到 FinancialRiskPolicyEngine

**状态：Accepted / Implemented**

### 目标

```text
Deterministic Engines
→ FinancialRiskPolicyEngine
→ FinancialRiskAssessment
→ AI explanation
```

### 实现事实（2026-08-19 Baseline Audit）

- `FinancialRiskPolicyEngine` 已在当前仓库落地。
- `FinancialRiskAssessmentService` 负责组装与评估。
- Regression：`FinancialRiskEvaluationGoldenParityTests`（29-case golden parity）等。
- 描述为 **IMPLEMENTED / regression-covered**；**不要**写 production-ready。

### 原因

避免风险规则：

- 散落在 UI
- 散落在 prompt
- 由 LLM 随机判断
- 多处重复阈值

---

## ADR-028 — AI warnings/actions 最终应以 deterministic assessment 为准

**状态：Accepted / Partially Implemented**

### 决策方向

AI 负责 narrative。

风险等级、warnings、actions 的事实基础优先来自 Policy Engine。

Provider 不能自由改变确定性 risk result。

### 实现事实（2026-08-19 Baseline Audit）

**PARTIAL — monthly summary 路径已落地：**

- `MonthlySummaryPolicyProjection.applyPolicyOwnership` 将 deterministic assessment 的 warnings / actions ownership 合并进 monthly summary draft。
- 测试：`MonthlySummaryPolicyProjectionTests` 等。

**尚未全覆盖：**

- ask / insight / purchase 等路径仍主要 mock 或局部实现。
- 非 monthly-summary 场景的 policy ownership 仍需扩展。

---

## ADR-029 — 测试门禁是架构的一部分

**状态：Accepted**

### 决策

核心修改必须覆盖：

- Domain 财务一致性
- CashFlow
- Debt
- DTO serialization
- no UUID / no merchant AI payload
- Assistant Validator
- Gateway schema / decoder
- Provider transport
- Golden / E2E（适用时）

AI 结构化输出问题不能仅靠 prompt 手工验证。

---

## ADR-030 — Project Context 文件成为 ChatGPT 长期协作真相源

**状态：Accepted**

### 文件

```text
01_Product.md
02_Architecture.md
03_Data_Model.md
04_Decision_Log.md
05_Current_Status.md
```

### 使用方式

以后开始新的 Chat 时优先引用这些文件和 Git 当前状态，而不是依赖超长历史聊天。

### 权威顺序

当信息冲突时：

```text
运行中的代码 / 自动化测试 / Git
        ↓
最新 ADR / Current_Status
        ↓
Architecture / Data_Model
        ↓
Product
        ↓
历史聊天
```

---

## ADR-031 — Provider KeyFacts use source-only ownership; Gateway materializes canonical values

**日期：2026-08-19**  
**状态：Accepted / Existing Architecture Formalized**

### Context

旧 structured output 方案允许 model 输出 KeyFact value。Provider generation 曾存在 polymorphic shape instability，同时让 LLM 对 canonical financial value 承担过多责任。

### Decision

Bailian / Provider model output 只选择或引用 authorized fact source。

Canonical KeyFact value **不由 LLM 生成**。

Gateway 根据 deterministic / authorized facts materialize：

- money
- text
- percent
- date

然后形成 iOS-facing `AssistantAnswerDraft`。

### Architecture

```text
Deterministic FactPack
        ↓
AI-safe request
        ↓
Bailian
        ↓
source-only keyFact references
        ↓
Gateway canonical materializer
        ↓
AssistantAnswerDraft
        ↓
AssistantAnswerValidator
        ↓
AssistantAnswer
```

### Consequences

- LLM 不拥有 canonical financial values
- 减少 Structured Output shape drift
- 强化 amount traceability
- 强化 ADR-013
- Provider transport 与 Domain 继续隔离
- Gateway materializer 成为重要 trust-boundary component
- materializer 必须有 schema / source / value regression tests

### Relationship

Supports: ADR-009, ADR-012, ADR-013, ADR-017, ADR-018

---

## ADR-032 — Stored Insight current-summary freshness and consent lifecycle

**日期：2026-08-20**  
**状态：Accepted / Implemented — RESOLVED 2026-08-20**

### Context

Stored Insight 的 Trust Boundary 在 ADR-032 开始之前已经 **VERIFIED SAFE**（validate-on-write → trusted persisted read）。

但 current-summary lifecycle 仍然存在与 Trust **相互独立**的问题：

- ledger facts 变化后，旧 `.summary` 仍可能继续作为 Home 当前摘要展示；
- Financial Risk Policy version 发生变化后，旧摘要可能不再代表当前风险结论；
- legacy summaries 缺少 reconciliation provenance；
- revoke financial-context consent 后，之前保存的 AI summary 仍可能继续显示在 Home。

必须明确：

```text
Freshness problem != Trust / Validator bypass problem
```

Freshness 问题 **不是** Stored Insight 未经 Validator 写入的问题。

### Decision

ADR-032 采用 **方案 A**。

#### A. Monthly `.summary` 是 current-state cache

Home 使用的 persisted monthly `.summary` 是 **current-state AI enrichment cache**，而不是永久代表当前财务状态的历史结论。

#### B. Deterministic Freshness Provenance

Freshness 使用：

```text
MonthlySummaryFacts
+
FinancialRiskAssessment
+
policyVersion
        ↓
canonical freshness input
        ↓
opaque SHA-256 digest
```

持久化的最小 provenance 为：

- freshness schema version
- policy version
- opaque digest

**不得**持久化 raw canonical token。

#### C. Freshness Resolution

Home 对 stored `.summary` 的判断规则：

```text
current metadata match
→ fresh

digest mismatch
→ stale

policyVersion mismatch
→ stale

legacy metadata == nil
→ stale / unverifiable

unsupported freshness schema
→ stale / unverifiable
```

所有 `stale / unverifiable` 都按 **cache miss** 处理。

不得使用 `generatedAt` / TTL 作为 freshness correctness 的主要判断机制。

不得扫描更早的历史 summary，然后因为 fingerprint 恰好匹配当前 facts 就重新“复活”旧 summary。

#### D. Trust 继续使用 validate-on-write

Stored summary read path **不**重新执行 `AssistantAnswerValidator`。

Trust 与 Freshness 是两个独立维度。

Trust：

```text
Provider Draft
→ Validator
→ persisted validated snapshot
```

Freshness：

```text
current deterministic facts
→ current freshness metadata
→ compare persisted metadata
```

stale **不代表** untrusted。

#### E. Consent 是独立 eligibility gate

Home 使用 current AI summary 必须同时满足：

```text
Consent eligible
AND
Freshness eligible
```

当 `allowFinancialContextToAI == false` 时：

- 不在 Home 展示 persisted AI monthly summary；
- 不发送新的 financial-context Provider 请求；
- 使用 deterministic Home summary；
- 保留历史 persisted insights。

Consent revoke **不等于**自动删除历史 AI 内容。

Consent **不进入** freshness digest。

重新开启 Consent 后：

```text
fresh summary
→ 可以复用

stale summary
→ 正常 regenerate
```

#### F. Proactive Insights

Proactive historical insights **不纳入** ADR-032 的 Home monthly-summary freshness contract。它们继续保持 **historical semantics**。

#### G. Compatibility

JSON Store 继续保持 **schema v4**。

因为 `freshnessMetadata` 是 optional，legacy records 缺少字段时可以安全 decode 为 nil。

**本次不需要 schema migration。**

#### H. Production Consent Wiring Invariant

Step 5A audit 确认 production Home 始终通过：

```text
FinSightApp
→ AppDependencies
→ AIDataConsentService
→ OverviewServiceContainer
→ HomeOverviewService
```

获得真实 `AIDataConsentService`。

不存在 persisted consent record 时：**deny-by-default**。

Optional nil consent service 默认值仍然存在，但仅属于 **test / dev API surface**；当前 production 不可达。

未来新增 production factory / composition 时：**不得省略 AIDataConsentService**。

### Consequences

**正向结果：**

- financial facts / policy 改变后，stale Home AI summary 不再继续作为当前摘要使用；
- Consent revoke 后，过去 AI Home summary 不再继续出现在当前 Home；
- Validator 保持原有强度；
- freshness metadata 不复制原始财务事实；
- historical insight 可以继续保留；
- legacy JSON records 保持兼容。

**成本 / trade-off：**

- Consent allowed 的 Home load 需要运行 deterministic freshness / risk assembly；
- fingerprint algorithm 需要显式 version；
- 未来 freshness schema 变化时，不支持的旧 cache 会自然失效；
- optional nil consent dependency 仍是 test/dev API footgun，必须继续保证 production composition 不可达。

### Relationship

Supports / relates to: ADR-012, ADR-013, ADR-015, ADR-020, ADR-021, ADR-027, ADR-031

---

## ADR-033 — Portable encrypted Backup v1 and transactional full-replace Restore

**日期：2026-08-21**  
**状态：Accepted / Implemented — VERIFIED 2026-08-21**

### Context

FinSight 当前 live persistence 仍是 JSON Document Store（ADR-021，schema v4）。在 ADR-033 之前，用户缺少一条 **用户可控、可携带、可加密** 的财务事实恢复路径；换机 / 卸载 / 本地数据丢失风险无法仅靠 live store 解决。

Backup / Restore v1 的目标不是 Cloud Sync，也不是 human-readable Export，而是在 **Files 生态** 中提供 **manual portable encrypted backup + full-replace restore**，并严格遵守 privacy / consent / transactional persistence 边界。

### Decision

#### A. Backup ≠ Export ≠ Cloud Sync

Backup v1 是：

```text
manual
portable
encrypted
user-controlled
Files-based
full-replace restore
```

Backup v1 **不是**：

- human-readable Export
- Cloud Sync
- multi-device live synchronization
- FinSight 实现的 CloudKit / 自动 iCloud 备份

用户可通过系统 Files 将 `.finsightbackup` 保存到 On My iPhone / iCloud Drive / 其他 Files provider，但 FinSight **不实现** CloudKit sync、automatic iCloud backup、multi-device merge/sync。

不得将 Backup v1 描述为 “iCloud support”。

#### B. Backup content boundary

Backup v1 是 **financial-facts-oriented portable payload**，不是 raw `YoushuSnapshot` 拷贝，也不是 JSON Store schema 的直接镜像。

当前 backed-up durable facts（`BackupPayloadV1` / `BackupFinancialDataV1`）包括：

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

实体间关系所需的 UUID 可保留在加密 artifact 内，用于 restore 后重建关系。

**不得** 声称 Backup 包含 entire `YoushuSnapshot`。

#### C. Explicit exclusions（privacy / trust lifecycle）

Backup v1 **故意不** backup / restore / carry forward：

```text
FinancialInsight
AIDataConsent
AIRecognitionRecord
MediaArtifact
PendingDebtLink
SuspectedDebt
```

Restore 后：

```text
User.debtImportInProgress = false
```

后果：

- `AIDataConsent` 缺失 → `AIDataConsentService.fetchOrDefault` → **deniedDefault**
- 历史 AI insight **不** 通过 backup 迁移
- restore **不** 触发 remote AI generation

这是 **intentional privacy/trust lifecycle behavior**，不是 data loss bug。

Derived read models **不是** backup facts，restore 后由 engines 自 restored facts 重算，例如：

```text
FinancialSummary
CashFlowProjection / CashFlowRisk
FinancialRiskAssessment
HomeOverview
其他 deterministic read models
```

#### D. Encryption contract（Backup Format v1）

```text
PBKDF2-HMAC-SHA256
600,000 iterations
256-bit key
AES-256-GCM
random salt
random nonce
authenticated envelope
```

v1 参数：

```text
salt   16 bytes
nonce  12 bytes
tag    16 bytes
whole backup file maximum 64 MiB
```

Backup format version（`BackupPayloadV1.formatVersion`）**独立 versioning**，与 JSON Store schema version **解耦**。

`sourceStoreSchemaVersion` 仅为 provenance metadata，**不是** restore compatibility authority。

#### E. Passphrase contract

- non-empty passphrase enforced below UI
- exact string is cryptographic input
- **no trim / normalization**
- **no complexity policy in v1**
- whitespace-only passphrase is **not forbidden**（non-empty only）
- passphrase **not persisted**（无 UserDefaults / AppStorage / Keychain / logging）
- FinSight **cannot recover** a lost backup passphrase

#### F. Restore = FULL REPLACE

Restore v1 = **FULL REPLACE**，不是 merge / import-additive / record-by-record reconciliation。

Successful restore **removes** current-device-only financial records not present in backup candidate。

未来若改为 merge，**必须** 新 ADR，不得静默改变 v1 语义。

#### G. Untrusted external artifact

External backup file remains **untrusted** even after Files selection。

Restore pipeline：

```text
encrypted Data
→ BackupCodec.decode / authenticate
→ BackupPayloadV1Validator
→ BackupRestoreCandidateBuilder
→ BackupRestoreCandidateValidator
→ transactional store replacement
```

Preflight：

- uses same validation pipeline
- **performs no store mutation**

Commit **does not trust** preview / cached plaintext candidate / preflight token。

Commit **independently re-decodes and re-validates** original encrypted `Data`。

#### H. Exact bytes preview-to-commit（anti-TOCTOU）

```text
Files URL
→ bounded security-scoped read
→ immutable encrypted Data
→ preflight
→ destructive confirmation
→ restore commit using the SAME Data
```

External URL **not re-read** after preview。

Security-scoped access exists **only during bounded read**。

No plaintext temporary backup file。

#### I. Transactional persistence

`YoushuStore` actor restore transaction：

```text
retain previous snapshot
→ encode candidate using current store rules
→ atomic candidate write
→ re-read actual persisted file
→ decode through current store path
→ verify candidate
→ publish candidate in-memory only after verification
```

**禁止** restore 实现为：

```text
wipeAllUserData()
→ reconstruct records
```

Post-write verification failure：

```text
rollback previous persisted representation
→ re-read
→ verify rollback
```

Memory remains previous until successful commit。

#### J. Critical rollback failure

三类 restore failure：

```text
validationFailure
commitFailure          → rollback verified / known previous state
criticalPersistenceFailure → rollbackFailed
```

`rollbackFailed` 表示 durability state **cannot be confidently asserted**。

必须 distinguishable from ordinary restore failure。

UI **must not** show normal success or assume known-good persisted state。

No automatic destructive recovery in v1。

#### K. Application refresh contract

Every successful full-replace restore requires application data refresh，**even if restored `User.id` is unchanged**。

Reason：same identity ≠ same financial data。

Current behavior：

```text
restore success
→ AppSession resync from store
→ applicationDataRevision bump
→ transient ViewModel reset
→ financial presentation reload
→ MainTabView presentation subtree recreation
```

If restored user IDs differ：restored backup identity becomes authoritative。**No User ID remapping**。

`BackupRestoreResult.requiresApplicationReload == true` on successful full-replace restore。

`userIdentityChanged` is separate identity-handoff metadata。

#### L. UI safety contract

**Create：**

```text
passphrase + confirmation
→ encrypted backup
→ Files exporter
```

**Restore：**

```text
Files importer
→ bounded read
→ passphrase
→ safe preflight preview
→ explicit destructive confirmation
→ transactional restore
→ application refresh
→ success
```

File selection alone **can never mutate** live financial data。

Preview exposes safe metadata / counts only — **not** financial amounts, internal IDs, merchant details, or notes in v1 preview contract。

#### M. Verification status（2026-08-21）

Shared Swift（Windows gate）：

```text
Foundation   10 PASS
Domain      362 PASS
Data         99 PASS
AI           61 PASS
Total       532 PASS
```

Apple GitHub Actions final gate（run **32443787799**, HEAD `967c0c5`）：

```text
YoushuUITests       10 PASS
YoushuDataTests     99 PASS
YoushuDomainTests  362 PASS
Total              471 PASS
```

Apple environment：Xcode **16.4**, iOS Simulator。

Processed Info.plist：`app.finsight.backup` / `.finsightbackup` verified。

**未验证：** physical iPhone Files smoke, TestFlight, App Store release-ready。

Windows 与 Apple 测试是 **两个 platform gates**，大量 Domain/Data tests overlap — **不得** 将 532 + 471 相加为 “unique tests”。

Physical-device Files smoke：**NOT RUN** — **PRE-RELEASE MANUAL ACCEPTANCE GATE**。

### Consequences

**正向结果：**

- 用户提供 manual migration / recovery path（前提是曾创建并保留 backup）
- restore 保持 privacy lifecycle：AI consent reset、historical insight 不迁移
- external artifact treated as untrusted until full validation + transactional commit
- same encrypted bytes preflight→commit；no TOCTOU via URL re-read

**成本 / trade-off / 仍开放：**

- 无 automatic backup / CloudKit / live sync
- 无 human-readable Export
- 卸载仍可能丢失 **未外置保存** 的 live local data
- physical-device Files smoke 尚未执行
- large JSON Store performance 仍 unverified
- lost passphrase = unrecoverable backup

### Relationship

Supports / relates to: ADR-015, ADR-016, ADR-021, ADR-022, ADR-029, ADR-030

ADR-033 adds the portable recovery layer **on top of** ADR-021 JSON Store; it does not replace or rename live store path rules（ADR-022 仍有效）。

---

## ADR-034 — Local full-data wipe uses monotonic deletion and post-wipe session bootstrap

**日期：2026-08-21**
**状态：Accepted / Implemented — VERIFIED 2026-08-21**

### Context

FinSight user-owned local state is no longer confined to one persistence representation.

Current relevant persistence spans:

```text
JSON Document Store
+
app-private retained original-image binaries
```

A full local-data wipe therefore cannot truthfully be modeled as one atomic transaction across JSON persistence and filesystem media.

Attempting rollback by recreating already-deleted sensitive data would be contrary to the privacy objective.

A successful store wipe also deletes the active persisted `User`; leaving `AppSession` and ViewModels bound to that deleted identity would create stale/invalid application state.

### Decision

#### A. Wipe is local user-data deletion

Full wipe targets the selected/current user's FinSight local data.

It includes current-user persisted financial / AI / privacy records and retained original-image binaries.

It does NOT automatically delete:

```text
external user-controlled .finsightbackup files
remote/server data
```

Wipe is distinct from:

```text
Consent revoke
Backup
Restore
Export
remote account deletion
```

#### B. Monotonic deletion

Deletion uses monotonic privacy semantics:

```text
once sensitive data is successfully deleted
→ it is not recreated merely to simulate rollback
```

Current implementation ordering:

```text
attempt user-scoped retained-media binary cleanup
→ canonical users.delete / YoushuStore.deleteUser cascade
```

Safe deletion continues where possible even if an independent deletion component fails.

#### C. Result taxonomy

The operation distinguishes:

```text
complete
mediaCleanupIncomplete
persistentDeletionIncomplete
```

Semantics:

##### complete

```text
user/store deletion complete
+
retained original cleanup complete
```

##### mediaCleanupIncomplete

```text
user/store deletion complete
+
one or more retained originals could not be removed
```

Consequences:

- deleted financial data is NOT restored
- deleted user remains deleted
- application may bootstrap a new/clean session
- leftover media cleanup remains observable/retryable against the wiped user identity

##### persistentDeletionIncomplete

```text
canonical JSON/user cascade did not complete
```

Consequences:

- do not claim full wipe success
- do not pretend a new empty session has replaced authoritative remaining store state

#### D. Cross-user isolation

Wipe is user-scoped.

Deleting User A must not delete User B:

- financial facts
- consent
- AI insights
- recognition state
- media metadata/binaries

#### E. Post-wipe session bootstrap

After successful persistent deletion:

```text
deleted active user
→ AppSession bootstrap
→ valid existing other user OR newly-created empty local user
→ application data revision bump
→ transient state reset
→ financial presentation reload
```

The app must not continue operating with:

```text
currentUserId == deletedUserId
```

Normal successful wipe must not require app restart.

#### F. Consent / AI lifecycle

Full wipe deletes the old user's:

```text
AIDataConsent
FinancialInsight
AIRecognitionRecord
```

A newly bootstrapped user resolves to deny-by-default consent.

This differs from ordinary financial-context Consent revoke, which preserves historical `FinancialInsight`.

#### G. Backup relationship

ADR-033 remains unchanged.

External `.finsightbackup` artifacts are user-controlled portable backups and are not deleted by local wipe.

A later restore from such a backup remains permitted under ADR-033:

```text
financial facts restored
AIDataConsent not restored
FinancialInsight not restored
MediaArtifact / retained originals not restored
```

#### H. Persistence compatibility

ADR-034 does NOT change:

```text
JSON schema v4
Application Support/Youshu/youshu-store.json
BackupPayloadV1
Backup format version
```

### Consequences

Positive:

- deletion behavior is truthful across JSON + filesystem persistence
- privacy deletion is not weakened by artificial rollback
- partial media cleanup is visible/retryable
- stale deleted-user sessions are prevented
- external user backups remain under user control

Trade-offs:

- wipe is not a cross-resource atomic transaction
- partial cleanup states must be represented
- media cleanup may need retry after financial/store deletion has completed

### Relationship

Supports / relates to: ADR-015, ADR-016, ADR-021, ADR-030, ADR-033

Do **not** merge ADR-034 into ADR-033.

Backup/Restore and local wipe are separate lifecycle contracts.

---

# ADR 变更模板

以后新增：

```markdown
## ADR-XXX — 标题

**日期：YYYY-MM-DD**
**状态：Proposed / Accepted / Deprecated / Superseded**

### Context
为什么出现这个问题？

### Decision
最终决定是什么？

### Alternatives
考虑过什么？

### Consequences
会带来什么代价？

### Supersedes
如果替换旧 ADR，写编号。
```
