import SwiftUI
import YoushuDesignSystem
import YoushuDomain

struct AccountFormSheet: View {
    @Bindable var viewModel: AccountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AccountFormDraft

    init(viewModel: AccountViewModel) {
        self.viewModel = viewModel
        if let editing = viewModel.editingSummary {
            _draft = State(initialValue: AccountFormDraft.from(summary: editing))
        } else {
            _draft = State(initialValue: AccountFormDraft())
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $draft.name)
                    Picker("类型", selection: $draft.type) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Picker("币种", selection: $draft.currencyCode) {
                        Text("CNY ¥").tag("CNY")
                    }
                }

                Section("期初余额") {
                    TextField("期初余额", text: $draft.openingBalanceText)
                        .keyboardType(.decimalPad)
                    if draft.type == .creditCard {
                        Text("信用卡账户用于记录刷卡与还款现金流；欠款请查看关联债务。")
                            .font(YSTypography.caption2)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
                }

                Section("备注") {
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
            .navigationTitle(viewModel.editingSummary == nil ? "添加账户" : "编辑账户")
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
                    .disabled(viewModel.isSaving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
