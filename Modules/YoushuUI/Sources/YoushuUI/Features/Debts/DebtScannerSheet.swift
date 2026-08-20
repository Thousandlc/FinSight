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
import YoushuFoundation

/// AI 债务扫描：批量截图 → 预览 → 分析 → 候选确认（确认前不入库）。
public struct DebtScannerSheet: View {
    @Bindable var viewModel: DebtScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var editingCandidate: DebtCandidate?

    public init(viewModel: DebtScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .intro:
                    introStep
                case .pick:
                    pickStep
                case .preview:
                    previewStep
                case .scanning:
                    YSLoadingState(message: "正在分析账单并发现债务…")
                case .review:
                    reviewStep
                case .failed(let message):
                    failedStep(message)
                }
            }
            .background(YSColor.Fallback.background)
            .navigationTitle("债务扫描")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $editingCandidate) { candidate in
                DebtCandidateEditSheet(candidate: candidate) { updated in
                    viewModel.updateEditable(updated)
                    editingCandidate = nil
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPickerItems(items) }
        }
    }

    // MARK: - Steps

    private var introStep: some View {
        VStack(alignment: .leading, spacing: YSSpacing.lg) {
            YSCard {
                VStack(alignment: .leading, spacing: YSSpacing.sm) {
                    Text("搞清楚你到底欠多少钱")
                        .font(YSTypography.title3)
                    Text("批量上传 5–20 张账单截图，AI 会帮你发现信用卡、分期和贷款等债务。")
                        .font(YSTypography.body)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                    Text("AI 只生成候选结果，不会直接写入账本；你确认后才会创建债务。")
                        .font(YSTypography.body)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                    Text("上传的财务图片仅用于识别债务信息。不会默认永久保存原图。")
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                }
            }
            Spacer()
            YSButton("开始扫描我的债务") {
                viewModel.acceptIntro()
            }
        }
        .padding(YSSpacing.md)
    }

    private var pickStep: some View {
        VStack(spacing: YSSpacing.lg) {
            YSEmptyState(
                config: YSEmptyStateConfig(
                    icon: "doc.on.doc",
                    title: "批量选择账单截图",
                    message: "支持多张支付/账单截图。未来将支持 PDF 与各类账单文件。",
                    actionTitle: nil
                )
            )
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: DebtScannerService.recommendedMaxDocuments,
                matching: .images,
                photoLibrary: .shared()
            ) {
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
        ScrollView {
            VStack(alignment: .leading, spacing: YSSpacing.md) {
                Text("已选 \(viewModel.documents.count) 张")
                    .font(YSTypography.headline)
                Text("建议 \(DebtScannerService.recommendedMinDocuments)–\(DebtScannerService.recommendedMaxDocuments) 张，可继续添加。")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: YSSpacing.sm)], spacing: YSSpacing.sm) {
                    ForEach(viewModel.documents) { doc in
                        ZStack(alignment: .topTrailing) {
                            documentThumbnail(doc)
                            Button {
                                viewModel.removeDocument(id: doc.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .padding(4)
                        }
                    }
                }

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: DebtScannerService.recommendedMaxDocuments,
                    matching: .images
                ) {
                    Text("继续添加")
                        .font(YSTypography.callout)
                        .foregroundStyle(YSColor.Fallback.brandPrimary)
                }

                YSButton("开始 AI 分析") {
                    Task { await viewModel.startScan() }
                }
                YSButton("重新选择", kind: .secondary) {
                    pickerItems = []
                    viewModel.retryFromPick()
                }
            }
            .padding(YSSpacing.md)
        }
    }

    private var reviewStep: some View {
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

                Text("发现 \(viewModel.reviewItems.count) 笔候选债务")
                    .font(YSTypography.headline)
                Text("请逐笔确认。AI 结果不会自动入库。")
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)

                ForEach(viewModel.reviewItems) { item in
                    candidateCard(item)
                }

                if let error = viewModel.formError {
                    Text(error)
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.warning)
                }

                YSButton(
                    viewModel.isSaving ? "创建中…" : "全部确认（\(viewModel.confirmableItems.count)）",
                    isLoading: viewModel.isSaving
                ) {
                    Task {
                        let ok = await viewModel.confirmAll()
                        if ok { dismiss() }
                    }
                }
                .disabled(viewModel.confirmableItems.isEmpty)
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

    // MARK: - Candidate card

    private func candidateCard(_ item: ReviewableDebtCandidate) -> some View {
        let draft = item.editable
        return YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: YSSpacing.xxs) {
                        Text(draft.lender ?? "未知债权方")
                            .font(YSTypography.headline)
                        Text(draft.productName ?? draft.debtType?.displayName ?? "债务")
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
                    Spacer()
                    if item.isIgnored {
                        YSBadge("已忽略", tone: .neutral)
                    } else {
                        YSBadge("待确认", tone: .brand)
                    }
                }

                detailLine("当前欠款", moneyText(draft.outstandingBalance, currency: draft.currencyCode))
                detailLine("本期应还", moneyText(draft.currentDue, currency: draft.currencyCode))
                detailLine("还款日", draft.dueDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "未知")
                detailLine("信息完整度", "\(draft.profileCompletenessPercent)%")
                detailLine("AI 置信度", draft.confidence.map { "\(Int($0 * 100))%" } ?? "—")

                if !item.isIgnored {
                    HStack(spacing: YSSpacing.sm) {
                        Button("编辑") { editingCandidate = draft }
                        Button("忽略") { viewModel.ignoreItem(id: item.id) }
                        Spacer()
                        Button("确认") {
                            Task {
                                let ok = await viewModel.confirmSingle(id: item.id)
                                if ok, viewModel.confirmableItems.isEmpty {
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                    }
                    .font(YSTypography.callout)
                    .foregroundStyle(YSColor.Fallback.brandPrimary)
                } else {
                    Button("恢复") { viewModel.restoreItem(id: item.id) }
                        .font(YSTypography.callout)
                        .foregroundStyle(YSColor.Fallback.brandPrimary)
                }
            }
            .opacity(item.isIgnored ? 0.55 : 1)
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            Spacer()
            Text(value)
                .font(YSTypography.callout)
        }
    }

    private func moneyText(_ amount: Decimal?, currency: String?) -> String {
        guard let amount else { return "未知" }
        let money = Money(amount: amount, currencyCode: currency ?? "CNY")
        return YSMoneyFormatter.string(for: money)
    }

    private func documentThumbnail(_ doc: BillDocument) -> some View {
        Group {
            if let image = makeImage(from: doc.data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                    .overlay {
                        Image(systemName: "doc")
                            .foregroundStyle(YSColor.Fallback.textSecondary)
                    }
            }
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous))
    }

    private func loadPickerItems(_ items: [PhotosPickerItem]) async {
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                datas.append(data)
            }
        }
        pickerItems = []
        if viewModel.documents.isEmpty {
            viewModel.setImageDatas(datas)
        } else {
            for data in datas {
                viewModel.appendImageData(data)
            }
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

struct DebtCandidateEditSheet: View {
    @State private var draft: DebtCandidate
    @Environment(\.dismiss) private var dismiss
    let onSave: (DebtCandidate) -> Void

    init(candidate: DebtCandidate, onSave: @escaping (DebtCandidate) -> Void) {
        _draft = State(initialValue: candidate)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础") {
                    TextField("债权方", text: stringBinding(\.lender))
                    TextField("产品名称", text: stringBinding(\.productName))
                    Picker("类型", selection: Binding(
                        get: { draft.debtType ?? .other },
                        set: { draft.debtType = $0 }
                    )) {
                        ForEach(DebtType.mvpCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                Section("金额（请勿混淆）") {
                    TextField("剩余总欠款", text: decimalBinding(\.outstandingBalance))
                        .keyboardType(.decimalPad)
                    TextField("本期应还", text: decimalBinding(\.currentDue))
                        .keyboardType(.decimalPad)
                    TextField("最低还款", text: decimalBinding(\.minimumDue))
                        .keyboardType(.decimalPad)
                    TextField("每期金额", text: decimalBinding(\.installmentAmount))
                        .keyboardType(.decimalPad)
                }
                Section("其他") {
                    DatePicker(
                        "还款日",
                        selection: Binding(
                            get: { draft.dueDate ?? Date() },
                            set: { draft.dueDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    TextField("剩余期数", text: intBinding(\.remainingInstallments))
                        .keyboardType(.numberPad)
                    TextField("利率（可留空=未知）", text: decimalBinding(\.interestRate))
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("编辑候选债务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func stringBinding(_ keyPath: WritableKeyPath<DebtCandidate, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func decimalBinding(_ keyPath: WritableKeyPath<DebtCandidate, Decimal?>) -> Binding<String> {
        Binding(
            get: {
                guard let value = draft[keyPath: keyPath] else { return "" }
                return "\(value)"
            },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty
                    ? nil
                    : Decimal(string: trimmed.replacingOccurrences(of: ",", with: ""))
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<DebtCandidate, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard let value = draft[keyPath: keyPath] else { return "" }
                return "\(value)"
            },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : Int(trimmed)
            }
        )
    }
}
