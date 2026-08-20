import SwiftUI
import YoushuDesignSystem
import YoushuDomain
import YoushuFoundation

struct CashFlowDetailRoute: Hashable {
    var projections: [CashFlowHorizonPresentation]
}

struct CashFlowDetailView: View {
    let projections: [CashFlowHorizonPresentation]
    @State private var selectedHorizon: CashFlowHorizon = .days30

    private var selectedPresentation: CashFlowHorizonPresentation? {
        projections.first { $0.horizon == selectedHorizon }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.lg) {
                if projections.isEmpty {
                    Text("目前还没有足够的数据生成现金流预测。")
                        .font(YSTypography.callout)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                } else {
                    horizonPicker
                    if let selectedPresentation {
                        summaryCard(selectedPresentation)
                        driverSection(selectedPresentation)
                        if let riskSummary = selectedPresentation.riskSummary {
                            riskCard(riskSummary)
                        }
                    }
                }
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
        .background(YSColor.Fallback.background)
        .navigationTitle("未来现金流")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(alignSelectedHorizon)
    }

    private var horizonPicker: some View {
        Picker("时间范围", selection: $selectedHorizon) {
            ForEach(projections) { projection in
                Text(CashFlowPresentation.pickerTitle(projection.horizon))
                    .tag(projection.horizon)
            }
        }
        .pickerStyle(.segmented)
    }

    private func summaryCard(_ presentation: CashFlowHorizonPresentation) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                HStack {
                    Text(presentation.title)
                        .font(YSTypography.headline)
                    Spacer()
                    YSBadge(presentation.statusText, tone: badgeTone(for: presentation.status))
                }

                detailMetric(title: "预计期末余额", money: presentation.endingBalance, accent: YSColor.Fallback.brandPrimary)
                detailMetric(title: "窗口内最低余额", money: presentation.minimumBalance, accent: YSColor.Fallback.textPrimary)
                detailRow(
                    title: "最低余额日期",
                    value: CashFlowPresentation.formatDate(presentation.minimumBalanceDate)
                )

                if let peakRepayment = presentation.peakRepayment {
                    detailMetric(title: "峰值还款", money: peakRepayment, accent: YSColor.Fallback.debt)
                } else {
                    detailRow(title: "峰值还款", value: "—")
                }

                if let peakRepaymentDate = presentation.peakRepaymentDate {
                    detailRow(
                        title: "峰值还款日期",
                        value: CashFlowPresentation.formatDate(peakRepaymentDate)
                    )
                } else {
                    detailRow(title: "峰值还款日期", value: "—")
                }
            }
        }
    }

    private func driverSection(_ presentation: CashFlowHorizonPresentation) -> some View {
        YSListSection(title: "现金流来源分类") {
            driverRow(title: "收入", money: presentation.driverBreakdown.income, accent: YSColor.Fallback.income)
            Divider().padding(.leading, YSSpacing.md)
            driverRow(title: "固定支出", money: presentation.driverBreakdown.fixedExpense, accent: YSColor.Fallback.expense)
            Divider().padding(.leading, YSSpacing.md)
            driverRow(title: "债务还款", money: presentation.driverBreakdown.debtRepayment, accent: YSColor.Fallback.debt)
            Divider().padding(.leading, YSSpacing.md)
            driverRow(title: "其他支出", money: presentation.driverBreakdown.otherExpense, accent: YSColor.Fallback.expense)
        }
    }

    private func riskCard(_ summary: String) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.xs) {
                Text("风险摘要")
                    .font(YSTypography.headline)
                Text(summary)
                    .font(YSTypography.callout)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
        }
    }

    private func detailMetric(title: String, money: Money, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xxs) {
            Text(title)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            YSMoneyText(money, style: YSTypography.amountMedium, color: accent)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(YSTypography.callout)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            Spacer()
            Text(value)
                .font(YSTypography.callout)
                .foregroundStyle(YSColor.Fallback.textPrimary)
        }
    }

    private func driverRow(title: String, money: Money, accent: Color) -> some View {
        HStack {
            Text(title)
                .font(YSTypography.body)
                .foregroundStyle(YSColor.Fallback.textPrimary)
            Spacer()
            YSMoneyText(money, style: YSTypography.amountSmall, color: accent)
        }
        .padding(.vertical, YSSpacing.sm)
        .padding(.horizontal, YSSpacing.md)
    }

    private func badgeTone(for status: CashFlowPresentationStatus) -> YSBadgeTone {
        switch status {
        case .safe: .positive
        case .risk: .debt
        }
    }

    private func alignSelectedHorizon() {
        guard !projections.contains(where: { $0.horizon == selectedHorizon }) else { return }
        selectedHorizon = projections.first(where: { $0.horizon == .days30 })?.horizon
            ?? projections.first?.horizon
            ?? .days30
    }
}
