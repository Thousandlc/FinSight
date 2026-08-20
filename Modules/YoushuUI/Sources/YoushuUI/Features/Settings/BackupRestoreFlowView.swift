import SwiftUI
import YoushuDesignSystem
import YoushuDomain

struct BackupRestoreFlowView: View {
    @Bindable var viewModel: DataBackupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDestructiveConfirmation = false

    var body: some View {
        NavigationStack {
            content
                .background(YSColor.Fallback.background)
                .navigationTitle("恢复备份")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            viewModel.cancelRestoreFlow()
                            dismiss()
                        }
                        .disabled(viewModel.restoreEngine.isBusy)
                    }
                }
                .confirmationDialog(
                    "确认恢复备份？",
                    isPresented: $showsDestructiveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("恢复并替换当前数据", role: .destructive) {
                        Task { await confirmRestore() }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(destructiveConfirmationMessage)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.restoreEngine.phase {
        case .idle, .importing:
            progressState(message: "正在读取备份文件…")
        case .awaitingPassphrase:
            passphraseStep
        case .preflighting:
            progressState(message: "正在验证备份…")
        case let .preview(preview):
            previewStep(preview)
        case let .confirmingDestructiveRestore(preview):
            previewStep(preview, awaitingFinalConfirmation: true)
        case .restoring:
            progressState(message: "正在恢复数据…")
        case .refreshingApplication:
            progressState(message: "正在刷新应用数据…")
        case let .success(result):
            successStep(result)
        case let .failed(message, _):
            outcomeStep(title: "无法恢复", message: message, isCritical: false)
        case .criticalFailure:
            outcomeStep(
                title: "严重错误",
                message: BackupUserFacingErrorMapper.criticalPersistenceMessage,
                isCritical: true
            )
        }
    }

    private var passphraseStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.md) {
                Text("输入创建此备份时设置的密码。")
                    .font(YSTypography.body)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                YSSecureInput(
                    title: "备份密码",
                    text: Binding(
                        get: { viewModel.restorePassphrase },
                        set: { viewModel.updateRestorePassphrase($0) }
                    ),
                    placeholder: "输入密码"
                )
                YSButton("继续", isLoading: viewModel.restoreEngine.isBusy) {
                    Task { await viewModel.submitRestorePassphrase() }
                }
                .disabled(viewModel.restoreEngine.isBusy)
                .accessibilityLabel("验证备份密码")
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.vertical, YSSpacing.lg)
        }
    }

    private func previewStep(_ preview: BackupRestorePreview, awaitingFinalConfirmation: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.md) {
                Text("备份预览")
                    .font(YSTypography.headline)
                previewCard(preview)
                warningCard
                if awaitingFinalConfirmation {
                    YSButton("确认恢复", kind: .secondary) {
                        showsDestructiveConfirmation = true
                    }
                    .accessibilityLabel("确认恢复备份")
                } else {
                    YSButton("继续") {
                        viewModel.restoreEngine.proceedToDestructiveConfirmation()
                    }
                    .accessibilityLabel("继续恢复流程")
                }
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.vertical, YSSpacing.lg)
        }
    }

    private func previewCard(_ preview: BackupRestorePreview) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                previewRow("备份时间", value: formattedDate(preview.createdAt))
                if let version = preview.sourceAppVersion {
                    previewRow("来源版本", value: version)
                }
                previewRow("账户", value: "\(preview.counts.accounts)")
                previewRow("交易", value: "\(preview.counts.transactions)")
                previewRow("债务", value: "\(preview.counts.debts)")
                previewRow("还款计划", value: "\(preview.counts.repaymentPlans)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("备份预览")
    }

    private var warningCard: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.xs) {
                Text("恢复会替换当前设备中的知数财务数据。当前设备中不在备份里的数据将被移除。")
                    .font(YSTypography.body)
                Text("AI 授权不会从备份恢复。历史 AI 洞察不会从备份恢复。")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
        }
    }

    private func successStep(_ result: BackupRestoreResult) -> some View {
        VStack(spacing: YSSpacing.md) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(YSColor.Fallback.positive)
                .accessibilityHidden(true)
            Text("恢复成功")
                .font(YSTypography.title3.weight(.semibold))
            if viewModel.restoreIdentityChanged {
                Text("当前账户身份已切换为备份中的用户。")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Text("已恢复 \(result.counts.transactions) 笔交易、\(result.counts.accounts) 个账户。")
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            YSButton("完成") {
                viewModel.dismissRestoreOutcome()
                dismiss()
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.lg)
        }
        .padding(.horizontal, YSSpacing.md)
        .accessibilityLabel("恢复成功")
    }

    private func outcomeStep(title: String, message: String, isCritical: Bool) -> some View {
        VStack(spacing: YSSpacing.md) {
            Spacer()
            Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(YSColor.Fallback.expense)
                .accessibilityHidden(true)
            Text(title)
                .font(YSTypography.title3.weight(.semibold))
            Text(message)
                .font(YSTypography.body)
                .foregroundStyle(YSColor.Fallback.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            YSButton("关闭") {
                viewModel.dismissRestoreOutcome()
                dismiss()
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.lg)
        }
        .padding(.horizontal, YSSpacing.md)
    }

    private func progressState(message: String) -> some View {
        VStack(spacing: YSSpacing.md) {
            Spacer()
            ProgressView()
                .accessibilityLabel(message)
            Text(message)
                .font(YSTypography.body)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(YSTypography.body)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            Spacer()
            Text(value)
                .font(YSTypography.body.weight(.medium))
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var destructiveConfirmationMessage: String {
        "恢复会替换当前设备中的知数财务数据。当前设备中不在备份里的数据将被移除。AI 授权与历史 AI 洞察不会恢复。"
    }

    private func confirmRestore() async {
        await viewModel.confirmRestore()
    }
}
