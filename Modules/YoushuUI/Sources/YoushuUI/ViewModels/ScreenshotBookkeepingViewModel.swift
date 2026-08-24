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
        case priorImportWarning
        case recognizing
        case confirm
        case failed(String)
    }

    public var step: Step = .privacy
    public var privacyAccepted = false
    public var imageData: Data?
    public var recognition: ScreenshotRecognitionResult?
    public var priorImportWarning: ScreenshotPriorImportWarning?
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
    public var linkingWarning: String?
    public var provenanceWarning: String?
    public var isSaving = false
    public var didSave = false
    public var isAcceptingPrivacy = false

    private let bookkeeping: ScreenshotBookkeepingService
    private let accountsRepository: any AccountRepository
    private let session: AppSession
    private let onSaved: (@Sendable () async -> Void)?
    private let onViewExistingTransaction: (@Sendable (UUID) async -> Void)?

    private var recognitionGeneration: UInt64 = 0
    private var recognitionTask: Task<Void, Never>?
    private var confirmationToken: UUID?
    private var confirmedTransactionId: UUID?
    private var confirmInFlight = false
    private var importIdentity: TransactionScreenshotImportIdentity?
    private var explicitReimportOverride = false

    public init(
        bookkeeping: ScreenshotBookkeepingService,
        accounts: any AccountRepository,
        session: AppSession,
        onSaved: (@Sendable () async -> Void)? = nil,
        onViewExistingTransaction: (@Sendable (UUID) async -> Void)? = nil
    ) {
        self.bookkeeping = bookkeeping
        self.accountsRepository = accounts
        self.session = session
        self.onSaved = onSaved
        self.onViewExistingTransaction = onViewExistingTransaction
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
        invalidateRecognitionOperation()
        recognition = nil
        imageData = nil
        priorImportWarning = nil
        importIdentity = nil
        explicitReimportOverride = false
        formError = nil
        linkingWarning = nil
        provenanceWarning = nil
        didSave = false
        confirmedTransactionId = nil
        confirmationToken = nil
        amountText = ""
        note = ""
        merchant = ""
        step = privacyAccepted ? .pick : .privacy
    }

    public func handleDismiss() {
        invalidateRecognitionOperation()
        recognition = nil
        imageData = nil
        priorImportWarning = nil
        importIdentity = nil
        explicitReimportOverride = false
        confirmationToken = nil
        confirmedTransactionId = nil
        formError = nil
        linkingWarning = nil
        provenanceWarning = nil
        didSave = false
    }

    public func acceptPrivacy() async {
        guard !isAcceptingPrivacy else { return }
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return
        }
        isAcceptingPrivacy = true
        formError = nil
        defer { isAcceptingPrivacy = false }
        do {
            try await bookkeeping.acceptPrivacy(userId: userId)
            privacyAccepted = true
            step = .pick
        } catch {
            privacyAccepted = false
            step = .privacy
            formError = PrivacySafeErrorMapper.userMessage(for: error)
        }
    }

    public func setImageData(_ data: Data?) {
        formError = nil
        priorImportWarning = nil
        importIdentity = nil
        explicitReimportOverride = false
        guard let data, !data.isEmpty else {
            step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            return
        }
        imageData = data
        step = .preview
    }

    public func startRecognition() {
        startRecognitionTask()
    }

    public func continueDespitePriorImport() {
        explicitReimportOverride = true
        priorImportWarning = nil
        startRecognitionTask()
    }

    public func cancelPriorImportWarning() {
        priorImportWarning = nil
        explicitReimportOverride = false
        importIdentity = nil
        step = .preview
    }

    public func viewExistingTransaction(_ transactionId: UUID) async {
        await onViewExistingTransaction?(transactionId)
    }

    public func retryFromPick() {
        invalidateRecognitionOperation()
        recognition = nil
        imageData = nil
        priorImportWarning = nil
        importIdentity = nil
        explicitReimportOverride = false
        formError = nil
        linkingWarning = nil
        provenanceWarning = nil
        didSave = false
        confirmedTransactionId = nil
        confirmationToken = nil
        step = privacyAccepted ? .pick : .privacy
    }

    public func confirmSave() async -> Bool {
        if confirmedTransactionId != nil {
            return true
        }
        guard !confirmInFlight else { return false }
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return false
        }
        guard let confirmationToken else {
            formError = "识别结果已失效，请重新识别"
            return false
        }
        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: "")), amount > 0 else {
            formError = "请填写有效金额"
            return false
        }

        confirmInFlight = true
        isSaving = true
        formError = nil
        linkingWarning = nil
        provenanceWarning = nil
        defer {
            confirmInFlight = false
            isSaving = false
        }

        do {
            let outcome = try await bookkeeping.confirm(
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
                    sourceImageId: recognition?.sourceImageId,
                    confirmationToken: confirmationToken,
                    importIdentity: recognition?.importIdentity ?? importIdentity
                ),
                userId: userId
            )
            confirmedTransactionId = outcome.transaction.id
            didSave = true
            invalidateRecognitionOperation()
            recognition = nil
            self.confirmationToken = nil
            importIdentity = nil
            imageData = nil
            linkingWarning = outcome.debtLinkingIssue
            provenanceWarning = outcome.provenanceIssue
            await onSaved?()
            return true
        } catch {
            if confirmedTransactionId != nil {
                return true
            }
            formError = PrivacySafeErrorMapper.userMessage(for: error)
            return false
        }
    }

    public var aiDraft: TransactionDraft? { recognition?.aiDraft }
    public var warnings: [String] { recognition?.warnings ?? [] }

    private func startRecognitionTask() {
        invalidateRecognitionOperation()
        let generation = bumpRecognitionGeneration()
        recognitionTask = Task { @MainActor in
            await performRecognition(generation: generation)
        }
    }

    private func performRecognition(generation: UInt64) async {
        guard let imageData else {
            guard isCurrentRecognitionGeneration(generation) else { return }
            step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            clearRecognitionTaskIfCurrent(generation)
            return
        }
        guard let userId = session.currentUserId else {
            guard isCurrentRecognitionGeneration(generation) else { return }
            step = .failed("尚未完成账户初始化")
            clearRecognitionTaskIfCurrent(generation)
            return
        }
        guard isCurrentRecognitionGeneration(generation) else { return }

        step = .recognizing
        formError = nil
        linkingWarning = nil
        provenanceWarning = nil
        confirmedTransactionId = nil
        confirmationToken = nil

        do {
            if !explicitReimportOverride {
                if let warning = try await bookkeeping.checkPriorImport(imageData: imageData, userId: userId) {
                    guard !Task.isCancelled, isCurrentRecognitionGeneration(generation) else { return }
                    priorImportWarning = warning
                    importIdentity = warning.importIdentity
                    step = .priorImportWarning
                    clearRecognitionTaskIfCurrent(generation)
                    return
                }
            }

            let shouldConsumeOverride = explicitReimportOverride
            if importIdentity == nil {
                importIdentity = TransactionScreenshotImportIdentity.from(imageData: imageData)
            }
            guard let importIdentity else {
                step = .failed(AIRecognitionError.imageUnreadable.userMessage)
                clearRecognitionTaskIfCurrent(generation)
                return
            }

            let pending = try await bookkeeping.recognize(
                imageData: imageData,
                userId: userId,
                importIdentity: importIdentity
            )
            if shouldConsumeOverride {
                explicitReimportOverride = false
            }
            guard !Task.isCancelled, isCurrentRecognitionGeneration(generation) else { return }
            let result = try await bookkeeping.acceptRecognition(pending, userId: userId)
            guard !Task.isCancelled, isCurrentRecognitionGeneration(generation) else { return }
            recognition = result
            confirmationToken = UUID()
            applyEditable(from: result.editableDraft)
            if let resolved = try await bookkeeping.defaultAccountId(for: result.editableDraft, userId: userId) {
                guard isCurrentRecognitionGeneration(generation) else { return }
                accountId = resolved
            }
            guard isCurrentRecognitionGeneration(generation) else { return }
            step = .confirm
        } catch {
            explicitReimportOverride = false
            guard !Task.isCancelled, isCurrentRecognitionGeneration(generation) else { return }
            step = .failed(PrivacySafeErrorMapper.userMessage(for: error))
        }
        clearRecognitionTaskIfCurrent(generation)
    }

    private func invalidateRecognitionOperation() {
        recognitionGeneration &+= 1
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    @discardableResult
    private func bumpRecognitionGeneration() -> UInt64 {
        recognitionGeneration &+= 1
        return recognitionGeneration
    }

    private func isCurrentRecognitionGeneration(_ generation: UInt64) -> Bool {
        generation == recognitionGeneration
    }

    private func clearRecognitionTaskIfCurrent(_ generation: UInt64) {
        if generation == recognitionGeneration {
            recognitionTask = nil
        }
    }

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
