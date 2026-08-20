import SwiftUI
import YoushuDesignSystem
import YoushuDomain

public struct AccountListView: View {
    @Bindable private var viewModel: AccountViewModel
    @Bindable private var dataBackupViewModel: DataBackupViewModel

    public init(viewModel: AccountViewModel, dataBackupViewModel: DataBackupViewModel) {
        self.viewModel = viewModel
        self.dataBackupViewModel = dataBackupViewModel
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
            YSEmptyState(config: config) { viewModel.presentCreate() }
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
        ScrollView {
            VStack(spacing: YSSpacing.md) {
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
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                        Text("AI 财务助手")
                            .font(YSTypography.body.weight(.medium))
                            .foregroundStyle(YSColor.Fallback.textPrimary)
                        Text(assistantConsentStatusText)
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
                    Spacer()
                    if viewModel.assistantConsentAuthorized == true {
                        YSBadge("已授权", tone: .positive)
                    } else if viewModel.assistantConsentAuthorized == false {
                        YSBadge("未授权", tone: .warning)
                    }
                }
                if viewModel.assistantConsentAuthorized == true {
                    YSButton(
                        "撤销授权",
                        kind: .secondary,
                        isLoading: viewModel.isUpdatingConsent
                    ) {
                        Task { await viewModel.revokeAssistantConsent() }
                    }
                } else if viewModel.assistantConsentAuthorized == false {
                    YSButton(
                        "授权 AI 助手",
                        isLoading: viewModel.isUpdatingConsent
                    ) {
                        Task { await viewModel.grantAssistantConsent() }
                    }
                }
                if let error = viewModel.consentActionError {
                    Text(error)
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.expense)
                }
            }
            .padding(.vertical, YSSpacing.sm)
            .padding(.horizontal, YSSpacing.md)
        }
    }

    private var assistantConsentStatusText: String {
        switch viewModel.assistantConsentAuthorized {
        case true:
            "已允许 AI 读取聚合财务 Context 以回答你的问题。"
        case false:
            "尚未授权 AI 使用你的财务信息。"
        case nil:
            "正在读取授权状态…"
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
