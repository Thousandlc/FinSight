import SwiftUI
import YoushuDesignSystem
import YoushuDomain

public struct DataBackupView: View {
    @Bindable private var viewModel: DataBackupViewModel
    @State private var isPresentingBackupCreation = false
    @State private var isPresentingRestoreFlow = false

    public init(viewModel: DataBackupViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.md) {
                introSection
                actionsSection
                restoreFlowSection
            }
            .padding(.horizontal, YSSpacing.md)
            .padding(.bottom, YSSpacing.xxl)
        }
        .background(YSColor.Fallback.background)
        .navigationTitle("数据与备份")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isPresentingBackupCreation, onDismiss: {
            viewModel.cancelBackupCreation()
        }) {
            BackupCreationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: restoreFlowBinding) {
            BackupRestoreFlowView(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $viewModel.isPresentingRestoreImporter,
            allowedContentTypes: [FinSightBackupDocumentType.utType],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.handleRestoreImportResult(.success(url))
                    isPresentingRestoreFlow = true
                } else {
                    viewModel.handleRestoreImportResult(.failure(CocoaError(.fileReadUnknown)))
                }
            case .failure(let error):
                viewModel.handleRestoreImportResult(.failure(error))
            }
        }
    }

    private var restoreFlowBinding: Binding<Bool> {
        Binding(
            get: {
                isPresentingRestoreFlow || isRestoreFlowActive
            },
            set: { newValue in
                if !newValue {
                    viewModel.cancelRestoreFlow()
                    isPresentingRestoreFlow = false
                }
            }
        )
    }

    private var isRestoreFlowActive: Bool {
        switch viewModel.restoreEngine.phase {
        case .idle:
            false
        default:
            true
        }
    }

    private var introSection: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                Text("备份包含加密的财务信息，由你设置的密码保护。知数无法找回此密码。")
                    .font(YSTypography.body)
                    .foregroundStyle(YSColor.Fallback.textPrimary)
                Text("恢复备份会完整替换当前设备中的知数财务数据，不会合并。")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actionsSection: some View {
        YSListSection(title: "备份操作") {
            Button {
                isPresentingBackupCreation = true
                viewModel.presentBackupCreation()
            } label: {
                YSListRow(
                    title: "创建备份",
                    subtitle: "加密并导出到文件",
                    icon: "square.and.arrow.up"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("创建备份")
            .disabled(viewModel.isBackupCreationBusy || viewModel.restoreEngine.isBusy)

            Divider().padding(.leading, YSSpacing.md + 28)

            Button {
                viewModel.beginRestoreImport()
            } label: {
                YSListRow(
                    title: "从备份恢复",
                    subtitle: "选择备份文件并完整恢复",
                    icon: "square.and.arrow.down"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从备份恢复")
            .disabled(viewModel.isBackupCreationBusy || viewModel.restoreEngine.isBusy)
        }
    }

    @ViewBuilder
    private var restoreFlowSection: some View {
        if case let .failed(message, _) = viewModel.restoreEngine.phase {
            failureBanner(message)
        }
        if case .criticalFailure = viewModel.restoreEngine.phase {
            criticalFailureBanner
        }
    }

    private func failureBanner(_ message: String) -> some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                Text(message)
                    .font(YSTypography.body)
                    .foregroundStyle(YSColor.Fallback.expense)
                YSButton("知道了", kind: .secondary) {
                    viewModel.dismissRestoreOutcome()
                }
            }
        }
        .accessibilityLabel("恢复失败")
        .accessibilityHint(message)
    }

    private var criticalFailureBanner: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                Text("严重错误")
                    .font(YSTypography.headline)
                    .foregroundStyle(YSColor.Fallback.expense)
                Text(BackupUserFacingErrorMapper.criticalPersistenceMessage)
                    .font(YSTypography.body)
                    .foregroundStyle(YSColor.Fallback.textPrimary)
                YSButton("知道了", kind: .secondary) {
                    viewModel.dismissRestoreOutcome()
                }
            }
        }
        .accessibilityLabel("严重恢复错误")
    }
}
