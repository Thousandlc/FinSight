import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
@testable import YoushuUI

@Suite("Debt scanner view model reliability")
@MainActor
struct DebtScannerViewModelTests {
    private let sampleImage = Data("debt-scan-viewmodel-bytes".utf8)
    private let userId = UUID()

    private final class SequencedDebtScanner: DebtScanning, @unchecked Sendable {
        private let lock = NSLock()
        private var index = 0
        private let delays: [UInt64]
        private let behaviors: [MockAIProvider.DebtScanBehavior]

        init(delays: [UInt64], behaviors: [MockAIProvider.DebtScanBehavior]) {
            self.delays = delays
            self.behaviors = behaviors
        }

        var name: String { "sequenced-debt-mock" }

        func scanDebts(from documents: [BillDocument]) async throws -> [DebtCandidate] {
            let current: Int = lock.withLock {
                defer { index += 1 }
                return min(index, delays.count - 1)
            }
            try await Task.sleep(nanoseconds: delays[current])
            try Task.checkCancellation()
            return try await MockAIProvider(debtScanBehavior: behaviors[current]).scanDebts(from: documents)
        }

        var callCount: Int {
            lock.withLock { index }
        }
    }

    private struct FailingConsentRepository: AIDataConsentRepository {
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

    private final class MutableFailTokenSet: @unchecked Sendable {
        private let lock = NSLock()
        var tokens: Set<UUID>

        init(_ tokens: Set<UUID>) {
            self.tokens = tokens
        }

        func contains(_ token: UUID) -> Bool {
            lock.withLock { tokens.contains(token) }
        }

        func remove(_ token: UUID) {
            lock.withLock { _ = tokens.remove(token) }
        }
    }

    private final class FailOnTokenDebtManager: DebtManaging, @unchecked Sendable {
        private let inner: DebtService
        private let failTokens: MutableFailTokenSet

        init(inner: DebtService, failTokens: MutableFailTokenSet) {
            self.inner = inner
            self.failTokens = failTokens
        }

        func create(_ input: CreateDebtInput, userId: UUID) async throws -> Debt {
            if let key = input.idempotencyKey, failTokens.contains(key) {
                throw DomainError.validationFailed("simulated create failure")
            }
            return try await inner.create(input, userId: userId)
        }

        func update(_ input: UpdateDebtInput, userId: UUID) async throws -> Debt {
            try await inner.update(input, userId: userId)
        }

        func delete(debtId: UUID, userId: UUID) async throws {
            try await inner.delete(debtId: debtId, userId: userId)
        }

        func recordRepayment(_ input: RecordDebtRepaymentInput, userId: UUID) async throws -> Debt {
            try await inner.recordRepayment(input, userId: userId)
        }
    }

    private func makeViewModel(
        scanner: any DebtScanning = MockAIProvider(debtScanBehavior: .successMultiDebt),
        consentRepository: FailingConsentRepository = FailingConsentRepository(),
        debtManager: (any DebtManaging)? = nil
    ) -> (DebtScannerViewModel, RepositoryContainer, FailingConsentRepository) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let session = AppSession()
        session.configureForPreview(userId: userId)
        let consent = AIDataConsentService(consents: consentRepository)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: NoPersistMediaBinaryStore()
        )
        let debtService = debtManager ?? DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let scannerService = DebtScannerService(
            scanner: scanner,
            debtService: debtService,
            debts: container.debts,
            confirmedImportProvenances: container.confirmedImportProvenances,
            consentService: consent,
            media: media,
            recognitionRecords: container.aiRecognitionRecords
        )
        let viewModel = DebtScannerViewModel(scanner: scannerService, session: session)
        return (viewModel, container, consentRepository)
    }

    private func seedUser(_ container: RepositoryContainer) async throws {
        try await container.users.upsert(User(id: userId, displayName: "VM Tester"))
    }

    private func prepareReview(_ viewModel: DebtScannerViewModel) async {
        viewModel.prepareForPresentation()
        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        await viewModel.startScanAndWait()
    }

    @Test("stale scan completion cannot overwrite newer flow")
    func staleScanIgnored() async throws {
        let customB = MockAIProvider.DebtScanBehavior.custom([
            DebtCandidate(
                lender: "建设银行",
                productName: "消费贷",
                debtType: .consumerLoan,
                outstandingBalance: 5000,
                currencyCode: "CNY",
                confidence: 0.9,
                sourceDocuments: ["doc-b"]
            ),
        ])
        let scanner = SequencedDebtScanner(
            delays: [300_000_000, 0],
            behaviors: [.successMultiDebt, customB]
        )
        let (viewModel, container, _) = makeViewModel(scanner: scanner)
        try await seedUser(container)
        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()
        viewModel.retryFromPick()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()

        for _ in 0..<80 {
            if case .review = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .review)
        #expect(viewModel.reviewItems.count == 1)
        #expect(viewModel.reviewItems[0].editable.lender == "建设银行")
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).count == 1)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).count == 1)
    }

    @Test("dismissed flow does not resurrect review items when scan finishes")
    func dismissPreventsResurrection() async throws {
        let scanner = SequencedDebtScanner(
            delays: [300_000_000],
            behaviors: [.successMultiDebt]
        )
        let (viewModel, container, _) = makeViewModel(scanner: scanner)
        try await seedUser(container)
        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()
        viewModel.handleDismiss()

        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(viewModel.reviewItems.isEmpty)
        #expect(viewModel.step != .review)
        #expect(try await container.debts.fetchAll(userId: userId).isEmpty)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
    }

    @Test("overlapping scans use cancel-and-replace semantics")
    func overlappingScanDeterministic() async throws {
        let scanner = SequencedDebtScanner(
            delays: [200_000_000, 0],
            behaviors: [.successMultiDebt, .successMultiDebt]
        )
        let (viewModel, container, _) = makeViewModel(scanner: scanner)
        try await seedUser(container)
        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()
        viewModel.startScan()

        for _ in 0..<80 {
            if case .review = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .review)
        #expect(scanner.callCount == 2)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).count == 1)
    }

    @Test("accept intro awaits consent persistence before advancing")
    func consentPersistenceSuccess() async throws {
        let consentRepo = FailingConsentRepository()
        let (viewModel, container, _) = makeViewModel(consentRepository: consentRepo)
        try await seedUser(container)

        await viewModel.acceptIntro()

        #expect(viewModel.step == .pick)
        let consent = try await AIDataConsentService(consents: consentRepo).fetchOrDefault(userId: userId)
        #expect(consent.allowDebtScanImageToAI)
    }

    @Test("consent persistence failure does not advance as success")
    func consentPersistenceFailure() async throws {
        var consentRepo = FailingConsentRepository()
        consentRepo.failOnUpsert = true
        let (viewModel, _, _) = makeViewModel(consentRepository: consentRepo)

        await viewModel.acceptIntro()

        #expect(viewModel.step == .intro)
        #expect(viewModel.formError != nil)
    }

    @Test("concurrent single confirm creates exactly one debt")
    func concurrentSingleConfirmIdempotent() async throws {
        let (viewModel, container, _) = makeViewModel()
        try await seedUser(container)
        await prepareReview(viewModel)
        let itemId = viewModel.reviewItems[0].id

        async let first = viewModel.confirmSingle(id: itemId)
        async let second = viewModel.confirmSingle(id: itemId)
        _ = await [first, second]

        #expect(try await container.debts.fetchAll(userId: userId).count == 1)
        #expect(!viewModel.reviewItems[0].isConfirmable)
    }

    @Test("confirm-all re-entry does not duplicate debts")
    func concurrentConfirmAllIdempotent() async throws {
        let (viewModel, container, _) = makeViewModel()
        try await seedUser(container)
        await prepareReview(viewModel)

        async let first = viewModel.confirmAll()
        async let second = viewModel.confirmAll()
        _ = await [first, second]

        #expect(try await container.debts.fetchAll(userId: userId).count == 2)
    }

    @Test("partial batch retry does not duplicate successful candidates")
    func partialBatchRetry() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await seedUser(container)
        let inner = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let scanner = MockAIProvider(debtScanBehavior: .successMultiDebt)
        let failToken = UUID()
        let failTokens = MutableFailTokenSet([failToken])
        let debtManager = FailOnTokenDebtManager(inner: inner, failTokens: failTokens)
        let consentRepo = FailingConsentRepository()
        let consent = AIDataConsentService(consents: consentRepo)
        let scannerService = DebtScannerService(
            scanner: scanner,
            debtService: debtManager,
            consentService: consent
        )
        let session = AppSession()
        session.configureForPreview(userId: userId)
        let viewModel = DebtScannerViewModel(scanner: scannerService, session: session)

        viewModel.prepareForPresentation()
        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        await viewModel.startScanAndWait()
        #expect(viewModel.reviewItems.count == 2)

        viewModel.reviewItems[1].confirmationToken = failToken
        _ = await viewModel.confirmAll()
        #expect(try await container.debts.fetchAll(userId: userId).count == 1)
        #expect(viewModel.reviewItems[0].isConfirmable == false)
        #expect(viewModel.reviewItems[1].isConfirmable)

        failTokens.remove(failToken)
        _ = await viewModel.confirmSingle(id: viewModel.reviewItems[1].id)
        #expect(try await container.debts.fetchAll(userId: userId).count == 2)
    }

    @Test("exact prior scan warns before scanner invocation")
    func priorScanWarningBlocksScanner() async throws {
        let scanner = SequencedDebtScanner(delays: [0], behaviors: [.successMultiDebt])
        let (viewModel, container, _) = makeViewModel(scanner: scanner)
        try await seedUser(container)
        try await seedPriorScanProvenance(container: container)

        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()

        for _ in 0..<40 {
            if case .priorScanWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .priorScanWarning)
        #expect(viewModel.priorScanWarning?.existingDebts.count == 1)
        #expect(scanner.callCount == 0)
    }

    @Test("explicit continue resumes scan once")
    func explicitContinueResumesScan() async throws {
        let scanner = SequencedDebtScanner(delays: [0], behaviors: [.successMultiDebt])
        let (viewModel, container, _) = makeViewModel(scanner: scanner)
        try await seedUser(container)
        try await seedPriorScanProvenance(container: container)

        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()
        for _ in 0..<40 {
            if case .priorScanWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        viewModel.continueDespitePriorScan()
        for _ in 0..<80 {
            if case .review = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .review)
        #expect(scanner.callCount == 1)
    }

    @Test("override resets after reselect")
    func overrideResetOnReselect() async throws {
        let scanner = SequencedDebtScanner(delays: [0], behaviors: [.successMultiDebt])
        let (viewModel, container, _) = makeViewModel(scanner: scanner)
        try await seedUser(container)
        try await seedPriorScanProvenance(container: container)

        await viewModel.acceptIntro()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()
        for _ in 0..<40 {
            if case .priorScanWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        viewModel.continueDespitePriorScan()
        for _ in 0..<80 {
            if case .review = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        viewModel.retryFromPick()
        viewModel.setImageDatas([sampleImage])
        viewModel.startScan()
        for _ in 0..<40 {
            if case .priorScanWarning = viewModel.step { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(viewModel.step == .priorScanWarning)
    }

    private func seedPriorScanProvenance(container: RepositoryContainer) async throws {
        let batch = [BillDocument(kind: .screenshot, data: sampleImage, fileName: "seed.png")]
        let identity = DebtScanImportIdentity.from(documents: batch)
        let debtId = UUID()
        let debt = Debt(
            id: debtId,
            userId: userId,
            lender: "种子银行",
            productName: "消费贷",
            debtType: .consumerLoan,
            outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
            source: .screenshot
        )
        try await container.debts.upsert(debt)
        let provenance = try ConfirmedImportProvenance(
            userId: userId,
            capability: .debtScan,
            sourceFingerprints: identity.sourceFingerprints,
            confirmedEntityReferences: [.debt(debtId)]
        )
        _ = try await container.confirmedImportProvenances.upsert(provenance)
    }
}

private extension DebtScannerViewModel {
    func startScanAndWait() async {
        startScan()
        for _ in 0..<80 {
            if case .review = step { return }
            if case .failed = step { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
