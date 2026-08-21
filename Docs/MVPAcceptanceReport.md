# 《知数（FinSight）》MVP 最终验收报告

**日期**：2026-08-12  
**范围**：既有功能闭环验收（未启动 P1 新功能开发）  
**自动化测试**：Domain **86** / Data **6** / AI **35**，全部通过  
**黄金账本一致性**：`MVPFinancialConsistencyTests`（10000 − 支出2000 − 债务5000 − 还款1000 → 可用资金 **7000**，债务余额 **4000**）

---

## 1. MVP 完成度

| 维度 | 完成度 | 说明 |
|------|--------|------|
| Domain / 财务引擎 | **高 (~90%)** | Account / Transaction / Debt / DebtEvent / CashFlow / Home Summary 可测且一致 |
| 核心记账 + 债务 UI | **中高 (~75%)** | 五 Tab 可用：首页 / 账单 / 债务 / 账户 / AI |
| AI 能力（产品级） | **中 (~50%)** | 流程完整，但为 **MockAI**；助手授权 UI 缺口 |
| 首次体验 / 设置 | **低 (~20%)** | 无 onboarding、无专用收入设置、无隐私设置页 |
| 发布就绪 | **低 (~25%)** | 有 XcodeGen + 模拟器脚本；无签名 / TestFlight / 真机流水线 |

**综合判定：内部可演示的功能 MVP ≈ 65–70%；不达对外 TestFlight 内测标准。**

---

## 2. P0 功能完成情况

### 核心用户旅程

| 步骤 | 状态 | 证据 |
|------|------|------|
| 下载/启动 | Partial | `FinSightApp` → bootstrap；本地 JSON；无商店分发 |
| 基础设置 | Missing | 无 Settings / Onboarding |
| 设置收入 | Partial | 可手动记收入；无工资/固定收入引导 |
| 创建账户 | Done | 账户 Tab；启动可自动建「现金」「银行卡」 |
| 上传交易截图 → AI 识别 → 确认 | Done* | Sheet 闭环；*AI=Mock |
| 债务中心 | Done | 列表 / 详情 / 手动录入 / 还款 |
| 批量账单 → AI 发现 → 确认债务 | Done* | 多图扫描；*AI=Mock |
| 生成财务全景 | Partial | Domain 生成；首页展示部分指标 |
| 查看首页 | Done | 可用资金、本月收支/还款、健康度、AI 摘要 |
| 查看现金流预测 | Missing(UI) | `cashFlowProjections` 已算，首页未展示 7/30/60/90 |
| 获得 AI 财务洞察 | Partial | AI Tab 存在；助手 consent UI 缺失，易失败 |

### P0 清单结论

| P0 项 | 状态 |
|-------|------|
| 手动记账（收/支/转） | Done |
| 账户与余额派生 | Done |
| 截图记账确认入库 | Done（Mock AI） |
| 债务中心 + 扫描确认 | Done（Mock AI） |
| 首页财务摘要 | Done |
| 现金流预测可见 | **缺口** |
| 真实 AI Provider | **缺口** |
| 首次引导 / 收入设置 / 隐私中心 | **缺口** |
| 待确认债务关联 UI | **缺口**（Domain 有，UI 无） |
| TestFlight 打包 | **缺口** |

---

## 3. Bug 列表

| ID | 严重度 | 描述 |
|----|--------|------|
| B1 | **P0** | AI 助手 Tab 未采集 `acceptAssistantPrivacy`，App 接线 consent 后提问可被拒 |
| B2 | **P0** | 现金流预测仅 Domain 有数据，首页无 7/30/60/90 与风险展示 |
| B3 | **P1** | 还款自动匹配 / PendingDebtLink / SuspectedDebt 无用户确认 UI |
| B4 | **P1** | `DebtService.recordRepayment` 写死分类 `"生活"`，语义不当 |
| B5 | **P1** | 无 onboarding；首次进入缺少「设置收入」路径 |
| B6 | **P2** | `AssetView` 孤儿，未挂 Tab |
| B7 | **P2** | README 仍写 Phase 0，与现状不符 |
| B8 | **P2** | 生产 Token 仍为 `InMemorySecureTokenStore`（非 Keychain） |

未发现：UI 层 `try!` / `as!` / `fatalError`；业务强制 unwrap 面干净。

---

## 4. 技术债务

1. **AI 全程 Mock**：`AppDependencies` 默认 `MockAIProvider`，无生产 LLM 适配层开关。  
2. **双 Package 结构**（历史审计项）：根 SPM（Domain/Data/AI）与 UI package 分离。**当前 canonical topology（2026-08-21）：** `Package.swift` + `Modules/Package.swift`（Xcode 经 `project.yml`）；legacy `AppPackages/YoushuUIPackages` 已移除。
3. **JSON Document Store**：可支撑 MVP；大数据量列表/查询无索引策略。  
4. **DebtScannerSheet ~400 行**：接近巨型 View，可拆步骤子视图。  
5. **DebtViewModel ~328 行**：偏大，列表/表单/还款可拆。  
6. **NoOpDebtMatchAssistant**：关联链路未真正 AI 辅助。  
7. **隐私服务有、设置页无**：wipe / consent / 识别记录删除缺入口。  
8. **无 UI / 快照 / 性能测试**：验收指标无法量化。

---

## 5. 性能问题

| 项 | 现状 |
|----|------|
| 首页启动速度 | 无基准；逻辑为一次 overview 聚合，数据量小时应可接受 |
| 图片加载 / 缓存 | 默认 **不落盘**（最小化）；大图仅内存，批量扫描时需注意峰值 |
| AI 请求 | Mock 瞬时；真实网络延迟/超时未在 UI 做专项优化测量 |
| 数据库查询 | 全量 JSON 读写；大量交易时列表滚动可能卡顿（未压测） |
| 大量交易列表 | 有分组，无分页 / 虚拟化验证 |

**结论**：无性能回归数据；当前不能宣称满足「首次记账耗时 / 首页加载时间」SLO。

---

## 6. 安全问题

详见 [`Docs/SecurityCheckReport.md`](SecurityCheckReport.md)。摘要：

| 项 | 状态 |
|----|------|
| 日志脱敏 | Done（`LogRedactor`） |
| AI 授权门禁 | Domain Done；助手 UI Partial |
| 原图最小化 | Done |
| 用户删除能力 | Domain Done；设置 UI Partial |
| Keychain | **未接生产实现** |
| 真实 API Key | 未写入代码（合规） |

残留风险：助手 consent 缺口导致错误体验；内存 Token；无隐私中心。

---

## 7. 建议修复优先级（仅 P0 闭环，不进入 P1 产品功能）

| 优先级 | 项 | 目的 |
|--------|----|------|
| **P0-1** | 首页展示 `cashFlowProjections` + 风险摘要 | 闭合「查看现金流预测」 |
| **P0-2** | AI Tab 增加助手隐私授权 | 闭合「AI 洞察」可用路径 |
| **P0-3** | 最小 onboarding：欢迎 → 设收入/账户提示 | 闭合启动旅程 |
| **P0-4** | 接入可切换的真实 AI Provider（或明确内测仍用 Mock 的范围） | 指标可测 |
| **P0-5** | Xcode 签名 + TestFlight 导出脚本 | 内测分发 |
| **P0-6** | 隐私与数据设置页（wipe / 删除识别记录） | 安全验收闭环 |
| **P1**（暂缓） | 待确认债务关联 UI、预算/目标、真实 Keychain | 非本轮 |

---

## 8. 重点指标评估

| 指标 | 自动化证据 | 产品结论 |
|------|------------|----------|
| 首次记账耗时 | 无 | **不可验收** |
| AI 识别成功率 / 准确性 | Mock 行为测试 | **不可对外宣称** |
| 债务扫描完成率 / 确认率 | 流程测试有，无漏斗率 | **不可对外宣称** |
| 还款交易匹配率 | Matcher/Linking 单测 | 行为正确，**无现场率** |
| 首页加载时间 | 无 | **不可验收** |
| 现金流计算正确性 | 引擎 + 黄金账本测试 | **通过（引擎层）** |
| AI 回答正确性 | 事实校验 + 拒编造 | **Mock 下通过** |

---

## 9. 财务一致性与边界

### 黄金场景（已建测试）

```
期初 10000 → 支出 2000 → 债务 5000 → 还款 1000
→ Account 余额 / 可用资金 = 7000
→ Debt 余额 = 4000（含 DebtEvent.created + repayment）
→ Home.monthlyLivingExpense = 2000
→ Home.monthlyDebtRepayment = 1000
→ CashFlow projections 四档存在且与 Summary 对齐
```

### 边界覆盖（自动化）

| 边界 | 覆盖 |
|------|------|
| 删除交易 / 债务 | 有 |
| AI / 网络失败 | 截图与债务扫描有 |
| 多债务 / 多账户 / 信用卡 | 有 |
| 部分还款 / 结清 / 超额还款 | 有 |
| 重复账单页聚合 | 有 |
| 0 / 负现金余额专项 | **弱** |
| 重复交易防重 | **弱** |
| 大额交易 | Partial |

---

## 10. 代码质量抽查

| 检查项 | 结论 |
|--------|------|
| 重复代码 | 中等；表单/Sheet 模式相似但可接受 |
| 巨型 View | `DebtScannerSheet` 偏大 |
| 巨型 ViewModel | `DebtViewModel` 偏大 |
| 业务进 UI | 总体经 Service；金额不在 View 硬算 |
| AI SDK 与业务耦合 | 端口隔离良好；App DI 绑死 Mock |
| 财务计算进 AI | 禁止路径有校验测试 |
| 未处理错误 | ViewModel 多有映射；助手 consent 体验差 |
| 强制 unwrap | UI 未见 |
| 不合理 singleton | 未见业务 singleton |
| 无意义抽象 | 整体克制；`NoOp*` 为占位 |

---

## 11. 当前是否达到 TestFlight 内测标准？

### **否。**

阻断项：

1. 无签名 / 导出 / TestFlight 流水线  
2. 核心 AI 仍为 Mock，内测用户无法验证真实识别  
3. 旅程缺口：现金流 UI、助手授权、基础设置/收入引导  
4. 无性能与真实识别准确率基线  

### 达到「团队内部 Demo / 模拟器验收」标准？

### **是（有条件）。**

条件：明确告知「AI 为 Mock、现金流预测 UI 未露出、助手需补授权」。Domain 财务一致性与单测门禁可用于回归。

---

## 附录：本轮验收动作

- 只做验收与最小测试补强，**未开发 P1 功能**  
- 新增：`Modules/YoushuDomain/Tests/YoushuDomainTests/MVPFinancialConsistencyTests.swift`  
- 全量测试：`scripts/test-windows.bat` → **127** 项通过（86+6+35）
