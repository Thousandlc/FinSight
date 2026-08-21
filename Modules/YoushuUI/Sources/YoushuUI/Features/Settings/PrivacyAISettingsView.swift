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
        .task { await viewModel.load() }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.md) {
                YSListSection(title: "AI 数据授权") {
                    settingRow(
                        title: "交易截图 AI 识别",
                        subtitle: "允许将记账截图发送给 AI 识别。关闭后不影响已记账交易。",
                        field: .screenshot,
                        isOn: viewModel.allowScreenshotImageToAI
                    )
                    Divider().padding(.leading, YSSpacing.md)
                    settingRow(
                        title: "债务图片 AI 扫描",
                        subtitle: "允许将债务账单图片发送给 AI 扫描。关闭后不影响已确认债务。",
                        field: .debtScan,
                        isOn: viewModel.allowDebtScanImageToAI
                    )
                    Divider().padding(.leading, YSSpacing.md)
                    settingRow(
                        title: "财务上下文 AI",
                        subtitle: "允许 AI 使用聚合财务信息回答问题。关闭后首页使用确定性摘要，历史洞察仍保留。",
                        field: .financialContext,
                        isOn: viewModel.allowFinancialContextToAI
                    )
                }

                YSListSection(title: "本地数据") {
                    settingRow(
                        title: "保留原始图片",
                        subtitle: "将截图和债务扫描原图保存在本机。关闭后将删除已保留原图。这不等于授权 AI 处理图片。",
                        field: .retainOriginalImages,
                        isOn: viewModel.retainOriginalImages
                    )
                }

                if let warning = viewModel.retentionCleanupWarning {
                    cleanupWarning(warning)
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
