import SwiftUI
import YoushuDesignSystem

struct AIAssistantConsentView: View {
    let isAccepting: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.lg) {
                YSCard {
                    VStack(alignment: .leading, spacing: YSSpacing.sm) {
                        Text("让 AI 帮你看懂财务")
                            .font(YSTypography.title3)
                        Text("为了回答你的财务问题，《知数》需要读取部分与你问题相关的财务信息，例如账户余额、交易记录、债务和现金流预测。")
                            .font(YSTypography.body)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                        Text("AI 不会因为你使用助手而自动修改你的账户、交易或债务数据。")
                            .font(YSTypography.body)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
                }
                YSButton("同意并继续", isLoading: isAccepting, action: onAccept)
                YSButton("暂不使用", kind: .secondary, action: onDecline)
            }
            .padding(YSSpacing.md)
        }
    }
}

struct AIAssistantDeclinedView: View {
    let onAuthorize: () -> Void

    var body: some View {
        VStack(spacing: YSSpacing.lg) {
            Spacer()
            YSEmptyState(
                config: YSEmptyStateConfig(
                    icon: "hand.raised",
                    title: "尚未授权 AI 助手",
                    message: "你还没有授权 AI 使用你的财务信息。",
                    actionTitle: nil
                )
            )
            YSButton("授权并继续", action: onAuthorize)
                .padding(.horizontal, YSSpacing.md)
            Spacer()
        }
        .padding(YSSpacing.md)
    }
}
