import SwiftUI
import YoushuDesignSystem
import YoushuDomain
import YoushuFoundation

/// 已校验 Assistant 回答的展示卡片。只消费 Presentation，不解析 Domain 事实。
public struct AssistantAnswerCardView: View {
    private let presentation: AssistantAnswerPresentation
    private let onNavigateToTab: ((MainTab) -> Void)?

    public init(
        presentation: AssistantAnswerPresentation,
        onNavigateToTab: ((MainTab) -> Void)? = nil
    ) {
        self.presentation = presentation
        self.onNavigateToTab = onNavigateToTab
    }

    public var body: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                Text(presentation.title)
                    .font(YSTypography.headline)
                Text(presentation.question)
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textTertiary)
                Text(presentation.body)
                    .font(YSTypography.callout)
                    .foregroundStyle(YSColor.Fallback.textSecondary)

                if !presentation.keyFacts.isEmpty {
                    keyFactsSection(presentation.keyFacts)
                }
                if !presentation.warnings.isEmpty {
                    warningsSection(presentation.warnings)
                }
                if !presentation.actions.isEmpty {
                    actionsSection(presentation.actions)
                }

                if !presentation.factSources.isEmpty {
                    Text("数据来源：\(presentation.factSources.joined(separator: " / "))")
                        .font(YSTypography.caption2)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                }
            }
        }
    }

    private func keyFactsSection(_ facts: [AssistantAnswerPresentation.KeyFactPresentation]) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xs) {
            Text("关键数据")
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            VStack(spacing: 0) {
                ForEach(facts) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: YSSpacing.sm) {
                        Text(fact.label)
                            .font(YSTypography.body)
                            .foregroundStyle(YSColor.Fallback.textPrimary)
                        Spacer(minLength: YSSpacing.sm)
                        keyFactValueView(fact.displayValue)
                    }
                    .padding(.vertical, YSSpacing.sm)
                    .padding(.horizontal, YSSpacing.md)
                    if fact.id != facts.last?.id {
                        Divider()
                            .padding(.leading, YSSpacing.md)
                    }
                }
            }
            .background(YSColor.Fallback.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: YSRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: YSRadius.md, style: .continuous)
                    .strokeBorder(YSColor.Fallback.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private func keyFactValueView(_ value: AssistantAnswerPresentation.KeyFactDisplayValue) -> some View {
        switch value {
        case .money(let money):
            YSMoneyText(money, style: YSTypography.amountSmall)
        case .text(let text):
            Text(text)
                .font(YSTypography.amountSmall)
                .foregroundStyle(YSColor.Fallback.textSecondary)
        case .percent(let percent):
            Text("\(NSDecimalNumber(decimal: percent).stringValue)%")
                .font(YSTypography.amountSmall)
                .foregroundStyle(YSColor.Fallback.textSecondary)
                .monospacedDigit()
        case .date(let date):
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(YSTypography.amountSmall)
                .foregroundStyle(YSColor.Fallback.textSecondary)
        }
    }

    private func warningsSection(_ warnings: [AssistantAnswerPresentation.WarningPresentation]) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xs) {
            Text("提示")
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            ForEach(warnings) { warning in
                YSCard(padding: YSSpacing.sm) {
                    VStack(alignment: .leading, spacing: YSSpacing.xs) {
                        HStack(spacing: YSSpacing.xs) {
                            Text(warning.title)
                                .font(YSTypography.callout.weight(.medium))
                            Spacer(minLength: YSSpacing.xs)
                            YSBadge(warningBadgeText(warning.severity), tone: warningBadgeTone(warning.severity))
                        }
                        Text(warning.message)
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
                }
            }
        }
    }

    private func actionsSection(_ actions: [AssistantAnswerPresentation.ActionPresentation]) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xs) {
            Text("下一步")
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            ForEach(actions.filter(\.isNavigable)) { action in
                YSButton(action.title, kind: .secondary) {
                    guard let tab = mainTab(for: action.destination) else { return }
                    onNavigateToTab?(tab)
                }
            }
        }
    }

    private func warningBadgeText(_ severity: AssistantWarningSeverity) -> String {
        switch severity {
        case .safe: "正常"
        case .warning: "注意"
        case .risk: "风险"
        }
    }

    private func warningBadgeTone(_ severity: AssistantWarningSeverity) -> YSBadgeTone {
        switch severity {
        case .safe: .positive
        case .warning: .warning
        case .risk: .debt
        }
    }

    private func mainTab(for destination: AssistantActionDestination) -> MainTab? {
        switch destination {
        case .cashFlow: .home
        case .debt: .debts
        case .transactions: .transactions
        case .accounts: .assets
        }
    }
}
