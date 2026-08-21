import SwiftUI
import YoushuDesignSystem
import YoushuDomain
import YoushuFoundation

public struct HomeView: View {
    @Bindable private var viewModel: HomeViewModel
    @State private var cashFlowDetailRoute: CashFlowDetailRoute?

    public init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        YSPageContainer(title: "首页", phase: viewModel.phase, onRetry: retry) { overview in
            ScrollView {
                VStack(alignment: .leading, spacing: YSSpacing.lg) {
                    availableFundsSection(overview)
                    metricsGrid(overview)
                    healthSection(overview)
                    cashFlowSection(overview)
                    aiSummarySection(overview)
                }
                .padding(.horizontal, YSSpacing.md)
                .padding(.bottom, YSSpacing.xxl)
            }
            .navigationDestination(item: $cashFlowDetailRoute) { route in
                CashFlowDetailView(projections: route.projections)
            }
        }
        .task { await viewModel.load() }
    }

    private func retry() {
        Task { await viewModel.load() }
    }

    private func availableFundsSection(_ overview: HomeOverview) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.xs) {
                Text("可用资金")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                if overview.hasAccounts || overview.hasTransactions {
                    YSMoneyText(overview.availableFunds, style: YSTypography.amountLarge)
                } else {
                    Text("—")
                        .font(YSTypography.amountLarge)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                }
                Text(overview.isEmpty ? "添加账户或记录交易后显示" : "基于账户期初余额与交易记录计算")
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textTertiary)
            }
        }
    }

    private func metricCard(title: String, money: Money, accent: Color, showPlaceholder: Bool) -> some View {
        YSCard(padding: YSSpacing.sm) {
            VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                Text(title)
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if showPlaceholder {
                    Text("—")
                        .font(YSTypography.amountSmall)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                } else {
                    YSMoneyText(money, style: YSTypography.amountSmall, color: accent)
                }
            }
        }
    }

    private func metricsGrid(_ overview: HomeOverview) -> some View {
        let placeholder = overview.isEmpty
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: YSSpacing.sm) {
            metricCard(title: "本月收入", money: overview.monthlyIncome, accent: YSColor.Fallback.income, showPlaceholder: placeholder)
            metricCard(title: "本月生活支出", money: overview.monthlyLivingExpense, accent: YSColor.Fallback.expense, showPlaceholder: placeholder)
            metricCard(title: "本月债务还款", money: overview.monthlyDebtRepayment, accent: YSColor.Fallback.debt, showPlaceholder: placeholder)
            metricCard(title: "预计月底结余", money: overview.projectedMonthEndBalance, accent: YSColor.Fallback.brandPrimary, showPlaceholder: placeholder)
        }
    }

    private func healthSection(_ overview: HomeOverview) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                HStack {
                    Text("财务健康度")
                        .font(YSTypography.headline)
                    Spacer()
                    if let score = overview.financialHealthScore {
                        YSBadge("\(score) 分", tone: score >= 70 ? .positive : .warning)
                    } else {
                        YSBadge("数据不足", tone: .neutral)
                    }
                }
                if let score = overview.financialHealthScore {
                    ProgressView(value: Double(score), total: 100)
                        .tint(YSColor.Fallback.positive)
                    Text("基于收入、支出与负债比例估算，仅供参考。")
                        .font(YSTypography.caption2)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                } else {
                    Text("继续记录交易与债务信息，系统将自动评估。")
                        .font(YSTypography.callout)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                }
            }
        }
    }

    private func cashFlowSection(_ overview: HomeOverview) -> some View {
        let presentation = CashFlowPresentation.makeSection(from: overview)
        return Button {
            guard !presentation.isEmpty else { return }
            cashFlowDetailRoute = CashFlowDetailRoute(
                projections: CashFlowPresentation.makeDetail(from: overview)
            )
        } label: {
            CashFlowSectionView(presentation: presentation)
        }
        .buttonStyle(.plain)
        .disabled(presentation.isEmpty)
    }

    private func aiSummarySection(_ overview: HomeOverview) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                HStack {
                    Text("AI 摘要")
                        .font(YSTypography.headline)
                    Spacer()
                    YSBadge("可解释", tone: .brand)
                }
                if let insight = overview.aiSummary {
                    Text(insight.title)
                        .font(YSTypography.callout.weight(.medium))
                    Text(insight.body)
                        .font(YSTypography.callout)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                    Text(insight.modelName == "deterministic"
                           ? PrivacyAIDisclosureCopy.homeDeterministicCaption
                           : PrivacyAIDisclosureCopy.homeAuthorizedCaption)
                        .font(YSTypography.caption2)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                } else {
                    Text("暂无 AI 摘要")
                        .font(YSTypography.callout)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                    Text(PrivacyAIDisclosureCopy.homeEmptyCaption)
                        .font(YSTypography.caption2)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                }
            }
        }
    }
}
