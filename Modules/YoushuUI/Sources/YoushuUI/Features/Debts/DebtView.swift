import SwiftUI
import YoushuDesignSystem
import YoushuDomain
import YoushuFoundation

public struct DebtView: View {
    @Bindable private var viewModel: DebtViewModel
    private let scannerViewModel: DebtScannerViewModel

    public init(viewModel: DebtViewModel, scannerViewModel: DebtScannerViewModel) {
        self.viewModel = viewModel
        self.scannerViewModel = scannerViewModel
    }

    public var body: some View {
        NavigationStack {
            content
                .background(YSColor.Fallback.background)
                .navigationTitle("债务")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            viewModel.presentScanner()
                        } label: {
                            Image(systemName: "doc.text.viewfinder")
                        }
                        .accessibilityLabel("扫描债务")

                        Button {
                            viewModel.presentCreate()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加债务")
                    }
                }
                .sheet(isPresented: $viewModel.isPresentingForm) {
                    DebtFormSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $viewModel.isPresentingScanner) {
                    DebtScannerSheet(viewModel: scannerViewModel)
                        .onAppear { scannerViewModel.prepareForPresentation() }
                        .onDisappear { scannerViewModel.handleDismiss() }
                }
                .navigationDestination(item: $viewModel.selectedDebtId) { debtId in
                    DebtDetailView(viewModel: viewModel, debtId: debtId)
                }
                .confirmationDialog(
                    "确认删除这笔债务？",
                    isPresented: deleteBinding,
                    titleVisibility: .visible
                ) {
                    Button("删除", role: .destructive) {
                        Task { await viewModel.deleteConfirmed() }
                    }
                    Button("取消", role: .cancel) { viewModel.pendingDeleteDebt = nil }
                } message: {
                    Text("相关 Debt Event 也会一并删除。")
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
            VStack(spacing: YSSpacing.lg) {
                YSEmptyState(config: config) {
                    viewModel.presentScanner()
                }
                YSButton("手动添加债务", kind: .secondary) {
                    viewModel.presentCreate()
                }
                .padding(.horizontal, YSSpacing.xl)
            }
        case .error(let message):
            YSErrorState(message: message) { Task { await viewModel.load() } }
        case .content(let snapshot):
            debtCenter(snapshot)
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeleteDebt != nil },
            set: { if !$0 { viewModel.pendingDeleteDebt = nil } }
        )
    }

    private func debtCenter(_ snapshot: DebtListSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.lg) {
                overviewCards(snapshot)
                filterBar
                debtList(snapshot)
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
    }

    private func overviewCards(_ snapshot: DebtListSnapshot) -> some View {
        VStack(spacing: YSSpacing.md) {
            YSCard {
                VStack(alignment: .leading, spacing: YSSpacing.xs) {
                    Text("总剩余债务")
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                    outstandingTotalHero(snapshot)
                }
            }

            HStack(spacing: YSSpacing.sm) {
                metricCard(title: "预计每月还款", presentation: snapshot.estimatedMonthlyPresentation)
                metricCard(
                    title: "债务压力",
                    text: "\(snapshot.debtPressureLevel.displayName) · \(snapshot.debtPressureScore)"
                )
            }

            YSCard {
                VStack(alignment: .leading, spacing: YSSpacing.sm) {
                    overviewRow(
                        title: "最近一次还款",
                        value: lastRepaymentText(snapshot)
                    )
                    Divider()
                    overviewRow(
                        title: "高成本债务",
                        value: snapshot.highCostDebts.isEmpty
                            ? "暂无"
                            : snapshot.highCostDebts.prefix(2).map { $0.lender ?? $0.productName ?? "债务" }.joined(separator: "、")
                    )
                    Divider()
                    overviewRow(
                        title: "预计清偿时间",
                        value: snapshot.debtFreeEstimate.map {
                            $0.formatted(date: .abbreviated, time: .omitted)
                        } ?? "信息不足"
                    )
                    if let nextDate = snapshot.nextPaymentDate {
                        Divider()
                        overviewRow(
                            title: "下期还款",
                            value: [
                                snapshot.nextPaymentLabel,
                                nextDate.formatted(date: .abbreviated, time: .omitted),
                                snapshot.nextPaymentAmount.map { YSMoneyFormatter.string(for: $0) }
                                    ?? DebtMoneyPresentation.unknownPlaceholder,
                            ]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func outstandingTotalHero(_ snapshot: DebtListSnapshot) -> some View {
        derivedMoneyStack(snapshot.outstandingPresentation, style: YSTypography.amountLarge, color: YSColor.Fallback.debt)
    }

    @ViewBuilder
    private func derivedMoneyStack(
        _ presentation: DebtMoneyPresentation,
        style: Font,
        color: Color = YSColor.Fallback.textPrimary
    ) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xxs) {
            switch presentation {
            case .unknown:
                Text(DebtMoneyPresentation.unknownPlaceholder)
                    .font(style)
                    .foregroundStyle(color)
            case .known(let money), .knownIncomplete(let money):
                YSMoneyText(money, style: style, color: color)
            }
            if let caption = presentation.caption {
                Text(caption)
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
        }
    }

    private func metricCard(title: String, presentation: DebtMoneyPresentation) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                Text(title)
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                derivedMoneyStack(presentation, style: YSTypography.amountSmall)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricCard(title: String, text: String) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                Text(title)
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                Text(text)
                    .font(YSTypography.headline)
                    .foregroundStyle(YSColor.Fallback.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func overviewRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            Spacer()
            Text(value)
                .font(YSTypography.callout)
                .multilineTextAlignment(.trailing)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: YSSpacing.sm) {
            Picker("排序", selection: $viewModel.sort) {
                ForEach(DebtListSort.allCases, id: \.self) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YSSpacing.xs) {
                    filterChip("全部类型", selected: viewModel.typeFilter == nil) {
                        viewModel.typeFilter = nil
                    }
                    ForEach(DebtType.mvpCases, id: \.self) { type in
                        filterChip(type.displayName, selected: viewModel.typeFilter == type) {
                            viewModel.typeFilter = type
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YSSpacing.xs) {
                    filterChip("全部状态", selected: viewModel.statusFilter == nil) {
                        viewModel.statusFilter = nil
                    }
                    ForEach([DebtStatus.active, .overdue, .paidOff], id: \.self) { status in
                        filterChip(status.displayName, selected: viewModel.statusFilter == status) {
                            viewModel.statusFilter = status
                        }
                    }
                }
            }

            TextField("按债权方筛选", text: $viewModel.lenderQuery)
                .padding(YSSpacing.sm)
                .background(YSColor.Fallback.surface)
                .clipShape(RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous))
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(YSTypography.caption)
                .padding(.horizontal, YSSpacing.sm)
                .padding(.vertical, YSSpacing.xs)
                .background(selected ? YSColor.Fallback.brandPrimary : YSColor.Fallback.surface)
                .foregroundStyle(selected ? Color.white : YSColor.Fallback.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func debtList(_ snapshot: DebtListSnapshot) -> some View {
        let debts = viewModel.filteredDebts(from: snapshot)
        return VStack(alignment: .leading, spacing: YSSpacing.xs) {
            Text("债务列表")
                .font(YSTypography.headline)
            if debts.isEmpty {
                Text("没有符合筛选条件的债务")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            } else {
                YSListSection {
                    ForEach(debts, id: \.id) { debt in
                        Button {
                            viewModel.openDetail(debt)
                        } label: {
                            YSListRow(
                                title: debt.lender ?? debt.productName ?? "未命名债务",
                                subtitle: "\(debt.debtType.displayName) · \(debt.status.displayName) · 完整度 \(DebtProfileCompleteness.percentage(for: debt))%",
                                trailing: debt.outstandingBalance.map { YSMoneyFormatter.string(for: $0) },
                                icon: "creditcard"
                            )
                        }
                        .buttonStyle(.plain)
                        if debt.id != debts.last?.id {
                            Divider().padding(.leading, YSSpacing.md + 28)
                        }
                    }
                }
            }
        }
    }

    private func lastRepaymentText(_ snapshot: DebtListSnapshot) -> String {
        guard let date = snapshot.lastRepaymentDate else { return "暂无" }
        let amount = snapshot.lastRepaymentAmount.map { YSMoneyFormatter.string(for: $0) } ?? ""
        return "\(date.formatted(date: .abbreviated, time: .omitted)) \(amount)".trimmingCharacters(in: .whitespaces)
    }
}
