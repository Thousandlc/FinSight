import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Debt scanner reliability")
struct DebtScannerReliabilityTests {
    private func docs(_ labels: [String]) -> [BillDocument] {
        labels.map { BillDocument(kind: .screenshot, data: Data($0.utf8), fileName: $0) }
    }

    private func makeService(
        scanner: any DebtScanning = MockAIProvider(debtScanBehavior: .successMultiDebt),
        debtManager: (any DebtManaging)? = nil
    ) async throws -> (DebtScannerService, RepositoryContainer, UUID) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Reliability"))
        let debtService = debtManager ?? DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let service = DebtScannerService(
            scanner: scanner,
            debtService: debtService
        )
        return (service, container, userId)
    }

    private func threeCandidates(from documents: [BillDocument]) -> [DebtCandidate] {
        let ref = documents[0].referenceId
        return [
            DebtCandidate(
                lender: "候选A",
                productName: "产品A",
                debtType: .consumerLoan,
                outstandingBalance: 1000,
                currencyCode: "CNY",
                confidence: 0.9,
                sourceDocuments: [ref]
            ),
            DebtCandidate(
                lender: "候选B",
                productName: "产品B",
                debtType: .consumerLoan,
                outstandingBalance: 2000,
                currencyCode: "CNY",
                confidence: 0.9,
                sourceDocuments: [ref]
            ),
            DebtCandidate(
                lender: "候选C",
                productName: "产品C",
                debtType: .consumerLoan,
                outstandingBalance: 3000,
                currencyCode: "CNY",
                confidence: 0.9,
                sourceDocuments: [ref]
            ),
        ]
    }

    private final class FailOnTokenDebtManager: DebtManaging, @unchecked Sendable {
        private let inner: DebtService
        private let failTokens: Set<UUID>

        init(inner: DebtService, failTokens: Set<UUID>) {
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

    private func createdEventCount(container: RepositoryContainer, debtId: UUID) async throws -> Int {
        try await container.debtEvents.fetchAll(debtId: debtId).filter { $0.type == .created }.count
    }

    private func runScan(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> PendingDebtScanResult {
        let identity = DebtScanImportIdentity.from(documents: documents)
        return try await service.scan(documents: documents, userId: userId, importIdentity: identity)
    }

    @Test("concurrent confirm with same token creates one debt and one created event")
    func concurrentSingleConfirmIdempotent() async throws {
        let (service, container, userId) = try await makeService()
        let scan = try await runScan(service, documents: docs(["bill"]), userId: userId)
        let candidate = scan.candidates[0]
        let token = UUID()
        let request = ConfirmDebtCandidateInput(
            reviewItemId: candidate.id,
            confirmationToken: token,
            candidate: candidate
        )

        async let first = service.confirm(requests: [request], userId: userId)
        async let second = service.confirm(requests: [request], userId: userId)
        let outcomes = await [first, second]

        #expect(outcomes[0].succeeded.count == 1)
        #expect(outcomes[1].succeeded.count == 1)
        #expect(outcomes[0].succeeded[0].debtId == outcomes[1].succeeded[0].debtId)

        let debts = try await container.debts.fetchAll(userId: userId)
        #expect(debts.count == 1)
        #expect(try await createdEventCount(container: container, debtId: debts[0].id) == 1)
    }

    @Test("partial batch stops after first failure and marks later candidates not attempted")
    func partialBatchSemantics() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Reliability"))
        let inner = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let documents = docs(["batch"])
        let candidates = threeCandidates(from: documents)
        let tokens = [UUID(), UUID(), UUID()]
        let service = DebtScannerService(
            scanner: MockAIProvider(debtScanBehavior: .custom(candidates)),
            debtService: FailOnTokenDebtManager(inner: inner, failTokens: [tokens[1]])
        )

        let requests = zip(candidates, tokens).map { candidate, token in
            ConfirmDebtCandidateInput(
                reviewItemId: candidate.id,
                confirmationToken: token,
                candidate: candidate
            )
        }
        let outcome = await service.confirm(requests: requests, userId: userId)

        #expect(outcome.succeeded.count == 1)
        #expect(outcome.failed.count == 1)
        #expect(outcome.notAttempted.count == 1)
        #expect(outcome.hasPartialSuccess)
        #expect(!outcome.isFullySuccessful)

        let debts = try await container.debts.fetchAll(userId: userId)
        #expect(debts.count == 1)
        #expect(debts[0].lender == "候选A")
    }

    @Test("retry after partial batch does not duplicate already-successful candidates")
    func retryPartialBatchNoDuplicate() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Reliability"))
        let inner = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let documents = docs(["retry"])
        let candidates = threeCandidates(from: documents)
        let tokens = [UUID(), UUID(), UUID()]
        let failingService = DebtScannerService(
            scanner: MockAIProvider(debtScanBehavior: .custom(candidates)),
            debtService: FailOnTokenDebtManager(inner: inner, failTokens: [tokens[1]])
        )

        let requests = zip(candidates, tokens).map { candidate, token in
            ConfirmDebtCandidateInput(
                reviewItemId: candidate.id,
                confirmationToken: token,
                candidate: candidate
            )
        }
        let first = await failingService.confirm(requests: requests, userId: userId)
        #expect(first.succeeded.count == 1)
        #expect(first.failed.count == 1)

        let retryService = DebtScannerService(
            scanner: MockAIProvider(debtScanBehavior: .custom(candidates)),
            debtService: inner
        )
        let second = await retryService.confirm(
            requests: [requests[0], requests[1]],
            userId: userId
        )
        #expect(second.succeeded.count == 2)
        #expect(try await container.debts.fetchAll(userId: userId).count == 2)

        let debtAId = first.succeeded[0].debtId!
        #expect(try await createdEventCount(container: container, debtId: debtAId) == 1)
    }

    @Test("concurrent confirm-all does not duplicate debts")
    func concurrentConfirmAllIdempotent() async throws {
        let (service, container, userId) = try await makeService()
        let scan = try await runScan(service, documents: docs(["a", "b"]), userId: userId)
        let tokens = scan.candidates.map { _ in UUID() }
        let requests = zip(scan.candidates, tokens).map { candidate, token in
            ConfirmDebtCandidateInput(
                reviewItemId: candidate.id,
                confirmationToken: token,
                candidate: candidate
            )
        }

        async let first = service.confirm(requests: requests, userId: userId)
        async let second = service.confirm(requests: requests, userId: userId)
        _ = await [first, second]

        #expect(try await container.debts.fetchAll(userId: userId).count == 2)
        for debt in try await container.debts.fetchAll(userId: userId) {
            #expect(try await createdEventCount(container: container, debtId: debt.id) == 1)
        }
    }

    @Test("invalid candidate is rejected before persistence")
    func invalidCandidateRejected() async throws {
        let (service, container, userId) = try await makeService()
        let invalid = DebtCandidate(
            lender: "",
            outstandingBalance: 100,
            currencyCode: "CNY",
            confidence: 0.5,
            sourceDocuments: ["x"]
        )
        let outcome = await service.confirm(
            requests: [
                ConfirmDebtCandidateInput(
                    reviewItemId: invalid.id,
                    confirmationToken: UUID(),
                    candidate: invalid
                ),
            ],
            userId: userId
        )

        #expect(outcome.failed.count == 1)
        #expect(try await container.debts.fetchAll(userId: userId).isEmpty)
    }

    @Test("partial debt missingness semantics remain intact after confirm")
    func partialDebtMissingnessRegression() async throws {
        let (service, container, userId) = try await makeService(
            scanner: MockAIProvider(debtScanBehavior: .currentDueOnly)
        )
        let scan = try await runScan(service, documents: docs(["due-only"]), userId: userId)
        let outcome = await service.confirm(candidates: scan.candidates, userId: userId)
        #expect(outcome.isFullySuccessful)

        let debt = try await container.debts.fetchAll(userId: userId)[0]
        #expect(debt.outstandingBalance == nil)
        #expect(debt.currentDue?.amount == Decimal(string: "2300"))
    }

    @Test("unknown due date remains nil after confirm")
    func unknownDueDateRegression() async throws {
        let (service, container, userId) = try await makeService(
            scanner: MockAIProvider(debtScanBehavior: .distinctAmountsNoInterest)
        )
        let scan = try await runScan(service, documents: docs(["no-due"]), userId: userId)
        let outcome = await service.confirm(candidates: scan.candidates, userId: userId)
        #expect(outcome.isFullySuccessful)

        let debt = try await container.debts.fetchAll(userId: userId)[0]
        #expect(debt.dueDate == nil)
    }
}
