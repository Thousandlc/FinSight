# 《知数（FinSight）》隐私与安全检查报告

**日期**：2026-08-12  
**范围**：用户数据删除、原图生命周期、敏感数据、Debt 来源标记、AI 数据授权、错误处理、相关单测

## 结论

本轮已落地隐私 / 安全 / 数据管理能力：用户可删除单笔交易、债务、账单图片、AI 识别记录与全部账户数据；原图默认不落盘；日志经脱敏；Debt 支持要求的来源枚举；AI 发送前经 `AIDataConsent` 门禁；敏感失败走安全错误映射。

**测试结果（2026-08-12）**：Domain 85 / Data 6 / AI 35，全部通过。

## 一、用户数据删除

| 能力 | 实现 | 状态 |
|------|------|------|
| 单笔交易 | `PrivacyDataService.deleteTransaction` | 通过 |
| 债务 | `PrivacyDataService.deleteDebt` | 通过 |
| 账单图片 | `PrivacyDataService.deleteBillImage` + 媒体元数据/二进制 | 通过 |
| AI 识别记录 | `PrivacyDataService.deleteAIRecognitionRecord` / `deleteAll…` | 通过 |
| 全部账户数据 | `PrivacyDataService.wipeAllUserData` → `YoushuStore.deleteUser` 级联 | 通过 |

## 二、原始图片

| 策略 | 说明 | 状态 |
|------|------|------|
| 默认最小化 | `MediaLifecyclePolicy.defaultRetainOriginalImages = false`；默认 `NoPersistMediaBinaryStore` | 通过 |
| 注册元数据 | `MediaLifecycleService.register`（可记字节数/哈希，默认无相对路径） | 通过 |
| AI 完成后清理 | `markProcessedAndMaybePurge`（非 userRetained 即删） | 通过 |
| 用户主动删除 | `deleteImage` / UI 确认后清空内存 `imageData`/`documents` | 通过 |
| 可选保留 | `DirectoryMediaBinaryStore` + `retainOriginalImages`（需显式授权） | 可用 |

## 三、敏感数据检查

| 面 | 现状 | 风险/备注 |
|----|------|-----------|
| 本地数据库 | JSON Snapshot v3；含同意/识别元数据/媒体元数据，默认无原图二进制 | 金额仍在本地业务表（产品必需）；禁止写入测试用真实财务数据 |
| Keychain | 跨平台测试使用 `InMemorySecureTokenStore`；生产应换平台 Keychain 适配器 | 已抽象 `SecureTokenStoring`，尚未接 Apple Keychain |
| API Token | 仅经 `SecureTokenStoring`；禁止写入代码/日志 | 通过（单测覆盖 round-trip） |
| AI 请求 | 截图/账单图/财务 Context 发送前 `require*` 门禁 | 通过 |
| 图片缓存 | 默认不落盘；处理后 purge；UI 丢弃内存副本 | 通过 |
| 日志 | `YoushuLog` → `LogRedactor`：金额/Token/Key/PII/base64 图脱敏 | 通过 |

**禁止入日志（已用红线扫描覆盖）**：完整财务金额、身份信息、Token、API Key、原始账单图片内容。

## 四、Debt 数据来源

`DebtSource` 已包含：`screenshot`、`transactionInference`、`userInput`、`futureAPI`（另保留 `pdf`）。单测校验必选枚举存在。

## 五、AI 数据授权（AIDataConsent）

明确可发送类别（仅在用户授权后）：

1. **记账截图图像字节**（`allowScreenshotImageToAI`）  
2. **债务账单图像字节**（`allowDebtScanImageToAI`）  
3. **聚合财务 Context**（可用资金、本月收支、债务汇总、现金流摘要、目标/预算摘要；不含完整交易明细列表）（`allowFinancialContextToAI`）

默认全部拒绝。`disclosedPayloadDescriptions` 供 UI / 审计展示。App 接线：`AppDependencies` → 截图记账 / 债务扫描 / 财务助手。

## 六、错误处理

- `PrivacyError` + `PrivacySafeErrorMapper`：失败不抛内部细节，不回显金额/Token  
- ViewModel（截图记账 / 债务扫描）捕获后展示安全文案  
- 删除 / 媒体失败映射为用户可读提示，不崩溃

## 七、测试覆盖

| 套件 | 覆盖点 |
|------|--------|
| `PrivacyDataDeletionTests` | 交易/债务/图片/识别记录/全量 wipe |
| `MediaLifecycleTests` | 默认不落盘、处理后 purge、用户保留后主动删 |
| `AIDataConsentTests` | 默认拒绝、截图门禁、助手门禁、披露文案 |
| `TokenAndLogSecurityTests` | Token 存储、日志脱敏扫描、错误映射 |
| `DebtSourcePrivacyTests` | 来源枚举 |
| 既有 AI 测试 | `recognize`/`scan` 已带 `userId`（consent 可选时不挡测试） |

## Migration 说明

- **Schema v2 → v3**：见 `Docs/ADR/0003-privacy-schema-v3.md`  
- 新增：`aiDataConsents`、`aiRecognitionRecords`、`mediaArtifacts`  
- Decode 缺省 `[]`；不改动核心财务金额计算逻辑

## 残留项（非阻塞）

1. Apple Keychain 生产适配器（当前内存实现用于 Windows/测试）  
2. 设置页「隐私与数据」完整 UI（服务层已就绪，可后续接线删除入口）  
3. 对存量日志文件做离线扫描脚本（运行时脱敏已覆盖新日志）

## 合规对照（AGENTS.md）

- 未擅自改产品需求以外的功能范围；Schema 变更已写 Migration/ADR  
- AI 仍不直接写入核心财务金额；确认路径经既有 Validator/DTO  
- 无 API Key 入代码；测试无真实财务数据
