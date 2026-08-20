import SwiftUI
import YoushuDesignSystem
import YoushuDomain

struct AccountDetailView: View {
    @Bindable var viewModel: AccountViewModel
    let accountId: UUID

    var body: some View {
        Group {
            switch viewModel.detailPhase {
            case .loading:
                YSLoadingState()
            case .error(let message):
                YSErrorState(message: message) {
                    Task { await viewModel.loadDetail(accountId: accountId) }
                }
            case .empty:
                YSEmptyState(config: YSEmptyStateConfig(icon: "wallet.pass", title: "无数据", message: ""))
            case .content(let detail):
                detailContent(detail)
            }
        }
        .navigationTitle(detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if case .content(let detail) = viewModel.detailPhase {
                        Button("编辑") {
                            viewModel.presentEdit(AccountSummary(
                                account: detail.account,
                                currentBalance: detail.currentBalance,
                                transactionCount: detail.recentTransactions.count
                            ))
                        }
                        Button("删除", role: .destructive) {
                            viewModel.confirmDelete(AccountSummary(
                                account: detail.account,
                                currentBalance: detail.currentBalance,
                                transactionCount: detail.recentTransactions.count
                            ))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await viewModel.loadDetail(accountId: accountId) }
    }

    private var detailTitle: String {
        if case .content(let detail) = viewModel.detailPhase {
            return detail.account.name
        }
        return "账户详情"
    }

    private func detailContent(_ detail: AccountDetailSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.lg) {
                YSCard {
                    VStack(alignment: .leading, spacing: YSSpacing.sm) {
                        Text("当前余额")
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                        YSMoneyText(detail.currentBalance, style: YSTypography.amountLarge)
                        HStack {
                            YSBadge(detail.account.type.displayName, tone: .brand)
                            Text(detail.account.currencyCode)
                                .font(YSTypography.caption)
                                .foregroundStyle(YSColor.Fallback.textSecondary)
                        }
                        if let note = detail.account.note, !note.isEmpty {
                            Text(note)
                                .font(YSTypography.callout)
                                .foregroundStyle(YSColor.Fallback.textSecondary)
                        }
                    }
                }

                if let debt = detail.linkedDebt {
                    YSCard {
                        VStack(alignment: .leading, spacing: YSSpacing.xs) {
                            Text("关联债务")
                                .font(YSTypography.caption)
                                .foregroundStyle(YSColor.Fallback.textSecondary)
                            Text(debt.productName ?? debt.lender ?? "信用卡债务")
                                .font(YSTypography.headline)
                            if let bal = debt.outstandingBalance {
                                YSMoneyText(bal, style: YSTypography.amountSmall, color: YSColor.Fallback.debt)
                            }
                            Text("账户记录现金流，债务记录真实欠款。")
                                .font(YSTypography.caption2)
                                .foregroundStyle(YSColor.Fallback.textTertiary)
                        }
                    }
                }

                if !detail.recentTransactions.isEmpty {
                    YSListSection(title: "最近交易") {
                        ForEach(detail.recentTransactions, id: \.id) { tx in
                            YSListRow(
                                title: tx.merchant ?? tx.category ?? "交易",
                                subtitle: tx.date.formatted(date: .abbreviated, time: .shortened),
                                trailing: YSMoneyFormatter.string(for: tx.amount)
                            )
                            if tx.id != detail.recentTransactions.last?.id {
                                Divider().padding(.leading, YSSpacing.md + 28)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
    }
}
