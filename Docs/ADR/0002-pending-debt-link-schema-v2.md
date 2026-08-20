# ADR 0002: Pending Debt Link Schema v2

## Status
Accepted

## Context
Transaction → Debt 自动关联需要持久化「待确认关联」与「疑似周期性债务」，以便用户确认/忽略后可追溯。

## Decision
Bump `YoushuSnapshot.schemaVersion` from 1 to 2.

新增字段：
- `pendingDebtLinks: [PendingDebtLink]`
- `suspectedDebts: [SuspectedDebt]`

## Migration
- Decode 时若缺字段，默认 `[]`
- `YoushuStore.reloadFromDisk` 在加载 schema < 2 时写回 schemaVersion = 2

## Consequences
旧本地 JSON 可无缝升级；不删除 v1 数据。
