import SwiftUI
import YoushuDesignSystem
import YoushuDomain
import YoushuFoundation

public struct TransactionView: View {
    @Bindable private var viewModel: TransactionViewModel
    private let screenshotViewModel: ScreenshotBookkeepingViewModel

    public init(
        viewModel: TransactionViewModel,
        screenshotViewModel: ScreenshotBookkeepingViewModel
    ) {
        self.viewModel = viewModel
        self.screenshotViewModel = screenshotViewModel
    }

    public var body: some View {
        NavigationStack {
            content
                .background(YSColor.Fallback.background)
                .navigationTitle("账单")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .sheet(isPresented: $viewModel.isPresentingForm) {
                    TransactionFormSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $viewModel.isPresentingScreenshotBookkeeping) {
                    ScreenshotBookkeepingSheet(viewModel: screenshotViewModel)
                        .onAppear { screenshotViewModel.prepareForPresentation() }
                        .onDisappear { screenshotViewModel.handleDismiss() }
                }
                .confirmationDialog(
                    "确认删除这笔交易？",
                    isPresented: deleteDialogBinding,
                    titleVisibility: .visible
                ) {
                    Button("删除", role: .destructive) {
                        Task { await viewModel.deleteConfirmed() }
                    }
                    Button("取消", role: .cancel) {
                        viewModel.pendingDeleteItem = nil
                    }
                } message: {
                    Text("删除后无法恢复，关联账户余额将重新计算。")
                }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            YSLoadingState()
        case .empty(let config):
            YSEmptyState(config: config) {
                viewModel.presentCreate()
            }
        case .error(let message):
            YSErrorState(message: message) {
                Task { await viewModel.load() }
            }
        case .content(let snapshot):
            transactionList(snapshot)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: YSSpacing.sm) {
                Button {
                    viewModel.presentScreenshotBookkeeping()
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .accessibilityLabel("截图记账")

                Button {
                    viewModel.presentCreate()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("记一笔")
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeleteItem != nil },
            set: { if !$0 { viewModel.pendingDeleteItem = nil } }
        )
    }

    private func transactionList(_ snapshot: TransactionListSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.lg) {
                monthlySummary(snapshot.monthlyStats)
                ForEach(snapshot.sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
    }

    private func monthlySummary(_ stats: MonthlyStats) -> some View {
        YSCard {
            HStack {
                summaryColumn(title: "本月收入", money: stats.income, color: YSColor.Fallback.income)
                Spacer()
                summaryColumn(title: "本月支出", money: stats.expense, color: YSColor.Fallback.expense)
                Spacer()
                summaryColumn(title: "结余", money: stats.net, color: YSColor.Fallback.brandPrimary)
            }
        }
    }

    private func summaryColumn(title: String, money: Money, color: Color) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xxs) {
            Text(title)
                .font(YSTypography.caption2)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            YSMoneyText(money, style: YSTypography.amountSmall, color: color)
        }
    }

    private func sectionView(_ section: TransactionDateSection) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xs) {
            Text(section.title)
                .font(YSTypography.headline)
                .foregroundStyle(YSColor.Fallback.textPrimary)
            YSListSection {
                ForEach(section.items) { item in
                    TransactionRowView(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.presentEdit(item) }
                        .contextMenu {
                            Button("编辑") { viewModel.presentEdit(item) }
                            Button("删除", role: .destructive) { viewModel.confirmDelete(item) }
                        }
                    if item.id != section.items.last?.id {
                        Divider().padding(.leading, YSSpacing.md)
                    }
                }
            }
        }
    }
}

struct TransactionRowView: View {
    let item: TransactionListItem

    var body: some View {
        HStack(alignment: .top, spacing: YSSpacing.sm) {
            VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                HStack {
                    Text(item.transaction.merchant ?? item.transaction.category ?? "未命名")
                        .font(YSTypography.body.weight(.medium))
                    Spacer()
                    YSMoneyText(
                        item.transaction.amount,
                        style: YSTypography.amountSmall,
                        color: amountColor,
                        showSign: item.displayType == .income
                    )
                }
                HStack(spacing: YSSpacing.xs) {
                    YSBadge(item.transaction.category ?? "—", tone: .neutral)
                    YSBadge(typeLabel, tone: typeTone)
                }
                HStack {
                    Text(item.accountName)
                    Text("·")
                    Text(item.transaction.date.formatted(date: .omitted, time: .shortened))
                }
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            }
        }
        .padding(.vertical, YSSpacing.sm)
        .padding(.horizontal, YSSpacing.md)
    }

    private var typeLabel: String {
        switch item.displayType {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        default: item.displayType.rawValue
        }
    }

    private var typeTone: YSBadgeTone {
        switch item.displayType {
        case .income: .positive
        case .expense: .neutral
        case .transfer: .brand
        default: .neutral
        }
    }

    private var amountColor: Color {
        switch item.displayType {
        case .income: YSColor.Fallback.income
        case .expense: YSColor.Fallback.expense
        case .transfer: YSColor.Fallback.brandPrimary
        default: YSColor.Fallback.textPrimary
        }
    }
}
