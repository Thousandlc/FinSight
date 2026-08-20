# 知数（FinSight）

面向中国用户的 AI 个人财务助手 — iOS MVP 工程骨架。

> 工程内部模块与 Target 仍沿用历史代号 Youshu；用户可见品牌为 **知数 / FinSight**。

## 本阶段范围

- 模块化 SPM 骨架：Domain / Data / AI / DesignSystem / UI
- App Shell：5 Tab 导航 + 页面空/加载/错误状态
- Design System：Color / Typography / Spacing / 基础组件
- ViewModel 经 Domain Provider 加载，Mock 独立在 `YoushuUIPreviewMocks`
- 单元测试（Domain / Data）

## 模块

| 模块 | 职责 |
|------|------|
| `YoushuDomain` | 实体、枚举、Repository 端口、余额/债务计算、ReadModel |
| `YoushuData` | JSON 持久化、Repository、Overview 服务组装 |
| `YoushuAI` | AI 端口 + `MockAIProvider` |
| `YoushuDesignSystem` | 设计令牌与 UI 组件 |
| `YoushuUI` | Tab Shell、Feature Views、ViewModels |
| `YoushuUIPreviewMocks` | Preview 专用 Mock 数据与 Provider |
| `YoushuFoundation` | `Money` 等基础类型 |
| `YoushuLogging` | 轻量日志 |

## 在 macOS / Xcode 中运行 App

1. 安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（可选）：`brew install xcodegen`
2. 在仓库根目录：

```bash
xcodegen generate
open Youshu.xcodeproj
```

或直接 `File → Open → Package.swift`，再按 `project.yml` 配置 App Target。

3. 选择 iPhone Simulator（建议 iPhone 16 / SE / 15 Pro Max 各测一遍）
4. Run（⌘R）
5. 在 Xcode Canvas 中打开 `FeaturePreviews.swift` 预览各 Tab、深色模式

也可：

```bash
./scripts/build-ios.sh
```

## 运行测试

**macOS（全量）**

```bash
swift test
```

**Windows（Domain / Data，不含 SwiftUI）**

```bat
scripts\test-windows.bat
```

## 架构原则（摘要）

- **Transaction** 是底层事实
- **Account / Asset / Debt** 是财务对象
- **余额 / 总负债 / 现金流** 由确定性代码计算，不交给 LLM
- **FinancialInsight** 必须带 `source*Ids` 以便追溯
