import Foundation
import YoushuDesignSystem
import YoushuDomain

@Observable
@MainActor
public final class ScreenshotBookkeepingViewModel {
    public enum Step: Equatable {
        case privacy
        case pick
        case preview
        case recognizing
        case confirm
        case failed(String)
    }

    public var step: Step = .privacy
    public var privacyAccepted = false
    public var imageData: Data?
    public var recognition: ScreenshotRecognitionResult?
    public var accounts: [Account] = []

    /// 用户最终编辑（与 AI 识别结果分离）。
    public var amountText = ""
    public var formType: TransactionFormType = .expense
    public var merchant = ""
    public var category = TransactionCategory.expense.first ?? "其他"
    public var date = Date()
    public var accountId: UUID = UUID()
    public var note = ""
    public var currencyCode = "CNY"

    public var formError: String?
    public var isSaving = false
    public var didSave = false

    private let bookkeeping: ScreenshotBookkeepingService
    private let accountsRepository: any AccountRepository
    private let session: AppSession
    private let onSaved: (@Sendable () async -> Void)?

    public init(
        bookkeeping: ScreenshotBookkeepingService,
        accounts: any AccountRepository,
        session: AppSession,
        onSaved: (@Sendable () async -> Void)? = nil
    ) {
        self.bookkeeping = bookkeeping
        self.accountsRepository = accounts
        self.session = session
        self.onSaved = onSaved
    }

    public func loadAccounts() async {
        guard let userId = session.currentUserId else { return }
        do {
            accounts = try await accountsRepository.fetchAll(userId: userId).filter { !$0.isArchived }
            if let first = accounts.first {
                accountId = first.id
            }
        } catch {
            formError = error.localizedDescription
        }
    }

    public func prepareForPresentation() {
        recognition = nil
        imageData = nil
        formError = nil
        didSave = false
        amountText = ""
        note = ""
        merchant = ""
        step = privacyAccepted ? .pick : .privacy
    }

    public func acceptPrivacy() {
        privacyAccepted = true
        step = .pick
        Task {
            guard let userId = session.currentUserId else { return }
            try? await bookkeeping.acceptPrivacy(userId: userId)
        }
    }

    public func setImageData(_ data: Data?) {
        formError = nil
        guard let data, !data.isEmpty else {
            step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            return
        }
        imageData = data
        step = .preview
    }

    public func startRecognition() async {
        guard let imageData else {
            step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            return
        }
        guard let userId = session.currentUserId else {
            step = .failed("尚未完成账户初始化")
            return
        }
        step = .recognizing
        formError = nil
        do {
            let result = try await bookkeeping.recognize(imageData: imageData, userId: userId)
            recognition = result
            applyEditable(from: result.editableDraft)
            if let resolved = try await bookkeeping.defaultAccountId(for: result.editableDraft, userId: userId) {
                accountId = resolved
            }
            step = .confirm
        } catch {
            step = .failed(PrivacySafeErrorMapper.userMessage(for: error))
        }
    }

    public func retryFromPick() {
        recognition = nil
        imageData = nil
        formError = nil
        didSave = false
        step = privacyAccepted ? .pick : .privacy
    }

    public func confirmSave() async -> Bool {
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return false
        }
        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: "")), amount > 0 else {
            formError = "请填写有效金额"
            return false
        }

        isSaving = true
        formError = nil
        defer { isSaving = false }

        do {
            _ = try await bookkeeping.confirm(
                ConfirmScreenshotTransactionInput(
                    amount: amount,
                    currencyCode: currencyCode,
                    date: date,
                    merchant: merchant.isEmpty ? nil : merchant,
                    category: category,
                    accountId: accountId,
                    note: note.isEmpty ? nil : note,
                    formType: formType,
                    recognitionConfidence: recognition?.aiDraft.confidence,
                    sourceImageId: recognition?.sourceImageId
                ),
                userId: userId
            )
            didSave = true
            // 数据最小化：确认后立即丢弃内存中的原图。
            imageData = nil
            await onSaved?()
            return true
        } catch {
            formError = PrivacySafeErrorMapper.userMessage(for: error)
            return false
        }
    }

    public var aiDraft: TransactionDraft? { recognition?.aiDraft }
    public var warnings: [String] { recognition?.warnings ?? [] }

    private func applyEditable(from draft: TransactionDraft) {
        if let amount = draft.amount {
            amountText = "\(amount)"
        } else {
            amountText = ""
        }
        if draft.transactionType == .income {
            formType = .income
        } else {
            formType = .expense
        }
        merchant = draft.merchant ?? ""
        let cats = TransactionCategory.categories(for: formType.transactionType)
        if let category = draft.category, cats.contains(category) {
            self.category = category
        } else {
            self.category = cats.first ?? "其他"
        }
        date = draft.date ?? Date()
        currencyCode = draft.currencyCode ?? "CNY"
        note = draft.note ?? ""
    }
}
