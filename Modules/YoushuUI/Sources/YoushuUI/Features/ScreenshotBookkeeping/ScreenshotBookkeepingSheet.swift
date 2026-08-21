import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import YoushuDesignSystem
import YoushuDomain

/// 截图 AI 记账流程：隐私 → 选图 → 预览 → 识别 → 确认（AI 结果 / 最终数据分离）。
public struct ScreenshotBookkeepingSheet: View {
    @Bindable var viewModel: ScreenshotBookkeepingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?

    public init(viewModel: ScreenshotBookkeepingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .privacy:
                    privacyStep
                case .pick:
                    pickStep
                case .preview:
                    previewStep
                case .recognizing:
                    YSLoadingState(message: "正在识别交易信息…")
                case .confirm:
                    confirmStep
                case .failed(let message):
                    failedStep(message)
                }
            }
            .background(YSColor.Fallback.background)
            .navigationTitle("截图记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadAccounts() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await loadPickerItem(item)
            }
        }
    }

    // MARK: - Steps

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: YSSpacing.lg) {
            YSCard {
                VStack(alignment: .leading, spacing: YSSpacing.sm) {
                    Text(PrivacyAIDisclosureCopy.screenshotConsentTitle)
                        .font(YSTypography.title3)
                    ForEach(PrivacyAIDisclosureCopy.screenshotConsentLines, id: \.self) { line in
                        Text(line)
                            .font(YSTypography.body)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
                }
            }
            Spacer()
            YSButton("我已了解，继续") {
                viewModel.acceptPrivacy()
            }
        }
        .padding(YSSpacing.md)
    }

    private var pickStep: some View {
        VStack(spacing: YSSpacing.lg) {
            YSEmptyState(
                config: YSEmptyStateConfig(
                    icon: "photo.on.rectangle.angled",
                    title: "选择支付截图",
                    message: "本阶段支持单张图片。请选择清晰的支付成功页或账单截图。",
                    actionTitle: nil
                )
            )
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Text("从相册选择")
                    .font(YSTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, YSSpacing.sm)
                    .background(YSColor.Fallback.brandPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous))
            }
            .padding(.horizontal, YSSpacing.md)
            Spacer()
        }
        .padding(.top, YSSpacing.xl)
    }

    private var previewStep: some View {
        VStack(spacing: YSSpacing.lg) {
            if let data = viewModel.imageData, let image = makeImage(from: data) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: YSRadius.md, style: .continuous))
                    .padding(.horizontal, YSSpacing.md)
            } else if viewModel.imageData != nil {
                Text("图片预览不可用，仍可继续识别。")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
            Text("确认使用这张截图进行识别？")
                .font(YSTypography.body)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            YSButton("开始识别") {
                Task { await viewModel.startRecognition() }
            }
            YSButton("重新选择", kind: .secondary) {
                pickerItem = nil
                viewModel.retryFromPick()
            }
            Spacer()
        }
        .padding(YSSpacing.md)
    }

    private var confirmStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.lg) {
                if !viewModel.warnings.isEmpty {
                    YSCard {
                        VStack(alignment: .leading, spacing: YSSpacing.xs) {
                            Text("识别提示")
                                .font(YSTypography.headline)
                            ForEach(viewModel.warnings, id: \.self) { warning in
                                Text("• \(warning)")
                                    .font(YSTypography.caption)
                                    .foregroundStyle(YSColor.Fallback.warning)
                            }
                        }
                    }
                }

                YSCard {
                    VStack(alignment: .leading, spacing: YSSpacing.sm) {
                        Text("AI 识别结果")
                            .font(YSTypography.headline)
                        Text("只读，供对照。不会直接保存。")
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                        if let ai = viewModel.aiDraft {
                            aiReadonlyRows(ai)
                        }
                    }
                }

                YSCard {
                    VStack(alignment: .leading, spacing: YSSpacing.md) {
                        Text("最终保存的数据")
                            .font(YSTypography.headline)
                        Text("可修改后再确认。确认后才会创建交易。")
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)

                        Picker("类型", selection: $viewModel.formType) {
                            Text(TransactionFormType.expense.title).tag(TransactionFormType.expense)
                            Text(TransactionFormType.income.title).tag(TransactionFormType.income)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.formType) { _, newValue in
                            let cats = TransactionCategory.categories(for: newValue.transactionType)
                            if !cats.contains(viewModel.category) {
                                viewModel.category = cats.first ?? "其他"
                            }
                        }

                        labeledField("金额", text: $viewModel.amountText)
                        DatePicker("时间", selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])
                        labeledField("商户", text: $viewModel.merchant)

                        Picker("分类", selection: $viewModel.category) {
                            ForEach(TransactionCategory.categories(for: viewModel.formType.transactionType), id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        Picker("账户", selection: $viewModel.accountId) {
                            ForEach(viewModel.accounts, id: \.id) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        labeledField("备注", text: $viewModel.note)
                    }
                }

                if let error = viewModel.formError {
                    Text(error)
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.warning)
                }

                YSButton(viewModel.isSaving ? "保存中…" : "确认记账", isLoading: viewModel.isSaving) {
                    Task {
                        let ok = await viewModel.confirmSave()
                        if ok { dismiss() }
                    }
                }
            }
            .padding(YSSpacing.md)
        }
    }

    private func failedStep(_ message: String) -> some View {
        VStack(spacing: YSSpacing.lg) {
            YSErrorState(message: message) {
                viewModel.retryFromPick()
            }
            Spacer()
        }
        .padding(YSSpacing.md)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func aiReadonlyRows(_ draft: TransactionDraft) -> some View {
        readonlyRow("金额", value: draft.amount.map { "\($0)" } ?? "未识别")
        readonlyRow("类型", value: typeLabel(draft.transactionType))
        readonlyRow("商户", value: draft.merchant ?? "未识别")
        readonlyRow("时间", value: draft.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未识别")
        readonlyRow("分类", value: draft.category ?? "未识别")
        readonlyRow("账户推测", value: draft.suggestedAccountName ?? "未识别")
        readonlyRow("置信度", value: draft.confidence.map { "\(Int($0 * 100))%" } ?? "—")
    }

    private func readonlyRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(YSColor.Fallback.textPrimary)
        }
        .font(YSTypography.callout)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xxs) {
            Text(title)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            TextField(title, text: text)
                .padding(YSSpacing.sm)
                .background(YSColor.Fallback.surface)
                .clipShape(RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous))
        }
    }

    private func typeLabel(_ type: TransactionType?) -> String {
        switch type {
        case .expense: "支出"
        case .income: "收入"
        case .none: "未识别"
        default: type?.rawValue ?? "未识别"
        }
    }

    private func loadPickerItem(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                viewModel.setImageData(data)
            } else {
                viewModel.step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            }
        } catch {
            viewModel.step = .failed(AIRecognitionError.imageUnreadable.userMessage)
        }
    }

    private func makeImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            return Image(uiImage: ui)
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) {
            return Image(nsImage: ns)
        }
        #endif
        return nil
    }
}
