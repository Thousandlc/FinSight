import SwiftUI
import YoushuDesignSystem
import YoushuDomain

struct TransactionFormSheet: View {
    @Bindable var viewModel: TransactionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TransactionFormDraft
    @State private var formType: TransactionFormType

    init(viewModel: TransactionViewModel) {
        self.viewModel = viewModel
        let defaultAccount = viewModel.accounts.first?.id ?? UUID()
        if let editing = viewModel.editingItem {
            _draft = State(initialValue: TransactionFormDraft.from(item: editing, accounts: viewModel.accounts))
            _formType = State(initialValue: TransactionFormDraft.from(item: editing, accounts: viewModel.accounts).formType)
        } else {
            let initial = TransactionFormDraft(accountId: defaultAccount)
            _draft = State(initialValue: initial)
            _formType = State(initialValue: .expense)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $formType) {
                        ForEach(TransactionFormType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, YSSpacing.xs)
                    .onChange(of: formType) { _, newValue in
                        draft.formType = newValue
                        if !TransactionCategory.categories(for: newValue.transactionType).contains(draft.category) {
                            draft.category = TransactionCategory.categories(for: newValue.transactionType).first ?? "其他"
                        }
                    }
                }

                Section("金额与日期") {
                    TextField("金额", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("日期", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                }

                Section("详情") {
                    if formType != .transfer {
                        TextField("商户（可选）", text: $draft.merchant)
                    }
                    Picker("分类", selection: $draft.category) {
                        ForEach(TransactionCategory.categories(for: formType.transactionType), id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    Picker("账户", selection: $draft.accountId) {
                        ForEach(viewModel.accounts, id: \.id) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    if formType == .transfer {
                        Picker("转入账户", selection: transferDestinationBinding) {
                            ForEach(viewModel.accounts.filter { $0.id != draft.accountId }, id: \.id) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                    }
                    TextField("备注（可选）", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = viewModel.formError {
                    Section {
                        Text(error)
                            .foregroundStyle(YSColor.Fallback.warning)
                            .font(YSTypography.caption)
                    }
                }
            }
            .navigationTitle(viewModel.editingItem == nil ? "记一笔" : "编辑交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSaving ? "保存中…" : "保存") {
                        Task {
                            let ok = await viewModel.saveForm(draft)
                            if ok { dismiss() }
                        }
                    }
                    .disabled(viewModel.isSaving || !isValid)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var transferDestinationBinding: Binding<UUID> {
        Binding(
            get: { draft.toAccountId ?? viewModel.accounts.first(where: { $0.id != draft.accountId })?.id ?? draft.accountId },
            set: { draft.toAccountId = $0 }
        )
    }

    private var isValid: Bool {
        guard draft.amountDecimal > 0 else { return false }
        if formType == .transfer {
            return draft.toAccountId != nil && draft.toAccountId != draft.accountId
        }
        return true
    }
}
