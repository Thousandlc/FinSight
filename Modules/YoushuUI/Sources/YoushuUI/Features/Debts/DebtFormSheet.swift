import SwiftUI
import YoushuDesignSystem
import YoushuDomain

struct DebtFormSheet: View {
    @Bindable var viewModel: DebtViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DebtFormDraft

    init(viewModel: DebtViewModel) {
        self.viewModel = viewModel
        if let editing = viewModel.editingDebt {
            _draft = State(initialValue: .from(editing))
        } else {
            _draft = State(initialValue: DebtFormDraft())
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("只需填写债权方和大致欠款即可创建，其他信息可稍后补充。")
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                }

                Section("必填") {
                    TextField("债权方", text: $draft.lender)
                    TextField("大致欠款", text: $draft.balanceText)
                        .keyboardType(.decimalPad)
                }

                Section("可选基础信息") {
                    TextField("产品名称", text: $draft.productName)
                    Picker("债务类型", selection: $draft.debtType) {
                        ForEach(DebtType.mvpCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Picker("状态", selection: $draft.status) {
                        Text(DebtStatus.active.displayName).tag(DebtStatus.active)
                        Text(DebtStatus.overdue.displayName).tag(DebtStatus.overdue)
                        Text(DebtStatus.paidOff.displayName).tag(DebtStatus.paidOff)
                    }
                }

                Section("可选还款信息") {
                    TextField("本期应还", text: $draft.currentDueText)
                        .keyboardType(.decimalPad)
                    TextField("最低还款", text: $draft.minimumDueText)
                        .keyboardType(.decimalPad)
                    TextField("每期还款", text: $draft.installmentText)
                        .keyboardType(.decimalPad)
                    Picker("还款频率", selection: $draft.paymentFrequency) {
                        ForEach(PaymentFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    Toggle("设置还款日", isOn: $draft.includeDueDate)
                    if draft.includeDueDate {
                        DatePicker(
                            "还款日",
                            selection: Binding(
                                get: { draft.dueDate ?? Date() },
                                set: { draft.dueDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                    TextField("剩余期数", text: $draft.remainingInstallmentsText)
                        .keyboardType(.numberPad)
                    Toggle("设置到期日", isOn: $draft.includeMaturityDate)
                    if draft.includeMaturityDate {
                        DatePicker(
                            "到期日",
                            selection: Binding(
                                get: { draft.maturityDate ?? Date() },
                                set: { draft.maturityDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }

                Section("可选成本信息") {
                    TextField("年化利率（如 0.18）", text: $draft.interestRateText)
                        .keyboardType(.decimalPad)
                    TextField("手续费", text: $draft.feeText)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $draft.note, axis: .vertical)
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
            .navigationTitle(viewModel.editingDebt == nil ? "添加债务" : "编辑债务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSaving ? "保存中…" : "保存") {
                        Task {
                            var toSave = draft
                            if !toSave.includeDueDate { toSave.dueDate = nil }
                            if !toSave.includeMaturityDate { toSave.maturityDate = nil }
                            let ok = await viewModel.saveForm(toSave)
                            if ok { dismiss() }
                        }
                    }
                    .disabled(viewModel.isSaving || !isValid)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var isValid: Bool {
        !draft.lender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.balanceDecimal >= 0
            && !draft.balanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DebtRepaymentSheet: View {
    @Bindable var viewModel: DebtViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DebtRepaymentDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section("还款") {
                    TextField("金额", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("日期", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                    Picker("付款账户（可选）", selection: Binding(
                        get: { draft.accountId },
                        set: { draft.accountId = $0 }
                    )) {
                        Text("不关联账户").tag(Optional<UUID>.none)
                        ForEach(viewModel.accounts, id: \.id) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    TextField("备注", text: $draft.note)
                }
                if let error = viewModel.formError {
                    Section {
                        Text(error)
                            .foregroundStyle(YSColor.Fallback.warning)
                            .font(YSTypography.caption)
                    }
                }
            }
            .navigationTitle("记录还款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSaving ? "保存中…" : "确认") {
                        Task {
                            let ok = await viewModel.saveRepayment(draft)
                            if ok { dismiss() }
                        }
                    }
                    .disabled(viewModel.isSaving || draft.amountDecimal <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if draft.accountId == nil {
                draft.accountId = viewModel.accounts.first?.id
            }
        }
    }
}
