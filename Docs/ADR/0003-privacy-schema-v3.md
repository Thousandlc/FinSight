# ADR 0003: Privacy Schema v3

## Status
Accepted

## Context
隐私与数据最小化需要持久化：AI 数据授权、识别审计记录、媒体元数据（默认不含原图二进制）。

## Decision
Bump `YoushuSnapshot.schemaVersion` from 2 to 3.

新增字段：
- `aiDataConsents: [AIDataConsent]`
- `aiRecognitionRecords: [AIRecognitionRecord]`
- `mediaArtifacts: [MediaArtifact]`

## Migration
- Decode 时若缺字段，默认 `[]`
- `YoushuStore.deleteUser` 同步清除上述三类数据
- 默认策略：`retainOriginalImages = false`，原图不落盘（`NoPersistMediaBinaryStore`）

## Consequences
旧本地 JSON 可无缝升级；不删除 v2 业务数据。AI 发送前必须经 `AIDataConsentService` 门禁。
