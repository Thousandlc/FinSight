import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
@testable import YoushuUI

@Suite("Screenshot bookkeeping view model reliability")
@MainActor
struct ScreenshotBookkeepingViewModelTests {
    private let sampleImage = Data("viewmodel-screenshot-bytes".utf8)
    private let userId = UUID()

    private final class SequencedTransactionExtractor: TransactionExtracting, @unchecked Sendable {
        private let lock = NSLock()
        private var index = 0
        private let delays: [UInt64]
        private let behaviors: [MockAIProvider.Behavior]

        init(delays: [UInt64], behaviors: [MockAIProvider.Behavior]) {
            self.delays = delays
            self.behaviors = behaviors
        }

        var name: String { "sequenced-mock" }

        func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
            let current: Int = lock.withLock {
                defer { index += 1 }
                return min(index, delays.count - 1)
            }
            try await Task.sleep(nanoseconds: delays[current])
            try Task.checkCancellation()
            return try await MockAIProvider(behavior: behaviors[current]).extractTransactionDraft(fromImageData: data)
        }

        var callCount: Int {
            lock.withLock { index }
        }
    }

    private final class FixedOutcomeExtractor: TransactionExtracting, @unchecked Sendable {
        private let lock = NSLock()
        private let outcome: TransactionRecognitionOutcome
        private var calls = 0

        init(_ outcome: TransactionRecognitionOutcome) {
            self.outcome = outcome
        }

        var name: String { "fixed-outcome" }

        func recognizeTransaction(fromImageData data: Data) async -> TransactionRecognitionOutcome {
            _ = data
            lock.withLock { calls += 1 }
            return outcome
        }

        func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
            switch await recognizeTransaction(fromImageData: data) {
            case .recognized(let draft): return draft
            case .unsupported: throw AIRecognitionError.invalidResponse("暂不支持此类交易截图")
            case .unreadable: throw AIRecognitionError.imageUnreadable
            case .failure(let error): throw error
            }
        }

        var callCount: Int { lock.withLock { calls } }
    }

    private actor CompletionGate {
        private var completed: Set<Int> = []
        private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

        func wait(for index: Int) async {
            if completed.remove(index) != nil { return }
            await withCheckedContinuation { continuation in
                continuations[index] = continuation
            }
        }

        func complete(_ index: Int) {
            if let continuation = continuations.removeValue(forKey: index) {
                continuation.resume()
            } else {
                completed.insert(index)
            }
        }
    }

    private final class ControlledOutcomeExtractor: TransactionExtracting, @unchecked Sendable {
        private let lock = NSLock()
        private let outcomes: [TransactionRecognitionOutcome]
        private let gate = CompletionGate()
        private var calls = 0

        init(_ outcomes: [TransactionRecognitionOutcome]) {
            self.outcomes = outcomes
        }

        var name: String { "controlled-outcome" }

        func recognizeTransaction(fromImageData data: Data) async -> TransactionRecognitionOutcome {
            _ = data
            let index = lock.withLock { () -> Int in
                defer { calls += 1 }
                return min(calls, outcomes.count - 1)
            }
            await gate.wait(for: index)
            return outcomes[index]
        }

        func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
            switch await recognizeTransaction(fromImageData: data) {
            case .recognized(let draft): return draft
            case .unsupported: throw AIRecognitionError.invalidResponse("暂不支持此类交易截图")
            case .unreadable: throw AIRecognitionError.imageUnreadable
            case .failure(let error): throw error
            }
        }

        var callCount: Int { lock.withLock { calls } }

        func complete(_ index: Int) async {
            await gate.complete(index)
        }
    }

    private final class FailingConsentRepository: AIDataConsentRepository, @unchecked Sendable {
        var failOnUpsert = false
        private var stored: AIDataConsent?

        func upsert(_ consent: AIDataConsent) async throws {
            if failOnUpsert {
                throw DataError.persistenceFailed("simulated consent save failure")
            }
            stored = consent
        }

        func fetch(userId: UUID) async throws -> AIDataConsent? {
            _ = userId
            return stored
        }

        func delete(userId: UUID) async throws {
            _ = userId
            stored = nil
        }
    }

    private struct ThrowingDebtLinker: TransactionDebtLinking {
        func processNewTransaction(_ transaction: Transaction, userId: UUID) async throws -> DebtLinkOutcome {
            _ = transaction
            _ = userId
            throw DomainError.invalidRelation("simulated debt linking failure")
        }

        func confirmPendingLink(pendingId: UUID, debtId: UUID, userId: UUID) async throws -> Debt {
            throw DomainError.notFound(entity: "PendingDebtLink", id: pendingId)
        }

        func ignorePendingLink(pendingId: UUID, userId: UUID) async throws {
            _ = pendingId
            _ = userId
        }

        func refreshSuspectedDebts(userId: UUID) async throws -> [SuspectedDebt] {
            _ = userId
            return []
        }

        func confirmSuspectedDebt(suspectedId: UUID, userId: UUID) async throws -> Debt {
            throw DomainError.notFound(entity: "SuspectedDebt", id: suspectedId)
        }

        func ignoreSuspectedDebt(suspectedId: UUID, userId: UUID) async throws {
            _ = suspectedId
            _ = userId
        }

        func pendingLinks(userId: UUID) async throws -> [PendingDebtLink] {
            _ = userId
            return []
        }
    }

    private func makeViewModel(
        extractor: any TransactionExtracting = MockAIProvider(behavior: .success),
        consentRepository: FailingConsentRepository = FailingConsentRepository(),
        debtLinker: (any TransactionDebtLinking)? = nil
    ) -> (ScreenshotBookkeepingViewModel, RepositoryContainer, FailingConsentRepository) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let session = AppSession(users: container.users)
        session.configureForPreview(userId: userId)
        let consent = AIDataConsentService(consents: consentRepository)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: NoPersistMediaBinaryStore()
        )
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions,
            debtLinker: debtLinker
        )
        let bookkeeping = ScreenshotBookkeepingService(
            extractor: extractor,
            transactionService: txService,
            accounts: container.accounts,
            transactions: container.transactions,
            confirmedImportProvenances: container.confirmedImportProvenances,
            consentService: consent,
            media: media,
            recognitionRecords: container.aiRecognitionRecords
        )
        let viewModel = ScreenshotBookkeepingViewModel(
            bookkeeping: bookkeeping,
            accounts: container.accounts,
            session: session
        )
        return (viewModel, container, consentRepository)
    }

    private func seedAccount(_ container: RepositoryContainer) async throws -> Account {
        try await container.users.upsert(User(id: userId, displayName: "VM Tester"))
        let account = Account(userId: userId, name: "现金", type: .cash)
        try await container.accounts.upsert(account)
        return account
    }

    private func prepareConfirmable(_ viewModel: ScreenshotBookkeepingViewModel) async {
        viewModel.prepareForPresentation()
        await viewModel.acceptPrivacy()
        viewModel.setImageData(sampleImage)
        await viewModel.startRecognitionAndWait()
    }

    @Test("stale recognition completion cannot overwrite newer flow")
    func staleRecognitionIgnored() async throws {
        let extractor = SequencedTransactionExtractor(
            delays: [300_000_000, 0],
            behaviors: [.success, .dateMissing]
        )
        let (viewModel, container, consentRepo) = makeViewModel(extractor: extractor)
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()

        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.retryFromPick()
        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()

        for _ in 0..<80 {
            if case .confirm = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .confirm)
        #expect(viewModel.recognition?.aiDraft.date == nil)
        #expect(viewModel.warnings.contains(where: { $0.contains("时间") }))
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).count == 1)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).count == 1)
    }

    @Test("dismissed flow does not resurrect draft when recognizer finishes")
    func dismissPreventsResurrection() async throws {
        let extractor = SequencedTransactionExtractor(
            delays: [300_000_000],
            behaviors: [.success]
        )
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()

        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()
        viewModel.handleDismiss()

        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(viewModel.recognition == nil)
        #expect(viewModel.step != .confirm)
        #expect(try await container.transactions.fetchAll(userId: userId).isEmpty)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
    }

    @Test("overlapping recognition uses cancel-and-replace semantics")
    func overlappingRecognitionDeterministic() async throws {
        let extractor = SequencedTransactionExtractor(
            delays: [200_000_000, 0],
            behaviors: [.success, .success]
        )
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()

        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.startRecognition()

        for _ in 0..<80 {
            if case .confirm = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .confirm)
        #expect(extractor.callCount == 2)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).count == 1)
    }

    @Test("accept privacy awaits persistence before advancing")
    func consentPersistenceSuccess() async throws {
        let consentRepo = FailingConsentRepository()
        let (viewModel, container, _) = makeViewModel(consentRepository: consentRepo)
        _ = try await seedAccount(container)

        await viewModel.acceptPrivacy()

        #expect(viewModel.privacyAccepted)
        #expect(viewModel.step == .pick)
        let consent = try await AIDataConsentService(consents: consentRepo).fetchOrDefault(userId: userId)
        #expect(consent.allowScreenshotImageToAI)
    }

    @Test("consent persistence failure does not advance as success")
    func consentPersistenceFailure() async throws {
        var consentRepo = FailingConsentRepository()
        consentRepo.failOnUpsert = true
        let (viewModel, _, _) = makeViewModel(consentRepository: consentRepo)

        await viewModel.acceptPrivacy()

        #expect(!viewModel.privacyAccepted)
        #expect(viewModel.step == .privacy)
        #expect(viewModel.formError != nil)
    }

    @Test("denied consent blocks recognizer review and metadata below UI")
    func deniedConsentBlocksRecognition() async throws {
        let extractor = FixedOutcomeExtractor(.recognized(MockAIProvider.sampleSuccessDraft()))
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()

        viewModel.setImageData(sampleImage)
        await viewModel.startRecognitionAndWait()

        #expect(extractor.callCount == 0)
        #expect(viewModel.recognition == nil)
        #expect(viewModel.step != .confirm)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
        #expect(try await container.transactions.fetchAll(userId: userId).isEmpty)
    }

    @Test("recognized outcome enters review without creating Transaction")
    func recognizedOutcomeEntersReviewOnly() async throws {
        let extractor = FixedOutcomeExtractor(.recognized(MockAIProvider.sampleSuccessDraft()))
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()
        viewModel.setImageData(sampleImage)
        await viewModel.startRecognitionAndWait()

        #expect(viewModel.step == .confirm)
        #expect(viewModel.recognition != nil)
        #expect(try await container.transactions.fetchAll(userId: userId).isEmpty)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).isEmpty)
    }

    @Test("unsupported outcome keeps a distinct user-facing reason")
    func unsupportedOutcome() async throws {
        let (viewModel, container, _) = makeViewModel(extractor: FixedOutcomeExtractor(.unsupported))
        _ = try await seedAccount(container)
        await viewModel.acceptPrivacy()
        viewModel.setImageData(sampleImage)
        await viewModel.startRecognitionAndWait()

        guard case .failed(let message) = viewModel.step else {
            Issue.record("Expected unsupported failure state")
            return
        }
        #expect(message.contains("暂不支持"))
        #expect(viewModel.recognition == nil)
    }

    @Test("unreadable outcome remains distinct from operational failure")
    func unreadableOutcome() async throws {
        let (viewModel, container, _) = makeViewModel(extractor: FixedOutcomeExtractor(.unreadable))
        _ = try await seedAccount(container)
        await viewModel.acceptPrivacy()
        viewModel.setImageData(sampleImage)
        await viewModel.startRecognitionAndWait()

        guard case .failed(let message) = viewModel.step else {
            Issue.record("Expected unreadable failure state")
            return
        }
        #expect(message.contains("无法读取图片"))
        #expect(!message.contains("暂不支持"))
    }

    @Test("operational failure keeps provider-safe failure reason")
    func operationalFailureOutcome() async throws {
        let extractor = FixedOutcomeExtractor(.failure(.requestFailed("本地识别故障")))
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        _ = try await seedAccount(container)
        await viewModel.acceptPrivacy()
        viewModel.setImageData(sampleImage)
        await viewModel.startRecognitionAndWait()

        guard case .failed(let message) = viewModel.step else {
            Issue.record("Expected operational failure state")
            return
        }
        #expect(message.contains("本地识别故障"))
        #expect(!message.contains("暂不支持"))
        #expect(!message.contains("无法读取图片"))
    }

    @Test("stale operational failure cannot replace newer accepted review")
    func staleFailureIgnored() async throws {
        let extractor = ControlledOutcomeExtractor([
            .failure(.requestFailed("旧请求失败")),
            .recognized(MockAIProvider.sampleSuccessDraft()),
        ])
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()
        viewModel.setImageData(sampleImage)

        viewModel.startRecognition()
        for _ in 0..<40 where extractor.callCount < 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        viewModel.startRecognition()
        for _ in 0..<40 where extractor.callCount < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        await extractor.complete(1)
        for _ in 0..<80 {
            if case .confirm = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await extractor.complete(0)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.step == .confirm)
        #expect(viewModel.recognition?.aiDraft.amount == Decimal(string: "36.50"))
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).count == 1)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).count == 1)
    }

    @Test("concurrent confirm creates exactly one transaction")
    func concurrentConfirmIdempotent() async throws {
        let (viewModel, container, _) = makeViewModel()
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()
        await prepareConfirmable(viewModel)

        async let first = viewModel.confirmSave()
        async let second = viewModel.confirmSave()
        _ = await [first, second]

        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
    }

    @Test("retry after linking failure does not create duplicate transaction")
    func retryAfterLinkingFailure() async throws {
        let (viewModel, container, _) = makeViewModel(debtLinker: ThrowingDebtLinker())
        _ = try await seedAccount(container)
        await viewModel.loadAccounts()
        await prepareConfirmable(viewModel)

        let first = await viewModel.confirmSave()
        #expect(first)
        #expect(viewModel.linkingWarning != nil)

        let second = await viewModel.confirmSave()
        #expect(second)
        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
    }

    @Test("normal confirmation still creates expected transaction")
    func normalConfirmationRegression() async throws {
        let (viewModel, container, _) = makeViewModel()
        let account = try await seedAccount(container)
        await viewModel.loadAccounts()
        await prepareConfirmable(viewModel)

        let ok = await viewModel.confirmSave()
        #expect(ok)

        let txs = try await container.transactions.fetchAll(userId: userId)
        #expect(txs.count == 1)
        #expect(txs[0].amount.amount == Decimal(string: "36.50"))
        #expect(txs[0].accountId == account.id)
        #expect(txs[0].source == .screenshot)
    }

    @Test("exact prior import warns before recognition")
    func priorImportWarningBlocksRecognizer() async throws {
        let extractor = SequencedTransactionExtractor(delays: [0], behaviors: [.success])
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        let account = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()

        let firstResult = try await acceptThroughService(container: container, account: account)
        _ = firstResult

        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()

        for _ in 0..<40 {
            if case .priorImportWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .priorImportWarning)
        #expect(viewModel.priorImportWarning?.existingTransactions.count == 1)
        #expect(extractor.callCount == 0)
    }

    @Test("explicit override resumes recognition once")
    func explicitOverrideResumesRecognition() async throws {
        let extractor = SequencedTransactionExtractor(delays: [0], behaviors: [.success])
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        let account = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()
        _ = try await acceptThroughService(container: container, account: account)

        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()
        for _ in 0..<40 {
            if case .priorImportWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        viewModel.continueDespitePriorImport()
        for _ in 0..<80 {
            if case .confirm = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .confirm)
        #expect(extractor.callCount == 1)
    }

    @Test("override resets after reselect")
    func overrideResetOnReselect() async throws {
        let extractor = SequencedTransactionExtractor(delays: [0], behaviors: [.success])
        let (viewModel, container, _) = makeViewModel(extractor: extractor)
        let account = try await seedAccount(container)
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()
        _ = try await acceptThroughService(container: container, account: account)

        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()
        for _ in 0..<40 {
            if case .priorImportWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        viewModel.continueDespitePriorImport()
        for _ in 0..<80 {
            if case .confirm = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        viewModel.retryFromPick()
        viewModel.setImageData(sampleImage)
        viewModel.startRecognition()
        for _ in 0..<40 {
            if case .priorImportWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .priorImportWarning)
    }

    private func acceptThroughService(
        container: RepositoryContainer,
        account: Account
    ) async throws -> Transaction {
        let consent = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consent.acceptScreenshotPrivacy(userId: userId)
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        let service = ScreenshotBookkeepingService(
            extractor: MockAIProvider(behavior: .success),
            transactionService: txService,
            accounts: container.accounts,
            transactions: container.transactions,
            confirmedImportProvenances: container.confirmedImportProvenances
        )
        let identity = TransactionScreenshotImportIdentity.from(imageData: sampleImage)
        let pending = try await service.recognize(
            imageData: sampleImage,
            userId: userId,
            importIdentity: identity
        )
        let result = try await service.acceptRecognition(pending, userId: userId)
        let outcome = try await service.confirm(
            ConfirmScreenshotTransactionInput(
                amount: result.editableDraft.amount!,
                date: result.editableDraft.date ?? Date(),
                merchant: result.editableDraft.merchant,
                category: result.editableDraft.category ?? "交通",
                accountId: account.id,
                formType: .expense,
                recognitionConfidence: result.editableDraft.confidence,
                sourceImageId: result.sourceImageId,
                confirmationToken: UUID(),
                importIdentity: result.importIdentity
            ),
            userId: userId
        )
        return outcome.transaction
    }
}

private extension ScreenshotBookkeepingViewModel {
    func startRecognitionAndWait() async {
        startRecognition()
        for _ in 0..<80 {
            if case .confirm = step { return }
            if case .failed = step { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
