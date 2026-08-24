import Foundation
import YoushuDesignSystem
import YoushuDomain

@Observable
@MainActor
public final class DebtScannerViewModel {
    public enum Step: Equatable {
        case intro
        case pick
        case preview
        case priorScanWarning
        case scanning
        case review
        case failed(String)
    }

    public var step: Step = .intro
    public var documents: [BillDocument] = []
    public var priorScanWarning: DebtPriorScanWarning?
    public var reviewItems: [ReviewableDebtCandidate] = []
    public var warnings: [String] = []
    public var formError: String?
    public var provenanceWarning: String?
    public var isSaving = false
    public var isAcceptingIntro = false
    public var editingItemId: UUID?

    private let scanner: DebtScannerService
    private let session: AppSession
    private let onCompleted: (@Sendable () async -> Void)?
    private let onViewExistingDebt: (@Sendable (UUID) async -> Void)?

    private var scanGeneration: UInt64 = 0
    private var scanTask: Task<Void, Never>?
    private var confirmInFlight = false
    private var scanImportIdentity: DebtScanImportIdentity?
    private var explicitRescanOverride = false

    public init(
        scanner: DebtScannerService,
        session: AppSession,
        onCompleted: (@Sendable () async -> Void)? = nil,
        onViewExistingDebt: (@Sendable (UUID) async -> Void)? = nil
    ) {
        self.scanner = scanner
        self.session = session
        self.onCompleted = onCompleted
        self.onViewExistingDebt = onViewExistingDebt
    }

    public func prepareForPresentation() {
        invalidateScanOperation()
        documents = []
        priorScanWarning = nil
        scanImportIdentity = nil
        explicitRescanOverride = false
        reviewItems = []
        warnings = []
        formError = nil
        provenanceWarning = nil
        isSaving = false
        editingItemId = nil
        step = .intro
    }

    public func handleDismiss() {
        invalidateScanOperation()
        documents = []
        priorScanWarning = nil
        scanImportIdentity = nil
        explicitRescanOverride = false
        reviewItems = []
        warnings = []
        formError = nil
        provenanceWarning = nil
        isSaving = false
        editingItemId = nil
    }

    public func acceptIntro() async {
        guard !isAcceptingIntro else { return }
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return
        }
        isAcceptingIntro = true
        formError = nil
        defer { isAcceptingIntro = false }
        do {
            try await scanner.acceptPrivacy(userId: userId)
            step = .pick
        } catch {
            step = .intro
            formError = PrivacySafeErrorMapper.userMessage(for: error)
        }
    }

    public func setImageDatas(_ datas: [Data]) {
        formError = nil
        priorScanWarning = nil
        scanImportIdentity = nil
        explicitRescanOverride = false
        let valid = datas.filter { !$0.isEmpty }
        guard !valid.isEmpty else {
            step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            return
        }
        documents = valid.enumerated().map { index, data in
            BillDocument(
                kind: .screenshot,
                data: data,
                fileName: "screenshot-\(index + 1).png"
            )
        }
        step = .preview
    }

    public func appendImageData(_ data: Data) {
        guard !data.isEmpty else { return }
        priorScanWarning = nil
        scanImportIdentity = nil
        explicitRescanOverride = false
        let index = documents.count + 1
        documents.append(
            BillDocument(kind: .screenshot, data: data, fileName: "screenshot-\(index).png")
        )
        step = .preview
    }

    public func removeDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        priorScanWarning = nil
        scanImportIdentity = nil
        explicitRescanOverride = false
        if documents.isEmpty {
            step = .pick
        }
    }

    public func startScan() {
        startScanTask()
    }

    public func continueDespitePriorScan() {
        explicitRescanOverride = true
        priorScanWarning = nil
        startScanTask()
    }

    public func cancelPriorScanWarning() {
        priorScanWarning = nil
        explicitRescanOverride = false
        scanImportIdentity = nil
        step = .preview
    }

    public func viewExistingDebt(_ debtId: UUID) async {
        await onViewExistingDebt?(debtId)
    }

    public func ignoreItem(id: UUID) {
        guard let index = reviewItems.firstIndex(where: { $0.id == id }) else { return }
        reviewItems[index].isIgnored = true
    }

    public func restoreItem(id: UUID) {
        guard let index = reviewItems.firstIndex(where: { $0.id == id }) else { return }
        reviewItems[index].isIgnored = false
    }

    public func updateEditable(_ candidate: DebtCandidate) {
        guard let index = reviewItems.firstIndex(where: { $0.id == candidate.id }) else { return }
        reviewItems[index].editable = candidate
    }

    public var confirmableItems: [ReviewableDebtCandidate] {
        reviewItems.filter(\.isConfirmable)
    }

    public var allReviewResolved: Bool {
        !reviewItems.isEmpty && reviewItems.allSatisfy { item in
            item.isIgnored || {
                if case .confirmed = item.confirmationState { return true }
                return false
            }()
        }
    }

    public func confirmAll() async -> Bool {
        await confirm(items: confirmableItems)
    }

    public func confirmSingle(id: UUID) async -> Bool {
        guard let item = reviewItems.first(where: { $0.id == id }), item.isConfirmable else {
            formError = "该候选不可确认"
            return false
        }
        return await confirm(items: [item])
    }

    public func retryFromPick() {
        invalidateScanOperation()
        documents = []
        priorScanWarning = nil
        scanImportIdentity = nil
        explicitRescanOverride = false
        reviewItems = []
        warnings = []
        formError = nil
        provenanceWarning = nil
        step = .pick
    }

    private func startScanTask() {
        invalidateScanOperation()
        let generation = bumpScanGeneration()
        scanTask = Task { @MainActor in
            await performScan(generation: generation)
        }
    }

    private func performScan(generation: UInt64) async {
        guard !documents.isEmpty else {
            guard isCurrentScanGeneration(generation) else { return }
            step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            clearScanTaskIfCurrent(generation)
            return
        }
        guard let userId = session.currentUserId else {
            guard isCurrentScanGeneration(generation) else { return }
            step = .failed("尚未完成账户初始化")
            clearScanTaskIfCurrent(generation)
            return
        }
        guard isCurrentScanGeneration(generation) else { return }

        step = .scanning
        formError = nil
        provenanceWarning = nil

        do {
            if !explicitRescanOverride {
                if let warning = try await scanner.checkPriorScan(documents: documents, userId: userId) {
                    guard !Task.isCancelled, isCurrentScanGeneration(generation) else { return }
                    priorScanWarning = warning
                    scanImportIdentity = warning.importIdentity
                    step = .priorScanWarning
                    clearScanTaskIfCurrent(generation)
                    return
                }
            }

            let shouldConsumeOverride = explicitRescanOverride
            if scanImportIdentity == nil {
                scanImportIdentity = DebtScanImportIdentity.from(documents: documents)
            }
            guard let scanImportIdentity else {
                step = .failed(AIRecognitionError.imageUnreadable.userMessage)
                clearScanTaskIfCurrent(generation)
                return
            }

            let pending = try await scanner.scan(
                documents: documents,
                userId: userId,
                importIdentity: scanImportIdentity
            )
            if shouldConsumeOverride {
                explicitRescanOverride = false
            }
            guard !Task.isCancelled, isCurrentScanGeneration(generation) else { return }
            let result = try await scanner.acceptScan(pending, userId: userId)
            guard !Task.isCancelled, isCurrentScanGeneration(generation) else { return }
            self.scanImportIdentity = result.importIdentity
            warnings = result.warnings
            reviewItems = result.candidates.map(ReviewableDebtCandidate.init(from:))
            documents = []
            step = .review
        } catch {
            explicitRescanOverride = false
            guard !Task.isCancelled, isCurrentScanGeneration(generation) else { return }
            step = .failed(PrivacySafeErrorMapper.userMessage(for: error))
        }
        clearScanTaskIfCurrent(generation)
    }

    private func confirm(items: [ReviewableDebtCandidate]) async -> Bool {
        guard !confirmInFlight else { return false }
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return false
        }
        guard !items.isEmpty else {
            formError = "请至少确认一笔债务"
            return false
        }

        confirmInFlight = true
        isSaving = true
        formError = nil
        defer {
            confirmInFlight = false
            isSaving = false
        }

        let cumulativeConfirmedDebtIds = reviewItems.compactMap { item -> UUID? in
            if case .confirmed(let debtId) = item.confirmationState { return debtId }
            return nil
        }
        let requests = items.map {
            ConfirmDebtCandidateInput(
                reviewItemId: $0.id,
                confirmationToken: $0.confirmationToken,
                candidate: $0.editable
            )
        }
        let outcome = await scanner.confirm(
            requests: requests,
            userId: userId,
            importIdentity: scanImportIdentity,
            cumulativeConfirmedDebtIds: cumulativeConfirmedDebtIds
        )
        applyConfirmOutcome(outcome)
        provenanceWarning = outcome.provenanceIssue

        if outcome.isFullySuccessful {
            documents = []
            await onCompleted?()
            return true
        }
        if outcome.hasPartialSuccess {
            formError = partialSuccessMessage(outcome)
            if allReviewResolved {
                await onCompleted?()
            }
            return allReviewResolved
        }
        if let firstFailure = outcome.failed.first?.errorMessage {
            formError = firstFailure
        } else {
            formError = "确认失败，请重试"
        }
        return false
    }

    private func applyConfirmOutcome(_ outcome: DebtScanConfirmOutcome) {
        for result in outcome.results {
            guard let index = reviewItems.firstIndex(where: { $0.id == result.reviewItemId }) else {
                continue
            }
            switch result.status {
            case .succeeded:
                if let debtId = result.debtId {
                    reviewItems[index].confirmationState = .confirmed(debtId: debtId)
                }
            case .failed:
                reviewItems[index].confirmationState = .failed(
                    message: result.errorMessage ?? "确认失败"
                )
            case .notAttempted:
                break
            }
        }
    }

    private func partialSuccessMessage(_ outcome: DebtScanConfirmOutcome) -> String {
        let succeeded = outcome.succeeded.count
        let failed = outcome.failed.count
        let skipped = outcome.notAttempted.count
        var parts = ["已成功创建 \(succeeded) 笔债务"]
        if failed > 0 {
            parts.append("\(failed) 笔失败")
        }
        if skipped > 0 {
            parts.append("\(skipped) 笔未尝试")
        }
        return parts.joined(separator: "，") + "。"
    }

    private func invalidateScanOperation() {
        scanGeneration &+= 1
        scanTask?.cancel()
        scanTask = nil
    }

    @discardableResult
    private func bumpScanGeneration() -> UInt64 {
        scanGeneration &+= 1
        return scanGeneration
    }

    private func isCurrentScanGeneration(_ generation: UInt64) -> Bool {
        generation == scanGeneration
    }

    private func clearScanTaskIfCurrent(_ generation: UInt64) {
        if generation == scanGeneration {
            scanTask = nil
        }
    }
}
