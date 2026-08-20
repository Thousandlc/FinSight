# ADR 0001 — MVP 本地持久化采用版本化 JSON Store

## Status

Accepted (Phase 0)

## Context

需要可单测的 Repository，并在无 Xcode 的环境验证持久化。SwiftData 仅 Apple 平台可用。

## Decision

1. Domain 使用纯 Swift 结构体 + UUID 关系。
2. Data 层用 `YoushuStore`（actor）+ `YoushuSnapshot`（Codable JSON，schemaVersion）。
3. Repository 实现 Domain ports；未来可替换为 SwiftData 而不改 Domain。
4. `SwiftDataModels.swift` 预留 `@Model` 映射，供后续迁移。

## Consequences

- 好处：测试快、边界清晰、跨平台可跑 Domain/Data 测试。
- 代价：尚未使用 SwiftData 查询/迁移工具；大数据量需后续迁移。
- 总负债、账户余额等**不作为权威字段单独存库汇总表**；由 `Debt` / `Transaction` 计算。
