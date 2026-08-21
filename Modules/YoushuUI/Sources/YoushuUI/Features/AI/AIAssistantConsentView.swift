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
                        Text(PrivacyAIDisclosureCopy.assistantConsentTitle)
                            .font(YSTypography.title3)
                        Text(PrivacyAIDisclosureCopy.assistantConsentBody)
                            .font(YSTypography.body)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                        Text(PrivacyAIDisclosureCopy.assistantConsentGuarantee)
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
                    message: PrivacyAIDisclosureCopy.assistantUnauthorizedMessage,
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
