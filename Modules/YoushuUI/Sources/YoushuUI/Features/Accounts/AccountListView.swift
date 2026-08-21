import SwiftUI
import YoushuDesignSystem
import YoushuDomain

public struct AccountListView: View {
    @Bindable private var viewModel: AccountViewModel
    @Bindable private var dataBackupViewModel: DataBackupViewModel
    @Bindable private var privacyAISettingsViewModel: PrivacyAISettingsViewModel

    public init(
        viewModel: AccountViewModel,
        dataBackupViewModel: DataBackupViewModel,
        privacyAISettingsViewModel: PrivacyAISettingsViewModel
    ) {
        self.viewModel = viewModel
        self.dataBackupViewModel = dataBackupViewModel
        self.privacyAISettingsViewModel = privacyAISettingsViewModel
    }

    public var body: some View {
        NavigationStack {
            content
                .background(YSColor.Fallback.background)
                .navigationTitle("账户")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.presentCreate()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $viewModel.isPresentingForm) {
                    AccountFormSheet(viewModel: viewModel)
                }
                .navigationDestination(item: $viewModel.selectedAccountId) { accountId in
                    AccountDetailView(viewModel: viewModel, accountId: accountId)
                }
                .navigationDestination(isPresented: $viewModel.isPresentingPrivacyAISettings) {
                    PrivacyAISettingsView(viewModel: privacyAISettingsViewModel)
                }
                .navigationDestination(isPresented: $isPresentingDataBackup) {
                    DataBackupView(viewModel: dataBackupViewModel)
                }
                .confirmationDialog(
                    "确认删除账户？",
                    isPresented: deleteBinding,
                    titleVisibility: .visible
                ) {
                    Button("删除", role: .destructive) {
                        Task { await viewModel.deleteConfirmed() }
                    }
                    Button("取消", role: .cancel) { viewModel.pendingDeleteSummary = nil }
                } message: {
                    Text("仅可删除无交易记录的账户。")
                }
        }
        .task { await viewModel.load() }
    }

    @State private var isPresentingDataBackup = false

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            YSLoadingState()
        case .empty(let config):
            settingsReachableScroll {
                YSEmptyState(config: config) { viewModel.presentCreate() }
            }
        case .error(let message):
            YSErrorState(message: message) { Task { await viewModel.load() } }
        case .content(let snapshot):
            accountList(snapshot)
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeleteSummary != nil },
            set: { if !$0 { viewModel.pendingDeleteSummary = nil } }
        )
    }

    private func accountList(_ snapshot: AccountListSnapshot) -> some View {
        settingsReachableScroll {
            YSCard {
                VStack(alignment: .leading, spacing: YSSpacing.xs) {
                    Text("可用资金")
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                    YSMoneyText(snapshot.totalAvailableFunds, style: YSTypography.amountLarge)
                    Text("不含信用卡负债账户")
                        .font(YSTypography.caption2)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                }
            }
            YSListSection(title: "我的账户") {
                ForEach(snapshot.accounts) { summary in
                    Button {
                        viewModel.openDetail(summary)
                    } label: {
                        accountRow(summary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑") { viewModel.presentEdit(summary) }
                        Button("删除", role: .destructive) { viewModel.confirmDelete(summary) }
                    }
                    if summary.id != snapshot.accounts.last?.id {
                        Divider().padding(.leading, YSSpacing.md + 28)
                    }
                }
            }
        }
    }

    private func settingsReachableScroll<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        ScrollView {
            VStack(spacing: YSSpacing.md) {
                header()
                privacySection
                dataBackupSection
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
    }

    private var dataBackupSection: some View {
        YSListSection(title: "数据与备份") {
            Button {
                isPresentingDataBackup = true
            } label: {
                YSListRow(
                    title: "数据与备份",
                    subtitle: "创建加密备份或从备份恢复",
                    icon: "externaldrive"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("数据与备份")
        }
    }

    private var privacySection: some View {
        YSListSection(title: "隐私与 AI") {
            Button {
                viewModel.openPrivacyAISettings()
            } label: {
                YSListRow(
                    title: "隐私与 AI",
                    subtitle: "管理 AI 授权与原图保留",
                    icon: "hand.raised"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("隐私与 AI")
            .accessibilityIdentifier("account-privacy-ai-entry")
        }
    }

    private func accountRow(_ summary: AccountSummary) -> some View {
        HStack(spacing: YSSpacing.sm) {
            Image(systemName: icon(for: summary.account.type))
                .foregroundStyle(YSColor.Fallback.brandPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.account.name)
                    .font(YSTypography.body.weight(.medium))
                    .foregroundStyle(YSColor.Fallback.textPrimary)
                HStack(spacing: YSSpacing.xs) {
                    YSBadge(summary.account.type.displayName, tone: .brand)
                    if summary.account.type == .creditCard {
                        YSBadge("关联债务", tone: .debt)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                YSMoneyText(summary.currentBalance, style: YSTypography.amountSmall)
                Text("\(summary.transactionCount) 笔交易")
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(YSColor.Fallback.textTertiary)
        }
        .padding(.vertical, YSSpacing.sm)
        .padding(.horizontal, YSSpacing.md)
    }

    private func icon(for type: AccountType) -> String {
        switch type {
        case .cash: "banknote"
        case .bankCard: "creditcard"
        case .creditCard: "creditcard.fill"
        case .alipay: "a.circle"
        case .weChat: "message"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
