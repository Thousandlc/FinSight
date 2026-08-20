import SwiftUI
import YoushuDesignSystem
import YoushuDomain

struct CashFlowSectionView: View {
    let presentation: CashFlowSectionPresentation

    var body: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                header
                content
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: YSSpacing.xxs) {
            HStack {
                Text("未来现金流")
                    .font(YSTypography.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YSColor.Fallback.textTertiary)
            }
            Text("看看未来一段时间，资金是否充足")
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if presentation.isEmpty, let message = presentation.emptyMessage {
            Text(message)
                .font(YSTypography.callout)
                .foregroundStyle(YSColor.Fallback.textSecondary)
        } else {
            if let insufficient = presentation.insufficientDataMessage {
                Text(insufficient)
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(presentation.horizons.enumerated()), id: \.element.id) { index, horizon in
                    horizonRow(horizon)
                    if index < presentation.horizons.count - 1 {
                        Divider()
                    }
                }
            }

            if !presentation.footerSummary.isEmpty {
                Text(presentation.footerSummary)
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                    .padding(.top, YSSpacing.xs)
            }
        }
    }

    private func horizonRow(_ horizon: CashFlowHorizonPresentation) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                Text(horizon.title)
                    .font(YSTypography.callout)
                    .foregroundStyle(YSColor.Fallback.textPrimary)
                YSMoneyText(horizon.endingBalance, style: YSTypography.amountMedium)
            }
            Spacer(minLength: YSSpacing.sm)
            YSBadge(horizon.statusText, tone: badgeTone(for: horizon.status))
        }
        .padding(.vertical, YSSpacing.xs)
    }

    private func badgeTone(for status: CashFlowPresentationStatus) -> YSBadgeTone {
        switch status {
        case .safe: .positive
        case .risk: .debt
        }
    }
}
