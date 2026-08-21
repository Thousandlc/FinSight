import SwiftUI
import YoushuDesignSystem

public struct PrivacyAISettingsView: View {
    @Bindable private var viewModel: PrivacyAISettingsViewModel

    public init(viewModel: PrivacyAISettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                YSLoadingState()
            case .error(let message):
                YSErrorState(message: message) {
                    Task { await viewModel.load() }
                }
            case .ready:
                settingsContent
            }
        }
        .background(YSColor.Fallback.background)
        .navigationTitle("隐私与 AI")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("privacy-ai-settings")
        .confirmationDialog(
            PrivacyAIDisclosureCopy.wipeConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(PrivacyAIDisclosureCopy.wipeConfirmButtonTitle, role: .destructive) {
                Task { await viewModel.confirmDeleteAllLocalData() }
            }
            .accessibilityIdentifier("privacy-ai-wipe-confirm")
            Button("取消", role: .cancel) {
                viewModel.cancelDeleteAllLocalData()
            }
            .accessibilityIdentifier("privacy-ai-wipe-cancel")
        } message: {
            Text(PrivacyAIDisclosureCopy.wipeConfirmationMessage)
        }
        .task { await viewModel.load() }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.md) {
                YSListSection(title: "AI 数据授权") {
                    settingRow(
                        title: PrivacyAIDisclosureCopy.screenshotSettingTitle,
                        subtitle: PrivacyAIDisclosureCopy.screenshotSettingSubtitle,
                        field: .screenshot,
                        isOn: viewModel.allowScreenshotImageToAI
                    )
                    Divider().padding(.leading, YSSpacing.md)
                    settingRow(
                        title: PrivacyAIDisclosureCopy.debtScanSettingTitle,
                        subtitle: PrivacyAIDisclosureCopy.debtScanSettingSubtitle,
                        field: .debtScan,
                        isOn: viewModel.allowDebtScanImageToAI
                    )
                    Divider().padding(.leading, YSSpacing.md)
                    settingRow(
                        title: PrivacyAIDisclosureCopy.financialContextSettingTitle,
                        subtitle: PrivacyAIDisclosureCopy.financialContextSettingSubtitle,
                        field: .financialContext,
                        isOn: viewModel.allowFinancialContextToAI
                    )
                }

                YSListSection(title: "本地数据") {
                    settingRow(
                        title: PrivacyAIDisclosureCopy.retentionSettingTitle,
                        subtitle: PrivacyAIDisclosureCopy.retentionSettingSubtitle,
                        field: .retainOriginalImages,
                        isOn: viewModel.retainOriginalImages
                    )
                }

                if let warning = viewModel.retentionCleanupWarning {
                    cleanupWarning(warning)
                }

                YSListSection(title: "数据管理") {
                    Button {
                        viewModel.requestDeleteAllLocalData()
                    } label: {
                        VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                            HStack {
                                Text(PrivacyAIDisclosureCopy.wipeActionTitle)
                                    .font(YSTypography.body.weight(.medium))
                                    .foregroundStyle(YSColor.Fallback.expense)
                                Spacer()
                                if viewModel.isWipeBusy {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            Text(PrivacyAIDisclosureCopy.wipeActionSubtitle)
                                .font(YSTypography.caption)
                                .foregroundStyle(YSColor.Fallback.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, YSSpacing.sm)
                        .padding(.horizontal, YSSpacing.md)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBusy)
                    .accessibilityLabel(PrivacyAIDisclosureCopy.wipeActionTitle)
                    .accessibilityIdentifier("privacy-ai-wipe-button")
                }

                if let warning = viewModel.wipeFailureMessage {
                    wipeStatus(warning, retryWipe: viewModel.showsWipeMediaCleanupRetry)
                }

                if let message = viewModel.wipeStatusMessage {
                    Text(message)
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                        .padding(.horizontal, YSSpacing.xxs)
                        .accessibilityIdentifier("privacy-ai-wipe-success")
                }

                if let error = viewModel.actionError {
                    Text(error)
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.expense)
                        .padding(.horizontal, YSSpacing.xxs)
                        .accessibilityIdentifier("privacy-ai-action-error")
                }
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
    }

    private func settingRow(
        title: String,
        subtitle: String,
        field: PrivacyAISettingField,
        isOn: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: YSSpacing.sm) {
            VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                Text(title)
                    .font(YSTypography.body.weight(.medium))
                    .foregroundStyle(YSColor.Fallback.textPrimary)
                Text(subtitle)
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
            Spacer(minLength: YSSpacing.sm)
            Toggle("", isOn: binding(for: field, current: isOn))
                .labelsHidden()
                .disabled(viewModel.isBusy)
                .accessibilityLabel(title)
                .accessibilityIdentifier(accessibilityIdentifier(for: field))
        }
        .padding(.vertical, YSSpacing.sm)
        .padding(.horizontal, YSSpacing.md)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirming = viewModel.wipePhase { return true }
                return false
            },
            set: { presented in
                if !presented {
                    viewModel.cancelDeleteAllLocalData()
                }
            }
        )
    }

    private func wipeStatus(_ message: String, retryWipe: Bool) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.sm) {
            Text(message)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.expense)
                .accessibilityIdentifier("privacy-ai-wipe-error")
            if retryWipe {
                YSButton(
                    "重试清除原图",
                    kind: .secondary,
                    isLoading: viewModel.isWipeBusy
                ) {
                    Task { await viewModel.retryWipeMediaCleanup() }
                }
                .accessibilityIdentifier("privacy-ai-wipe-media-retry")
            }
        }
        .padding(.horizontal, YSSpacing.xxs)
    }

    private func cleanupWarning(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.sm) {
            Text(message)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.expense)
                .accessibilityIdentifier("privacy-ai-retention-cleanup-warning")
            if viewModel.showsRetentionCleanupRetry {
                YSButton(
                    "重试清除原图",
                    kind: .secondary,
                    isLoading: viewModel.mutatingField == .retainOriginalImages
                ) {
                    Task { await viewModel.retryRetentionCleanup() }
                }
                .accessibilityIdentifier("privacy-ai-retention-cleanup-retry")
            }
        }
        .padding(.horizontal, YSSpacing.xxs)
    }

    private func binding(for field: PrivacyAISettingField, current: Bool) -> Binding<Bool> {
        Binding(
            get: { current },
            set: { newValue in
                Task { await apply(field, enabled: newValue) }
            }
        )
    }

    private func apply(_ field: PrivacyAISettingField, enabled: Bool) async {
        switch field {
        case .screenshot:
            await viewModel.setScreenshotAIEnabled(enabled)
        case .debtScan:
            await viewModel.setDebtScanAIEnabled(enabled)
        case .financialContext:
            await viewModel.setFinancialContextAIEnabled(enabled)
        case .retainOriginalImages:
            await viewModel.setRetainOriginalImagesEnabled(enabled)
        }
    }

    private func accessibilityIdentifier(for field: PrivacyAISettingField) -> String {
        switch field {
        case .screenshot: "privacy-ai-screenshot-toggle"
        case .debtScan: "privacy-ai-debt-scan-toggle"
        case .financialContext: "privacy-ai-financial-context-toggle"
        case .retainOriginalImages: "privacy-ai-retain-originals-toggle"
        }
    }
}
