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
        case scanning
        case review
        case failed(String)
    }

    public var step: Step = .intro
    public var documents: [BillDocument] = []
    public var reviewItems: [ReviewableDebtCandidate] = []
    public var warnings: [String] = []
    public var formError: String?
    public var isSaving = false
    public var editingItemId: UUID?

    private let scanner: DebtScannerService
    private let session: AppSession
    private let onCompleted: (@Sendable () async -> Void)?

    public init(
        scanner: DebtScannerService,
        session: AppSession,
        onCompleted: (@Sendable () async -> Void)? = nil
    ) {
        self.scanner = scanner
        self.session = session
        self.onCompleted = onCompleted
    }

    public func prepareForPresentation() {
        documents = []
        reviewItems = []
        warnings = []
        formError = nil
        isSaving = false
        editingItemId = nil
        step = .intro
    }

    public func acceptIntro() {
        step = .pick
        Task {
            guard let userId = session.currentUserId else { return }
            try? await scanner.acceptPrivacy(userId: userId)
        }
    }

    public func setImageDatas(_ datas: [Data]) {
        formError = nil
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
        let index = documents.count + 1
        documents.append(
            BillDocument(kind: .screenshot, data: data, fileName: "screenshot-\(index).png")
        )
        step = .preview
    }

    public func removeDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        if documents.isEmpty {
            step = .pick
        }
    }

    public func startScan() async {
        guard !documents.isEmpty else {
            step = .failed(AIRecognitionError.imageUnreadable.userMessage)
            return
        }
        guard let userId = session.currentUserId else {
            step = .failed("尚未完成账户初始化")
            return
        }
        step = .scanning
        formError = nil
        do {
            let result = try await scanner.scan(documents: documents, userId: userId)
            warnings = result.warnings
            reviewItems = result.candidates.map(ReviewableDebtCandidate.init(from:))
            documents = []
            step = .review
        } catch {
            step = .failed(PrivacySafeErrorMapper.userMessage(for: error))
        }
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
        reviewItems.filter { !$0.isIgnored }
    }

    public func confirmAll() async -> Bool {
        await confirm(candidates: confirmableItems.map(\.editable))
    }

    public func confirmSingle(id: UUID) async -> Bool {
        guard let item = reviewItems.first(where: { $0.id == id }), !item.isIgnored else {
            formError = "该候选已被忽略"
            return false
        }
        let ok = await confirm(candidates: [item.editable])
        if ok {
            ignoreItem(id: id)
        }
        return ok
    }

    public func retryFromPick() {
        documents = []
        reviewItems = []
        warnings = []
        formError = nil
        step = .pick
    }

    private func confirm(candidates: [DebtCandidate]) async -> Bool {
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return false
        }
        guard !candidates.isEmpty else {
            formError = "请至少确认一笔债务"
            return false
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }

        do {
            _ = try await scanner.confirm(candidates: candidates, userId: userId)
            documents = []
            await onCompleted?()
            return true
        } catch {
            formError = PrivacySafeErrorMapper.userMessage(for: error)
            return false
        }
    }
}
