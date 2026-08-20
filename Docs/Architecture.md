# 知数（FinSight）Architecture（Phase 0）

## 分层

```
Apps/Youshu          UI 壳（本阶段无业务页）
Modules/YoushuAI     AI ports + Mock provider
Modules/YoushuData   Store + Repository 实现
Modules/YoushuDomain Entities / Services / Ports
Infrastructure/*     Money / Logging
```

依赖方向：`App → Features(未来) → Domain ← Data/AI`

## MVVM 落点（后续 Feature）

- View：SwiftUI
- ViewModel：`@Observable`，只编排 UseCase / Repository
- Model：Domain 实体与计算器（无 UIKit/SwiftUI）

本阶段尚未引入 Feature 模块，避免空壳过度工程。

## AI 边界

- MockAIProvider 可替换为 OnDevice / Cloud
- AI 只产出 Draft / Insight 文案
- 金额、余额、还款计划由 Domain Services 计算
