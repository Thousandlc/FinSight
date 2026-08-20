import SwiftUI
import YoushuDesignSystem

struct BackupCreationSheet: View {
    @Bindable var viewModel: DataBackupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: YSSpacing.md) {
                    warningSection
                    passphraseSection
                    if let validationError = viewModel.creationValidationError {
                        Text(validationError)
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.expense)
                            .accessibilityLabel("验证错误")
                            .accessibilityValue(validationError)
                    }
                    if case let .failed(message) = viewModel.creationPhase {
                        Text(message)
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.expense)
                    }
                    YSButton(
                        "创建并导出",
                        isLoading: viewModel.isBackupCreationBusy
                    ) {
                        Task { await viewModel.createBackup() }
                    }
                    .disabled(viewModel.isBackupCreationBusy)
                    .accessibilityLabel("创建并导出备份")
                }
                .padding(.horizontal, YSSpacing.md)
                .padding(.vertical, YSSpacing.lg)
            }
            .background(YSColor.Fallback.background)
            .navigationTitle("创建备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelBackupCreation()
                        dismiss()
                    }
                }
            }
            .fileExporter(
                isPresented: $viewModel.isPresentingBackupExporter,
                document: viewModel.exportDocument ?? FinSightBackupExportDocument(encryptedData: Data()),
                contentType: FinSightBackupDocumentType.utType,
                defaultFilename: viewModel.exportFilename
            ) { result in
                switch result {
                case .success:
                    viewModel.backupExportCompleted(success: true)
                    dismiss()
                case .failure(let error):
                    if (error as? CocoaError)?.code == .userCancelled {
                        viewModel.backupExportCompleted(success: false)
                    } else {
                        viewModel.creationPhase = .failed(message: "导出失败，请稍后重试。")
                        viewModel.isPresentingBackupExporter = false
                    }
                }
            }
        }
    }

    private var warningSection: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.xs) {
                Text("请保存好备份密码。")
                    .font(YSTypography.body.weight(.medium))
                Text("知数无法找回此密码；密码丢失后，备份文件将无法恢复。")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
        }
    }

    private var passphraseSection: some View {
        VStack(spacing: YSSpacing.md) {
            YSSecureInput(
                title: "备份密码",
                text: $viewModel.creationPassphrase,
                placeholder: "输入密码"
            )
            YSSecureInput(
                title: "确认密码",
                text: $viewModel.creationPassphraseConfirmation,
                placeholder: "再次输入密码"
            )
        }
    }
}
