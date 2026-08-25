# 知数 · FinSight — Decision Log

> 文档角色：架构 / 产品重大决策记录（ADR Index）  
> 版本：v1.0  
> 更新日期：2026-08-24
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

当前使用 JSON Document Store（live schema 以代码 `YoushuSnapshot.currentSchemaVersion` 为准）。

**更新（2026-08-24）：** live JSON Store 现为 **schema v5**（ADR-036 新增 `confirmedImportProvenances`；v4 → v5 默认空数组，既有财务事实保持不变）。SwiftData 尚未作为当前事实存储实现。

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

JSON Store 在本 ADR 接受时保持 **schema v4**。

因为 `freshnessMetadata` 是 optional，legacy records 缺少字段时可以安全 decode 为 nil。

**本次不需要 schema migration。**

**更新（2026-08-24）：** live store 后经 ADR-036 升至 schema v5（provenance collection）；ADR-032 的 optional freshness 语义不变。

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

**更新（2026-08-24 / ADR-036）：** live store 新增的 `ConfirmedImportProvenance` **同样排除于 Backup v1**。这是后续 ADR-036 对 Backup v1 exclusion 合同的延伸，**不是** 回溯改写 ADR-033 原接受范围。Restore 后 provenance 重置为空；财务事实仍按 Backup v1 恢复。

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
Application Support/Youshu/youshu-store.json
BackupPayloadV1
Backup format version
```

**更新（2026-08-24）：** live JSON Store 后经 ADR-036 升至 schema v5。Full local wipe 仍移除当前用户全部本地状态，包括 `ConfirmedImportProvenance`；这符合 ADR-034 的 monotonic wipe 语义，不改写本 ADR 原决策。

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

## ADR-035 — Production observability uses privacy-safe correlated telemetry and stage-based error taxonomy

**日期：2026-08-22**
**状态：Accepted / Implemented — VERIFIED 2026-08-22**

### Context

Before this ADR, production observability was incomplete and fragmented:

```text
error semantics split across iOS and Gateway
request correlation existed (X-Youshu-Request-Id) but was not a formal observability contract
token usage existed only partially
failure stages were not consistently classified
privacy-safe production logging needed explicit guarantees
```

The product still needed a canonical taxonomy, correlated request identity, and allowlisted sinks that cannot leak financial payloads or fail AI/business work.

### Decision

#### A. Canonical taxonomy

Production observability uses orthogonal dimensions:

```text
failureStage
errorCode
failureClass
retryability
outcome
```

Outcomes:

```text
success
degraded
failed
cancelled
```

Canonical failure stages:

```text
clientPreflight
consent
requestSerialization
clientTransport
gatewayAuth
gatewayRequestValidation
providerTransport
providerHTTP
providerStructuredOutput
factMaterialization
gatewayResponseEncoding
clientResponseDecode
assistantValidation
insightPersistence
unknown
```

Trust-boundary stages remain distinct:

```text
providerStructuredOutput
≠ factMaterialization
≠ assistantValidation
```

iOS does **not** invent Gateway-internal stages from public error envelopes. For Gateway envelopes:

```text
iOS preserves stable errorCode
iOS does not fabricate Gateway-internal failureStage
requestId is used for cross-system join
```

#### B. Cross-platform taxonomy parity

Shared semantic fixture:

```text
contracts/observability_taxonomy_defaults.json
```

Swift (`YoushuFoundation`) and Go (`internal/observability`) defaults must stay aligned with this fixture. No code generation is required.

#### C. Request correlation

```text
one logical iOS AI operation
→ one opaque requestId

requestId
→ iOS observability event
→ X-Youshu-Request-Id
→ Gateway ai_request event
```

iOS retry keeps the same logical `requestId`. Gateway emits one `ai_request` terminal event per HTTP attempt.

The header name remains:

```text
X-Youshu-Request-Id
```

This is not a branding migration.

Request IDs are opaque UUIDs and are not derived from user or financial IDs.

Verified correlation is local/component integration (iOS client tests + Gateway httptest), not live Swift↔Go production traffic.

#### D. Gateway terminal telemetry

The production Gateway emits one canonical:

```text
event = ai_request
```

per AI HTTP request.

Allowlisted metadata includes:

```text
requestId
operation
outcome
durationMs
retryCount
provider / model / status
failureStage
errorCode
failureClass
retryability
schemaStage
token usage when actually returned
gatewayVersion
```

Current sinks are **local structured production-safe logs**. ADR-035 does **not** deploy remote log aggregation or a dashboard.

#### E. iOS telemetry

iOS observes:

```text
consent
requestSerialization
clientTransport
clientResponseDecode
assistantValidation
insightPersistence
```

plus stable Gateway envelope error codes (with `failureStage=unknown` when the envelope does not expose an internal Gateway stage).

iOS must not log:

```text
question
FinancialContext
FactPack
merchant
note
source IDs
raw response
Validator associated amount/key values
Authorization / token
```

#### F. Privacy contract

Production observability is allowlisted. Forbidden by default:

```text
raw financial payload
prompt
question/body
merchant
note
financial UUID / sourceIds
raw image
Provider raw response
API key
Authorization / client token
arbitrary localized error strings
```

Debug-only raw diagnostics remain explicitly gated and unavailable in production default behavior.

Observability is **not** a new Consent or AI-data transmission channel.

#### G. Retryability semantics

Retryability describes effective operation/path policy, not theoretical recoverability.

```text
networkUnavailable  → notRetryable
transportFailure    → notRetryable
gatewayRateLimited  → notRetryable
providerRateLimited → notRetryable
providerTimeout     → retryable
providerUnavailable → retryable
internalError       → retryable
unknown             → notRetryable
```

Gateway internal retry count and iOS client retry count are **separate scopes**. Do not equate them.

#### H. Token / cost ownership

```text
Gateway:
real Bailian token usage recorded when returned

iOS:
does not duplicate token usage because the public success envelope does not expose it

cost:
absent
```

No price table or estimated cost is implemented.

#### I. Home degraded semantics

This clarifies ADR-020 + ADR-032; it does not supersede them.

```text
Provider failure
→ deterministic fallback
→ Home available
→ degraded

Validator failure
→ deterministic fallback
→ Home available
→ degraded

optional monthly-summary cache persistence failure
→ validated ephemeral AI summary
→ Home available
→ insightPersistence / persistenceFailure / degraded

core repository / deterministic failure
→ Home failure
```

Monthly `.summary` remains a current-state AI enrichment cache, not a core financial fact.

A failed cache write:

```text
does not create fake freshness
does not mutate stale cache into fresh
next load follows normal cache-miss behavior
```

Explicit `FinancialAssistantService` persistence operations may still fail their own operation.

#### J. Sink failure

Observability/logging failure must never fail the AI or business operation.

```text
iOS ObservabilityLogSink
→ local structured safe log

Gateway SafeLog
→ local structured safe log
```

No third-party vendor or remote aggregation is part of ADR-035.

#### K. Scope / compliance

ADR-035 does **not** mean:

```text
public Gateway production-ready
real Bailian production smoke completed
remote aggregation / dashboard deployed
iOS public production AI wiring completed
ICP constraint removed
```

ICP remains pending. Public Gateway exposure remains prohibited.

### Verification

Verified candidate:

```text
HEAD 385647b5c1d4959d449d182f66ec3845d7a548b2

Windows:
Foundation 30 / Domain 399 / Data 102 / AI 79
Total 610 PASS
Failed 0
swift build -c release PASS

Gateway:
go test ./... PASS
go build ./... PASS

Apple:
workflow ios-apple-gate.yml
run 32555839840
Xcode 16.4 (16F6)
YoushuUITests 36 / YoushuDataTests 102 / YoushuDomainTests 399
Total 537 PASS
Failed 0
```

Windows and Apple are **separate platform gates**. Do not add 610 + 537 as unique tests.

### Relationship

Supports / relates to: ADR-009, ADR-012, ADR-013, ADR-015, ADR-020, ADR-025, ADR-026, ADR-029, ADR-031, ADR-032

Does **not** supersede them.

ADR-035 clarifies Home optional-cache durability under ADR-020 / ADR-032. It does not change Validator, Consent, Gateway materialization ownership, ICP restrictions, or “health-ready ≠ production-ready”.

---

## ADR-036 — Confirmed import provenance uses local cryptographic source fingerprints; per-image Provider semantics remain deferred

**日期：2026-08-22**
**状态：Accepted / Implemented — VERIFIED 2026-08-24**

### Context

Recognition Quality & Import Reliability Steps 1–4A closed **same-flow** import reliability (stale recognition, consent races, confirmation idempotency, partial batch semantics). Step 4B audited remaining gaps:

- Transaction cross-session exact-image dedup is only **partially** possible with current persisted fields.
- Debt cross-session exact-scan provenance is **not safely representable**.
- `MediaArtifact` / `AIRecognitionRecord` are workflow/audit metadata, **not** durable confirmed-import provenance.
- Current `sourceImageId` / `MediaLifecyclePolicy.makeImageId` is a **non-cryptographic media lifecycle identifier** and must **not** become authoritative exact-input identity.
- True Debt per-image Provider outcome semantics cannot be frozen while production Debt scanning still uses
  `MockAIProvider` (no Debt pixel-reading recognizer).
- Stale/cancelled recognition may still write durable metadata **before** Application operation-currentness acceptance.

At ADR-036 verification, production image recognition remained `MockAIProvider`. ADR-037 Step 3 later supersedes
that runtime statement for Transaction recognition only; the real accuracy baseline remains **NOT ESTABLISHED**.

### Decision

#### A. Separate durable model — `ConfirmedImportProvenance`

Introduce a **local persisted** concept `ConfirmedImportProvenance`:

> Records that one **confirmed import operation** produced one or more **authoritative financial entities** from a specific **exact local input set**.

It is **NOT**:

```text
recognition output / TransactionDraft / DebtCandidate
AIRecognitionRecord
MediaArtifact
Transaction / Debt (financial facts)
Provider transport DTO
production observability payload
```

Minimum semantic fields (implemented conceptually; Swift names follow the Domain model):

```text
user scope
import capability (screenshot transaction / debt scan batch)
cryptographic source fingerprint(s) — per input document/image
operation / batch fingerprint — canonical, versioned, order-insensitive, multiplicity-sensitive
confirmed entity references (typed refs to Transaction / Debt ids)
confirmedAt
```

**Cardinality:**

- One confirmed import operation may reference **multiple** confirmed entities (e.g. debt scan batch → Debt A, B, C).
- Provenance must **not** falsely assert image-level causality (e.g. “image A caused Debt B”) when recognition cannot prove it.
- Partial batch confirm: initial provenance records **only successfully persisted** entities; later retry may **extend** the same operation’s entity set.

**Creation eligibility:**

```text
Recognition Result != Confirmed Import
```

`ConfirmedImportProvenance` is created/updated **only after**:

```text
user confirmation
+
authoritative Transaction / Debt persistence success
```

Not after: Provider success alone, draft display, recognition metadata write, or abandoned review.

#### B. Cryptographic provenance fingerprint (local-only)

Explicitly separate:

```text
MediaArtifact.id / sourceImageId  →  media lifecycle identifier (NOT authoritative exact-input identity)
ConfirmedImportProvenance fingerprint  →  full-file SHA-256 of entire input bytes (local-only)
```

**Transaction:** one screenshot → one full-file SHA-256.

**Debt batch:** each input document/image → full-file SHA-256; plus an **operation/batch fingerprint** that is:

```text
order-insensitive: [A,B] == [B,A]
multiplicity-sensitive: [A,A,B] != [A,B]
versioned / canonical encoding before hash (implementation must not use fragile plain-string concat)
```

Fingerprint data is **local-only**. It is **NOT** AI payload, Consent expansion, original-image retention, or observability payload.

**No new `AIDataConsent` field** is required.

#### C. Transaction exact re-import product rule

```text
exact cryptographic input match
+
existing confirmed Transaction relation
→ WARN user
→ allow navigation / view of existing record
→ explicit user override may continue import
```

Do **NOT** hard-block. Do **NOT** use merchant/amount/date/category as duplicate identity. This addresses **exact-source accidental duplication only**, not semantic duplicate detection.

#### D. Debt exact re-scan product rule

Debt is a **long-lived** financial object, not a point-in-time ledger event.

```text
exact batch fingerprint previously confirmed
→ indicate prior scan
→ surface related Debt references where available
→ user may continue
```

Do **NOT** hard-block. Do **NOT** define “same image = duplicate Debt” as universal rule. Semantic target: **prior scan / reconciliation candidate**, not pure duplicate prevention.

**Deferred:** field-level reconciliation/merge (outstanding vs currentDue overwrite, statement period rules) — separate future **Debt Reconciliation** decision.

#### E. Recognition metadata lifecycle target

Implemented recognition-metadata boundary:

```text
Provider returns recognition result
        ↓
Application checks operation generation / currentness
├─ stale / cancelled / obsolete → discard in memory; NO durable recognition metadata
└─ current → accept into active review lifecycle → THEN eligible for recognition/media metadata persistence
```

Applies conceptually to **ScreenshotBookkeeping** and **DebtScanner**.

`AIRecognitionRecord` is **not** repurposed as durable confirmed-import provenance. It may remain workflow/audit metadata. Stale Tasks need **not** be written as `.discarded`; default target is **do not persist** recognition metadata before Application acceptance.

#### F. Backup v1 unchanged — ADR-033 not superseded

```text
BackupPayloadV1 remains unchanged.
ConfirmedImportProvenance is excluded from Backup v1.
```

After ADR-033 restore:

```text
financial facts restored
AIDataConsent → deniedDefault
AIRecognitionRecord / MediaArtifact exclusions unchanged
ConfirmedImportProvenance absent → duplicate / prior-scan memory resets
```

This is **intentional** for Backup v1, not data corruption. Cross-device provenance requires a future **Backup v2 / separate ADR**.

#### G. Delete / wipe releases provenance

**Transaction deleted:** remove its provenance entity relation; if no remaining confirmed entity refs, remove provenance record → exact image may import again.

**Debt deleted:** remove its provenance entity relation → re-scan/reconciliation may occur again.

**Full local wipe (ADR-034):** provenance removed with user-owned local state → duplicate/prior-scan memory resets. No permanent tombstone solely to block future import.

#### H. Per-image Provider contract — explicitly deferred

```text
Per-image Provider outcome taxonomy: DEFERRED UNTIL REAL PIXEL-READING PROVIDER
```

Current implemented contract remains:

```text
DebtScanning.scanDebts(from: [BillDocument]) → [DebtCandidate]
```

Do **NOT** mark RQ-06 closed. Do **NOT** freeze enums (unreadable / unsupported / noRelevantDebt / providerFailure) today.

Future real Provider may introduce Provider-specific DTO → normalized Application recognition batch result, then validated document-level outcomes.

**Rejected as default architecture:** one Provider request per Debt document merely to obtain per-image errors (cross-document context, cost, rate limits, multi-page aggregation quality).

#### I. Write ordering / failure semantics (implemented)

```text
authoritative financial fact persists successfully
        → then eligible to record/update ConfirmedImportProvenance
```

If financial fact persists but provenance write fails:

```text
financial fact remains authoritative
provenance failure → degraded dedup / prior-scan memory only
do NOT roll back financial fact to simulate atomicity
```

(JSON Store has no multi-entity transaction API today.)

### Alternatives considered

| Alternative | Rejected because |
|-------------|------------------|
| Reuse `Transaction.sourceImageId` as dedup key | Non-cryptographic; not on Debt; lifecycle ≠ provenance |
| Reuse `AIRecognitionRecord` / `MediaArtifact` | Excluded from Backup v1; ephemeral; debt batch links first image only |
| Hard-block exact re-import | Blocks legitimate correction / reconciliation flows |
| Per-document Provider calls now | Loses cross-page context; Mock-driven false closure |
| Include provenance in Backup v1 | Would reopen ADR-033; deferred to Backup v2 decision |
| Persist provenance on recognition success | Violates Recognition Result ≠ Confirmed Import |

### Consequences

**Implemented (verified 2026-08-24):**

- Local exact-source warn+allow (Transaction) and prior-scan signal (Debt) are durable across sessions on the same device.
- Restore from Backup v1 intentionally resets provenance memory.
- Recognition services split “return unpersisted result” vs “persist metadata after Application acceptance”.
- JSON Store schema **v5** persists `confirmedImportProvenances`.
- Delete / wipe releases provenance refs; last-ref removal deletes the provenance row.

**Still unchanged / still deferred:**

- Per-image Provider outcome semantics (RQ-06) remain **DEFERRED**.
- At ADR-036 verification, production image recognition remained `MockAIProvider`; ADR-037 Step 3 later switches
  Transaction recognition only, while Debt scanning remains Mock.
- Real recognition accuracy baseline remains **NOT ESTABLISHED**.
- Debt field-level reconciliation / semantic Transaction duplicate detection / Backup v2 portable provenance remain **not decided by this ADR**.

### Deferred items (explicit — not decided by ADR-036)

```text
real OCR / Vision / Bailian image-recognition Provider choice
Gateway image-recognition endpoint
per-image outcome enum semantics
Debt field merge / reconciliation policy
semantic Transaction duplicate detection
Backup v2 / portable provenance
Cloud sync
```

### Relationship

Supports / relates to: ADR-003, ADR-015, ADR-016, ADR-021, ADR-022, ADR-029, ADR-033, ADR-034

**Does NOT supersede ADR-033.** Local durable provenance ≠ Backup-v1 portable state.

ADR-036 does **not** change BackupPayloadV1 shape, local wipe monotonic semantics (ADR-034 extends naturally), or Consent fields. Live JSON Store schema is **v5** solely for the provenance collection.

### Verification

Implementation closed and verified on **2026-08-24** against candidate `153a23d2d7dbfa570c063156932a646340f0f3f0`.

```text
Windows:  746 PASS (Foundation 30 / Domain 493 / Data 114 / AI 109); Failed 0
          swift build -c release PASS

Apple:    ios-apple-gate.yml run 32684027127
          665 PASS (YoushuUITests 58 / YoushuDataTests 114 / YoushuDomainTests 493); Failed 0
          Xcode 16.4 (16F6), macos-15-arm64

Gateway:  go test ./... PASS
          go build ./... PASS
```

Acceptance-time historical baseline (docs-only Step 4C, 2026-08-22): 677 PASS; Apple gate then **NOT RUN**. That is no longer the current checkpoint.

No real Bailian production image-recognition smoke was performed. `MockAIProvider` is not baseline-eligible.

---

## ADR-037 — Transaction Recognition v1 uses on-device pixel recognition with deterministic parsing and baseline-gated production eligibility

**日期：2026-08-24**
**状态：Accepted / Implemented — VERIFIED 2026-08-24 (Steps 1–3)**

### Context

At ADR start, production `TransactionExtracting` used `MockAIProvider`; it did not read image pixels and no real
Transaction-recognition accuracy baseline exists. The shared contract previously returned only a
`TransactionDraft` or an error, so it could not distinguish a supported review draft from a readable but
unsupported layout, unreadable input, or an operational failure.

### Decision

Transaction Recognition v1 uses this dependency direction:

```text
on-device pixel-reading recognition (Apple Vision initially; Infrastructure-only)
→ platform-neutral RecognizedTextSpan values
→ deterministic TransactionRecognizedTextParsing implementation
→ TransactionRecognitionOutcome
→ reviewable TransactionDraft
→ existing Application currentness gate
→ existing user confirmation
→ authoritative Transaction persistence
→ ConfirmedImportProvenance
```

Shared Domain/Application code must not expose Apple Vision, `CGImage`, or `UIImage` types. The minimum
recognized-text value contains text plus optional confidence; geometry is deliberately omitted until a
deterministic parser proves it necessary. Raw recognized text is transient by default.

Single-image Transaction outcomes are frozen as:

- `recognized`: recognition produced a reviewable draft; it does not mean persisted, confirmed, correct,
  authoritative, or provenance-recorded.
- `unsupported`: the readable input is not a supported Transaction screenshot/layout/type and must not be guessed.
- `unreadable`: trustworthy content is insufficient for a reviewable draft.
- `failure`: an operational/provider/internal failure prevented completion.

The deterministic parser does not call a remote LLM or Gateway, depend on Apple types, persist data, write
provenance, or bypass confirmation. Existing aggregate draft confidence and field-level unknowns remain advisory;
the existing Recognition Quality harness continues to measure critical fields independently, including amount,
direction, date, merchant, and category. Overall recognition success never implies field correctness.

Provider identity, engine version, and whether the recognizer genuinely inspects pixels are exposed through
`TransactionRecognizerMetadata`. `baselineEligible` requires real pixel inspection, a non-mock provider identity,
and reproducible non-empty engine metadata. Merely conforming to `TransactionExtracting` is insufficient;
`MockAIProvider` remains ineligible. Establishing a baseline is distinct from production eligibility and production
readiness, and a real baseline may fail later eligibility thresholds.

### Scope and privacy

v1 covers Transaction screenshots only. Existing screenshot-recognition consent remains the eligibility gate.
Local recognition requires no remote image transmission. Original-image retention remains independently governed
by `retainOriginalImages`. No OCR text, screenshots, bounding boxes, merchant text, or image bytes are added to
observability, AI financial-context DTOs, Backup v1, or persisted financial facts.

### Evaluation

Reuse the existing Recognition Quality corpus, harness, per-field evaluators, and report. Do not create a second
benchmark framework. Step 2 synthetic/development fixtures make the recognizer baseline-capable but do not establish
a real accuracy baseline.

### Step 2 implementation

- `AppleVisionTextRecognizer` uses on-device Vision accurate text recognition for `zh-Hans` and `en-US`, returning
  transient platform-neutral `RecognizedTextSpan` values.
- `DeterministicTransactionReceiptParser` conservatively supports representative WeChat Pay and Alipay Transaction
  detail semantics; amount and direction remain required, while date/merchant/account/category may remain unknown.
- `AppleVisionTransactionRecognizer` composes OCR + parser and truthfully reports pixel inspection, provider identity,
  and engine version. It is baseline-capable but is not wired into production.
- OCR text is not persisted, logged, backed up, or sent remotely. Schema v5, Backup v1, Consent, ADR-036 currentness,
  metadata ordering, confirmation, and provenance remain unchanged.

### Step 3 production integration

- Production screenshot bookkeeping now injects `AppleVisionTransactionRecognizer` only for `TransactionExtracting`.
- `DebtScanning` remains `MockAIProvider`; `FinancialAssisting` retains its existing Mock/remote routing.
- Canonical `AIDataConsentService`, exact-source lookup, Application generation/currentness acceptance, editable
  review, confirmation, Transaction-first provenance ordering, and media-retention policy remain unchanged.
- The production-composed Apple test proves image pixels reach Vision and a deterministic review draft is produced
  without auto-confirming a Transaction. No screenshot or OCR text is sent remotely or persisted as metadata.
- This production switch does not establish an accuracy baseline or pass an accuracy/release gate.

### Step 4A measurement infrastructure

- Reused the existing Recognition Quality contract, comparisons, adapters, and report conventions; no second
  benchmark framework was introduced.
- Added an opt-in private local Transaction corpus manifest with opaque IDs, explicit outcome/coverage labels,
  deterministic canonical-manifest plus ordered-image SHA-256 digest, production recognizer execution, latency,
  outcome distribution, field-level end-to-end and recognized-only denominators, readable-negative false-positive
  rate, aggregate diagnostic categories, and the frozen v1 threshold gate.
- Amount comparison remains exact `Decimal` equality. Date labels explicitly select day or minute precision in the
  corpus timezone. Merchant normalization is limited to whitespace, Unicode width, and Latin case normalization.
- The aggregate report schema contains no per-sample collection, sample ID, asset path, OCR text, image bytes,
  ground-truth values, recognized amount, or merchant value. Private input and optional report output remain local.
- Missing `REAL_RECOGNITION_CORPUS` prints `REAL BASELINE CORPUS NOT AVAILABLE`; normal CI does not substitute Mock or
  synthetic fixtures. No private corpus was available for this verification, so no real metrics or gate result exist.
- No Vision configuration, parser rule, confidence threshold, production outcome, persistence, Backup, Consent,
  production Provider composition, or remote-image boundary changed. Parser/OCR tuning remains Step 4B-only.

### Deferred

- additional unsupported WeChat / Alipay historical layouts beyond conservative v1 rules
- real accuracy run and threshold decision
- remote Qwen/VL recognizer or Gateway image endpoint
- Debt recognition, Debt per-image outcomes, and Debt reconciliation
- semantic Transaction duplicate detection

### Relationship

Relates to, and does not supersede, ADR-003, ADR-015, ADR-016, ADR-029, ADR-035, and ADR-036. ADR-036 exact-source
warn-and-allow behavior, Application currentness acceptance, recognition-metadata ordering, confirmation ordering,
post-Transaction provenance write, delete/wipe lifecycle, and Backup v1 provenance exclusion remain unchanged.

This Step 1 introduces no Apple OCR implementation, production Provider switch, remote image transmission, Consent
field, Backup v1 change, or JSON Store schema change.

Step 2 adds the non-production local Apple OCR/parser composition only. It introduces no production Provider switch,
remote image transmission, Consent field, Backup v1 change, or JSON Store schema change.

Step 3 switches only production `TransactionExtracting` to the local Apple recognizer. It introduces no Debt or
Financial Assistant provider switch, remote image transmission, Consent field, Backup v1 change, or JSON Store
schema change.

### Verification

```text
Windows/shared targeted Transaction Recognition contract: 4 PASS; Failed 0
Windows/shared targeted Recognition / ADR-036 regression: 70 PASS; Failed 0
Windows/shared full gate: 750 PASS (107 suites); Failed 0
swift build -c release: PASS
Apple: ios-apple-gate.yml run 32707622669
       verified candidate bf75520bf7f71affcd73a04add48523a849510bf
       Xcode 16.4 (16F6), macos-15-arm64 / macOS 15.7.7
       YoushuUITests 58 PASS / YoushuDataTests 114 PASS / YoushuDomainTests 493 PASS
       Total 665 PASS; Failed 0

Step 2 Windows/shared deterministic parser: 20 PASS; Failed 0
Step 2 Windows/shared Transaction Recognition contract: 5 PASS; Failed 0
Step 2 Windows/shared Recognition Quality: 26 PASS; Failed 0
Step 2 Windows/shared ADR-036 targeted regression: 44 PASS; Failed 0
Step 2 Windows/shared full gate: 771 PASS (108 suites); Failed 0
Step 2 swift build -c release: PASS
Step 2 Apple: ios-apple-gate.yml run 32710172471
       verified candidate 9fc6bfad6e84c137638b5a458889489ea4851c8b
       Xcode 16.4 (16F6)
       YoushuUITests 61 PASS / YoushuDataTests 114 PASS / YoushuDomainTests 493 PASS
       Total 668 PASS; Failed 0
       Apple Vision focused tests 3 PASS (including synthetic pixel OCR)

Step 3 Windows/shared full gate: 771 PASS (108 suites); Failed 0
Step 3 swift build -c release: PASS
Step 3 Apple: ios-apple-gate.yml run 32716260090
       verified candidate 67de996dc817ba9114479f613f0c83292f1e8240
       Xcode 16.4 (16F6)
       YoushuUITests 70 PASS / YoushuDataTests 114 PASS / YoushuDomainTests 493 PASS
       Total 677 PASS; Failed 0
       Production composition 3 PASS, including production-composed synthetic pixel OCR to editable review

Step 4A private-corpus infrastructure: 16 PASS (3 suites); Failed 0
Step 4A existing Recognition regression: 51 PASS (6 suites); Failed 0
Step 4A ADR-036 / screenshot lifecycle regression: 71 PASS (10 suites); Failed 0
Step 4A Windows/shared full gate: 787 PASS (111 suites); Failed 0
Step 4A swift build -c release: PASS
Step 4A real-corpus run: NOT RUN — REAL BASELINE CORPUS NOT AVAILABLE
Step 4A Apple: ios-apple-gate.yml run 32799176406
       verified candidate 0a039e98efff5562e9bbd518ae2e1ee0cd35ad9d
       Xcode 16.4 (16F6), macos-15-arm64 / macOS 15.7.7
       private-corpus infrastructure 16 PASS; corpus unavailable (no fallback)
       YoushuUITests 70 PASS / YoushuDataTests 114 PASS / YoushuDomainTests 493 PASS
       iOS integration total 677 PASS; Failed 0
       Do not add shared, package-infrastructure, and iOS totals as unique tests.
```

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
