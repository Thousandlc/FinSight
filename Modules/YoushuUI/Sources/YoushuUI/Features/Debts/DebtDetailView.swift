import SwiftUI
import YoushuDesignSystem
import YoushuDomain
import YoushuFoundation

struct DebtDetailView: View {
    @Bindable var viewModel: DebtViewModel
    let debtId: UUID

    var body: some View {
        Group {
            if let detail = viewModel.detail, detail.id == debtId {
                detailContent(detail)
            } else {
                YSLoadingState(message: "加载债务详情…")
            }
        }
        .background(YSColor.Fallback.background)
        .navigationTitle("债务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑") {
                        if let debt = viewModel.detail?.debt {
                            viewModel.presentEdit(debt)
                        }
                    }
                    Button("记录还款") {
                        viewModel.presentRepayment()
                    }
                    Button("删除", role: .destructive) {
                        if let debt = viewModel.detail?.debt {
                            viewModel.confirmDelete(debt)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingRepayment) {
            DebtRepaymentSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.loadDetail(debtId: debtId)
        }
    }

    private func detailContent(_ detail: DebtDetailSnapshot) -> some View {
        let debt = detail.debt
        return ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.lg) {
                YSCard {
                    VStack(alignment: .leading, spacing: YSSpacing.xs) {
                        Text(debt.lender ?? "未命名债权方")
                            .font(YSTypography.title3)
                        Text(debt.productName ?? debt.debtType.displayName)
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                        outstandingHero(debt.outstandingBalance)
                        Text("信息完整度 \(detail.profileCompletenessPercent)% · \(debt.source.displayName)")
                            .font(YSTypography.caption2)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
                }

                YSCard {
                    VStack(alignment: .leading, spacing: YSSpacing.sm) {
                        detailRow("债权方", debt.lender ?? "—")
                        detailRow("产品名称", debt.productName ?? "—")
                        detailRow("债务类型", debt.debtType.displayName)
                        detailRow("当前欠款", moneyText(debt.outstandingBalance))
                        detailRow("剩余本金", moneyText(debt.outstandingPrincipal))
                        detailRow("本期应还", moneyText(debt.currentDue))
                        detailRow("最低还款", moneyText(debt.minimumDue))
                        detailRow("每期还款", moneyText(debt.installmentAmount))
                        detailRow("还款日", dateText(debt.dueDate))
                        detailRow("剩余期数", debt.remainingInstallments.map(String.init) ?? "—")
                        detailRow("到期日", dateText(debt.maturityDate))
                        detailRow("利率", debt.interestRate.map { "\(NSDecimalNumber(decimal: $0).stringValue)" } ?? "—")
                        detailRow("手续费", moneyText(debt.fee))
                        detailRow("状态", debt.status.displayName)
                        detailRow("数据来源", debt.source.displayName)
                    }
                }

                VStack(alignment: .leading, spacing: YSSpacing.xs) {
                    Text("Debt Event")
                        .font(YSTypography.headline)
                    if detail.events.isEmpty {
                        Text("暂无事件")
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    } else {
                        YSListSection {
                            ForEach(detail.events, id: \.id) { event in
                                YSListRow(
                                    title: event.type.displayName,
                                    subtitle: [
                                        event.date.formatted(date: .abbreviated, time: .shortened),
                                        event.note,
                                    ]
                                    .compactMap { $0 }
                                    .joined(separator: " · "),
                                    trailing: event.amount.map { YSMoneyFormatter.string(for: $0) },
                                    icon: "clock.arrow.circlepath"
                                )
                                if event.id != detail.events.last?.id {
                                    Divider().padding(.leading, YSSpacing.md + 28)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
    }

    @ViewBuilder
    private func outstandingHero(_ balance: Money?) -> some View {
        switch DebtMoneyPresentation(balance) {
        case .unknown:
            Text(DebtMoneyPresentation.unknownPlaceholder)
                .font(YSTypography.amountLarge)
                .foregroundStyle(YSColor.Fallback.debt)
        case .known(let money), .knownIncomplete(let money):
            YSMoneyText(money, style: YSTypography.amountLarge, color: YSColor.Fallback.debt)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            Spacer()
            Text(value)
                .font(YSTypography.callout)
                .multilineTextAlignment(.trailing)
        }
    }

    private func moneyText(_ money: Money?) -> String {
        DebtMoneyPresentation(money).text(formatted: { YSMoneyFormatter.string(for: $0) })
    }

    private func dateText(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
    }
}
