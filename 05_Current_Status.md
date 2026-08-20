# 知数 · FinSight — Current Status

> 文档角色：项目当前存档点 / 新 Chat 恢复入口  
> 版本：v1.0  
> **Last Updated：2026-08-20（ADR-032 Stored Insight Freshness / Lifecycle Closure）**  
> 本文件应频繁更新；旧状态不应无限累积，重大历史移入 Decision Log。

---

## 1. 当前阶段摘要

FinSight 已经从“PRD / 纯 Mock MVP”进入：

**核心 Domain 闭环基本建立 → AI Context / Provider / Validator 重构完成较多 → Bailian Structured Output 稳定化 → Gateway 已部署到 ECS 内部环境 → 等待 ICP 备案后再继续公网生产链路。**

当前不是：

- 对外正式发布版本
- TestFlight 公共内测就绪版本
- 已完成真实 Bailian production smoke 的版本

当前更接近：

**可持续开发的内部 MVP / Pre-Production Engineering 阶段。**

---

## 2. 产品命名

### 正式

```text
中文：知数
英文：FinSight
```

### Legacy

```text
有数
Youshu
youshu
```

**FinSight 品牌 / runtime identity 已部分迁移**（例如 App display name、`FinSightApp`、Gateway 部署名 `finsight-ai-gateway`）。

**Legacy technical identifiers 仍大量存在**（2026-08-19 Baseline Audit 已验证）：

- `YoushuDomain` / `YoushuData` / `YoushuAI` / `YoushuUI` / `YoushuDesignSystem`
- Root SPM package name `Youshu`
- XcodeGen target / scheme `Youshu`
- Bundle ID `app.youshu.Youshu`
- Go module path `github.com/youshu/youshu-ai-gateway`
- JSON store path `Application Support/Youshu/youshu-store.json`
- Gateway / config keys：`YOUSHU_*`、`X-Youshu-Request-Id` 等

Technical rename 仍是 **migration-sensitive** 工作，不能仅因品牌改名假设代码已 100% 迁移。

---

## 3. 当前客户端技术基础

已知基础：

```text
iOS 17+
XcodeGen
Swift / SwiftUI
Domain / Data / AI / UI 分层
Local JSON Store
```

历史代码模块：

```text
YoushuUI
YoushuDomain
YoushuData
YoushuAI
```

应视为 legacy technical identifiers，等待仓库级 rename audit。

---

## 4. 当前导航

五 Tab 已建立：

```text
首页
账单
债务
账户
AI
```

---

## 5. 核心财务 Domain

### 已建立 / 可测试的核心对象

- Account
- Transaction
- Debt
- RepaymentPlan
- Debt-related facts
- FinancialContext

**未实现（产品 / Domain 目标，非当前 persisted entity）：**

- `Bill` — 当前仅有 `BillDocument`（扫描 / import 输入 VO），不等同于 persisted Bill

### 确定性 Engine

已知包括：

- FinancialSummaryEngine
- CashFlowEngine
- DebtCenterCalculator
- PurchaseScenarioEngine
- HomeOverview aggregation
- **FinancialRiskPolicyEngine**（`IMPLEMENTED`，regression-covered）
- **FinancialRiskAssessmentService**（`IMPLEMENTED`，组装 assessment 并接入 monthly summary / Gateway envelope）

**Risk Policy regression（仓库实测名称）：**

- `FinancialRiskEvaluationGoldenParityTests` — 29-case golden parity
- `FinancialRiskPolicyEngineTests` / `FinancialRiskProductionWiringTests` 等

描述为 **IMPLEMENTED / regression-covered**；**不要**写 production-grade 或 production-ready（本轮无额外生产证据）。

核心原则已经建立：

**金额不交给 LLM 计算。**

---

## 6. Cash Flow

已实现预测 horizon：

```text
7
30
60
90 days
```

HomeOverview 链路已整合多 horizon。

已建立：

```text
CashFlowPresentation
CashFlowSectionView
CashFlowDetailView
```

Presentation 不负责计算。

---

## 7. Home

核心链路：

```text
HomeOverviewService.loadOverview
        ↓
FinancialContextBuilder / repositories
        ↓
FinancialSummaryEngine
        ↓
CashFlowEngine
        ↓
HomeOverview
        ↓
UI
```

### ADR-020 Home AI failure isolation：`FIXED — 2026-08-19`

### ADR-032 Home AI summary eligibility：`IMPLEMENTED — 2026-08-20`

Home current AI summary 使用 **两个独立 gate**：

```text
Gate A — Consent（allowFinancialContextToAI）
Gate B — Freshness（deterministic metadata match）
```

当前真实行为：

```text
Deterministic Home（repositories → engines → HomeOverview metrics）
        ↓
Consent Gate
├─ denied → deterministic summary（不展示 stored AI summary；无 Provider 调用）
└─ allowed
        ↓
Freshness Gate
├─ fresh stored .summary → trusted persisted summary reuse
└─ stale / legacy nil / unsupported schema → cache miss
        ↓
Optional AI monthly-summary enrichment
        ├─ AI success → validated AI summary（modelName = provider）
        └─ AI failure → local deterministic summary（modelName = "deterministic"）
        ↓
Home remains available（metrics + cash flow 正常展示）
```

Consent revoke **不删除** historical persisted insights；仅阻止当前 Home 展示与新的 financial-context transmission。

Consent re-enable 后：仍 fresh 的 stored summary 可复用；stale summary 走正常 regenerate 路径。

Freshness metadata **不包含** Consent 状态。

**Home availability policy 归属 `HomeOverviewService`**，不再由 Provider 决定。  
`FinancialAssisting` contract **已移除** `allowsDeterministicFallbackOnAIFailure`；Provider 只报告 AI 成功/失败。

**仍会导致 Home load failure 的情况（未吞错）：**

- Repository 读取失败
- 必需的 deterministic 财务计算失败
- 其他 core Home pipeline 错误

**不要**写成“Home 永远不会失败”。

Regression：

- `HomeOverviewAIFailureIsolationTests`（5 cases）
- `HomeOverviewFreshnessTests`
- `HomeOverviewConsentLifecycleTests`
- `FinancialRiskConsentClosureTests`

---

## 8. 债务中心

已建立的能力方向包括：

- 债务列表
- 债务详情
- 手动录入
- 还款
- 批量截图债务扫描流程
- RepaymentPlan
- 债务数据完整性
- DebtCenterCalculator

债务扫描当前产品方向：

```text
多截图
→ AI detection
→ Draft
→ Confirm
→ Debt
```

目标继续加强：

- 自动发现
- partial debt inventory
- 后续账单更新
- transaction repayment matching
- 风险 / 现金流联动

---

## 9. Consent / Privacy

核心 `AIDataConsent` 已建立，包含：

```text
allowScreenshotImageToAI
allowDebtScanImageToAI
allowFinancialContextToAI
retainOriginalImages
```

已完成的重要架构动作：

- Assistant Financial Context 有统一 consent 门禁。
- 支持撤销授权。
- AI payload 与 Domain Context 分离。
- 原图保留可配置，产品原则为最小化。

历史遗留 / 应复核：

- 全局“隐私与 AI”设置 UI 是否已覆盖全部字段。
- `retainOriginalImages` UI 是否最终完成。
- 全量数据删除入口是否已经暴露。
- 截图、债务扫描、Assistant 三条 consent 文案是否与真实 payload 完全一致。

---

## 10. AI Assistant Context

已形成目标链路：

```text
Domain Data
      ↓
FinancialContextBuilder
      ↓
FinancialContext
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
```

关键约束：

- 不直接传 FinancialContext。
- 不发送 UUID。
- 不发送无必要 merchant / note。
- Provider 只看到 transport DTO。
- Context 只包含完成任务所需的聚合数据。

---

## 11. AI Answer

已形成双层：

```text
Provider
→ AssistantAnswerDraft
→ AssistantAnswerValidator
→ AssistantAnswer
→ UI
```

Validator 负责：

- title / body
- citedFactKeys
- allowed amount
- disclaimer
- unknowns
- confidence
- fact safety

重要经验：

`safeBalance` 等确定性金额如果进入 AI body，也必须进入对应 FactPack，否则 Validator 正确拒绝。

---

## 12. Bailian Structured Output & C2B KeyFact Ownership

### 历史问题

早期 `keyFactValue` 使用 `allOf + if / then` 做 polymorphic conditional schema，Provider 生成阶段出现 shape drift / `typeMismatch`。

### 当前架构（2026-08-19 Baseline Audit 已验证）

真实链路已演进为 **C2B source-only ownership**（见 ADR-031）：

```text
Deterministic FactPack / MonthlySummaryFacts
        ↓
AI-safe request (+ financialRiskAssessment)
        ↓
Bailian model output（source-only keyFact references）
        ↓
Gateway canonical fact materializer
        ↓
iOS-facing AssistantAnswerDraft（含 materialized keyFact values）
        ↓
AssistantAnswerValidator
        ↓
AssistantAnswer
```

**重点：**

- Provider / LLM **不拥有** canonical financial values。
- LLM 选择 / 引用 **authorized fact source**（label / kind / source）。
- Gateway 从 deterministic / authorized facts **materialize** canonical value（money / text / percent / date）。
- Bailian **model-generation schema** 不再要求 LLM 输出 embedded KeyFact value DTO。

### 三层 schema（不要混为一谈）

| 层 | 作用 | 备注 |
|----|------|------|
| **A. Bailian model-generation** | LLM structured output | source-only keyFacts；**不得**依赖 conditional polymorphic generated value（ADR-017） |
| **B. Gateway materialization** | canonical value 组装 | `ModelKeyFactValueDTO` 等用于 materialization / trust boundary，非 LLM 生成 |
| **C. Gateway → iOS response** | `AssistantAnswerDraft` transport | 可有独立 deterministic schema；不自动构成 ADR-017 conflict |

### 原则

不因为 Provider / transport schema 限制去污染 Domain Model。

---

## 13. Gateway

### 服务

```text
finsight-ai-gateway
```

### 技术

```text
Go
```

### API

已知核心路径：

```text
POST /v1/ai/financial-assistant
GET /health
GET /ready
```

### ECS 内部部署 — Latest documented runtime snapshot

**Latest documented runtime snapshot: 2026-08-18**

（以下为 **2026-08-18 当时验收记录**，非实时状态。）

**2026-08-19 Repository Baseline Audit did NOT revalidate live ECS runtime.**

截至 2026-08-18 的最新验收记录：

```text
systemd: active
bind: 127.0.0.1:8080
/health: 200
/ready: 200
service: finsight-ai-gateway
version: uncommitted
provider: bailian
```

运行权限已按内部部署方式收紧：

```text
runtime user: finsight
binary: root:root 0755
production.env: root:root 0600
systemd: enabled
```

### 注意

在部署过程中曾出现：

```text
production requires GATEWAY_CLIENT_TOKEN
```

导致 restart loop。

后续配置已修正并最终通过 health / ready 验收。

该历史故障应保留在运维知识中，但不代表当前服务仍失败。

---

## 14. ICP 备案当前硬约束

**ICP备案仍 pending。**

当前只允许：

```text
ECS 内部部署
localhost-only bind
内部健康检查
配置 / 权限 / systemd 验收
```

当前禁止：

```text
公网 DNS
公网 80
公网 443
公网 8080
任何绕过备案的公开访问
iOS production Gateway wiring
真实 Bailian production smoke
```

这不是技术 blocker 的规避建议，而是当前阶段明确的合规边界。

---

## 15. iOS Remote AI 状态

历史 MVP 默认：

```text
MockAIProvider
```

Remote path 已有架构：

```text
RemoteFinancialAIProvider
→ Gateway
→ Bailian
```

但截至本存档点：

**不能把“Gateway 在 ECS 内部 active”理解为“iOS 真实 AI production path 已上线”。**

由于 ICP 约束，目前不要进行：

- 公网 HTTPS 接入
- iPhone production remote wiring
- production live smoke

---

## 16. 测试状态

### 2026-08-20 ADR-032 Step 5A — 当前实测基线

以下数字来自 **2026-08-20 ADR-032 Step 5A full regression**（Step 5B docs-only 同步轮次未重跑）。
以后仍必须以 **每轮真实测试** 为准，不能把本文当作永久 CI 状态。

```text
Swift (scripts/test-windows.bat):

Foundation:   2 passed
Domain:     358 passed
Data:         6 passed
AI:          61 passed
Total:      427 passed
Failed:       0
Skipped:      0

iOS Build:
  NOT RUN — Windows environment limitation
```

Gateway tests：

```text
NOT rerun for ADR-032 because Gateway code/contracts were unchanged.
```

关键回归包括：

- `StoredInsightTrustBoundaryTests`（validate-on-write / trusted-read / fallback non-persist）
- `StoredInsightFreshnessTests` / `StoredInsightFreshnessPersistenceTests`
- `HomeOverviewFreshnessTests` / `HomeOverviewConsentLifecycleTests`
- `HomeOverviewAIFailureIsolationTests`（remote success / remote failure + consent / consent denied / core failure / mock）
- `DeterministicSHA256Tests`（empty / "abc" known vectors）
- `CashFlowEngineTests` / `HomeOverviewServiceTests`
- `CashFlowPresentationTests` / `MVPFinancialConsistencyTests`
- `FinancialRiskEvaluationGoldenParityTests`（29-case golden parity）
- `FinancialRiskConsentClosureTests`

### 历史阶段记录（归档，非当前基线）

2026-08-20 Stored Insight trust boundary closure 曾记录：

```text
Domain: 318 passed
Data:     6 passed
AI:      61 passed
Total:  385 passed
```

2026-08-12 MVP 验收曾达到：

```text
Domain 86 / Data 6 / AI 35 / Total 127
```

P0-1 改造后曾记录：

```text
Domain 97 / Data 6 / AI 35 / Total 138
```

2026-08-19 Baseline Audit（ADR-020 修复前）曾记录：

```text
Domain 309 / Data 6 / AI 61 / Total 376
```

2026-08-19 ADR-020 fix 曾记录：

```text
Domain 314 / Data 6 / AI 61 / Total 381
```

上述 **138 / 376 / 381 / 385** 等旧数字 **不再是当前基线**（当前为 **427**）。

典型一致性：

```text
10000
- 支出 2000
- 还款现金流 1000
----------------
可用资金 7000

债务：
5000 - 1000 = 4000
```

用于防止 Debt / Transaction / Cash Flow 双计或漏计。

### 当前需要坚持

每次架构重构后重新跑“当前仓库全量测试”，不能把历史数字当作永久最新 CI 状态。

---

## 17. 数据持久化

当前：

```text
JSON Store schema v4
```

支持 v1 → v4 migration。

Legacy path：

```text
Application Support/Youshu/youshu-store.json
```

当前已知重大缺口：

- iCloud：未建立
- Export：未建立
- Backup：未建立
- 卸载：存在数据丢失风险
- 换机：缺少数据恢复链路

进入真实长期自用前，这一项应提升优先级。

---

## 18. 目前最重要的风险 / 技术债

### 18.1 Stored Insight Trust Boundary（已关闭验证）

**Stored Insight Trust Boundary：`VERIFIED SAFE — 2026-08-20`**

Step 5 lifecycle audit + Step 6 `StoredInsightTrustBoundaryTests` 已确认：

- monthly summary persistence 经 `AssistantAnswerValidator`
- proactive insight persistence 经 `AssistantAnswerValidator`
- invalid monthly summary **cannot** persist
- persisted validated summary may be **trusted on read**（validate-on-write → trusted persisted snapshot）
- ADR-020 deterministic fallback is **ephemeral / not persisted**

**不存在** production-reachable：

```text
Provider raw → persistence
AssistantAnswerDraft → persistence without Validator
```

Home read persisted summary 时不重复 Validator — 在当前 trust model 下 **合理**，**不是**已知 ADR-012 conflict。

Trust 与 Freshness / Consent 是 **三个独立维度**（见 §18.2）。

### 18.2 Stored Insight Freshness / Lifecycle（已关闭实现）

**Stored Insight Freshness / Lifecycle：`RESOLVED / IMPLEMENTED — 2026-08-20`（ADR-032）**

已验证实现：

- monthly summary 可选择性持久化 `FinancialInsightFreshnessMetadata`（schema version / policy version / opaque SHA-256 digest）
- raw canonical financial-fact token **仅运行时存在，不持久化**
- freshness 基于 deterministic `MonthlySummaryFacts` + `FinancialRiskAssessment` + `policyVersion`
- stale / legacy nil metadata / unsupported freshness schema → Home **cache miss**（read 时不删除 stale record）
- Consent denied → 不展示 current stored AI summary；不发送新的 financial-context Provider 请求
- Consent re-enable → 仍 fresh 的 stored summary 可复用；stale 走正常 regenerate
- Consent **不进入** freshness metadata / fingerprint
- proactive historical insights 不要求 monthly-summary freshness metadata；revoke 不删除 proactive historical insights
- ADR-020 deterministic fallback 仍 **non-persisted**
- JSON Store 保持 **schema v4**；`freshnessMetadata` optional；**无需 migration**
- Step 5A 已验证 production consent wiring 安全（`FinSightApp → AppDependencies → AIDataConsentService → HomeOverviewService`）

### P0 / Release Gate 级

1. **ICP备案未完成**
   - 阻止公网 Gateway / iOS production AI wiring。

2. **真实 AI production chain 尚未完成合规验收**
   - 内部 Gateway ready ≠ iPhone live ready。

3. **品牌技术迁移未完成**
   - `Youshu*` legacy identifiers 仍大量存在（见 §2 inventory）。

### P1 级

4. **Backup / Export / device migration 缺失**
5. **Production observability 不完整**
6. **Token / cost telemetry 尚未完全接 production**
7. **隐私设置 UI 覆盖度需重新核验**（含 `retainOriginalImages`）
8. **真实图片识别准确率缺少稳定 baseline**
9. **大数据量 JSON Store 性能未压测**

### 代码质量

历史审计关注：

- DebtScannerSheet 偏大
- DebtViewModel 偏大
- 双 Package / 项目结构维护成本
- NoOp / mock path 的生产替换
- UI / snapshot / performance tests 不完整

这些不是当前产品方向阻断项，但需要逐步偿还。

---

## 19. 下一阶段建议顺序

### Stage A — ICP pending 期间

只做不违反公网约束的工作：

1. 整理项目 Context / ADR。
2. 清理 legacy naming，但只做安全、可测试的部分。
3. 完成本地 / Gateway unit tests。
4. 强化 Provider schema tests。
5. 完成 error taxonomy。
6. 完成 observability 设计与本地验证。
7. 修复 remote-AI-to-Home 的耦合架构。
8. 建立 Backup / Export 方案。
9. 补 Consent / Privacy UI。
10. 真机仅验证不依赖公网 AI 的本地能力（若环境条件允许）。

### Stage B — ICP 完成后

再进入：

```text
domain / DNS
→ HTTPS
→ Gateway public production config
→ auth
→ real Bailian smoke
→ iOS RemoteFinancialAIProvider wiring
→ end-to-end iPhone test
→ TestFlight readiness
```

每一步单独验收，不一次性“大开关”。

---

## 20. 新 Chat 启动时建议读取顺序

如果以后新开 Chat 做 FinSight：

```text
1. 05_Current_Status.md
2. 04_Decision_Log.md
3. 与任务有关的：
   - 02_Architecture.md
   - 03_Data_Model.md
   - 01_Product.md
4. Git / Cursor 最新 diff 与 tests
```

如果文档与代码冲突：

```text
运行代码 / 测试
> 最新 Current Status / ADR
> Architecture / Data Model
> Product
> 历史聊天
```

---

## 21. 下一次更新本文件的触发条件

出现以下任一情况就更新：

- ICP 状态变化
- Gateway 开放 HTTPS
- iOS 切换 Remote Provider
- Bailian real smoke 完成
- TestFlight 构建成功
- 数据存储迁移
- Backup / Export 完成
- 模块 rename
- 大 milestone 完成
- 全量测试数字发生显著变化
- 新的 P0 blocker
- 风险 Policy Engine 实现状态显著变化（非“planned-only”）

---

## 22. 当前一句话存档

**截至 2026-08-20，FinSight 的核心财务 Domain、现金流（7/30/60/90）、多债务、Consent、AI Context、Answer Validator、Stored Insight trust boundary（VERIFIED SAFE）、ADR-032 Stored Insight freshness/lifecycle（RESOLVED）、FinancialRiskPolicyEngine（regression-covered）、C2B KeyFact / Gateway materialization 与 ADR-020 Home AI failure isolation（FIXED）已建立到较成熟的内部 MVP 阶段；Swift 当前基线 **427 tests PASS**（iOS build NOT RUN）；Gateway ECS 运行态仅保留 2026-08-18 documented snapshot；Gateway tests NOT rerun for ADR-032；ICP 备案 pending，公网 HTTPS、iOS production wiring 与真实 Bailian production smoke 仍明确禁止。**
