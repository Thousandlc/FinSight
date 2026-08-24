import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Debt scan provenance (ADR-036 Step E)")
struct DebtScanProvenanceTests {
    private func doc(_ label: String) -> BillDocument {
        BillDocument(kind: .screenshot, data: Data(label.utf8), fileName: "\(label).png")
    }

    private func docs(_ labels: [String]) -> [BillDocument] {
        labels.map { doc($0) }
    }

    private final class CountingDebtScanner: DebtScanning, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var callCount = 0
        var name: String { "counting-debt-mock" }

        func scanDebts(from documents: [BillDocument]) async throws -> [DebtCandidate] {
            lock.withLock { callCount += 1 }
            return try await MockAIProvider(debtScanBehavior: .successMultiDebt).scanDebts(from: documents)
        }
    }

    private final class ThrowingProvenanceRepository: ConfirmedImportProvenanceRepository, @unchecked Sendable {
        var failUpsert = false
        let base: any ConfirmedImportProvenanceRepository

        init(failUpsert: Bool = false, base: any ConfirmedImportProvenanceRepository) {
            self.failUpsert = failUpsert
            self.base = base
        }

        func find(
            userId: UUID,
            capability: ConfirmedImportCapability,
            operationFingerprint: ImportOperationFingerprint
        ) async throws -> ConfirmedImportProvenance? {
            try await base.find(userId: userId, capability: capability, operationFingerprint: operationFingerprint)
        }

        func fetch(id: UUID) async throws -> ConfirmedImportProvenance? {
            try await base.fetch(id: id)
        }

        func fetchAll(userId: UUID) async throws -> [ConfirmedImportProvenance] {
            try await base.fetchAll(userId: userId)
        }

        func upsert(_ provenance: ConfirmedImportProvenance) async throws -> ConfirmedImportProvenance {
            if failUpsert {
                throw DataError.persistenceFailed("simulated provenance failure")
            }
            return try await base.upsert(provenance)
        }

        func removeConfirmedEntity(userId: UUID, reference: ConfirmedImportEntityReference) async throws {
            try await base.removeConfirmedEntity(userId: userId, reference: reference)
        }

        func deleteAll(userId: UUID) async throws {
            try await base.deleteAll(userId: userId)
        }
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

    private func makeService(
        scanner: any DebtScanning = MockAIProvider(debtScanBehavior: .successMultiDebt),
        debtManager: (any DebtManaging)? = nil,
        provenanceRepository: (any ConfirmedImportProvenanceRepository)? = nil,
        existing: (RepositoryContainer, UUID)? = nil
    ) async throws -> (DebtScannerService, RepositoryContainer, UUID) {
        let container: RepositoryContainer
        let userId: UUID
        if let existing {
            container = existing.0
            userId = existing.1
        } else {
            container = RepositoryContainer(store: YoushuStore())
            userId = UUID()
            try await container.users.upsert(User(id: userId, displayName: "Provenance"))
        }
        let debtService = debtManager ?? DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let service = DebtScannerService(
            scanner: scanner,
            debtService: debtService,
            debts: container.debts,
            confirmedImportProvenances: provenanceRepository ?? container.confirmedImportProvenances
        )
        return (service, container, userId)
    }

    private func scan(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> PendingDebtScanResult {
        let identity = DebtScanImportIdentity.from(documents: documents)
        return try await service.scan(documents: documents, userId: userId, importIdentity: identity)
    }

    private func accept(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> DebtScanResult {
        let pending = try await scan(service, documents: documents, userId: userId)
        return try await service.acceptScan(pending, userId: userId)
    }

    private func seedProvenance(
        documents: [BillDocument],
        debtIds: [UUID],
        userId: UUID,
        container: RepositoryContainer
    ) async throws {
        let identity = DebtScanImportIdentity.from(documents: documents)
        let provenance = try ConfirmedImportProvenance(
            userId: userId,
            capability: .debtScan,
            sourceFingerprints: identity.sourceFingerprints,
            confirmedEntityReferences: debtIds.map { .debt($0) }
        )
        _ = try await container.confirmedImportProvenances.upsert(provenance)
    }

    private func seedDebt(
        id: UUID,
        userId: UUID,
        lender: String,
        container: RepositoryContainer
    ) async throws {
        let debt = Debt(
            id: id,
            userId: userId,
            lender: lender,
            productName: "产品",
            debtType: .consumerLoan,
            outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
            source: .screenshot
        )
        try await container.debts.upsert(debt)
    }

    @Test("A: first batch with no provenance proceeds to scan")
    func firstBatchNoWarning() async throws {
        let scanner = CountingDebtScanner()
        let (service, _, userId) = try await makeService(scanner: scanner)
        let batch = docs(["A", "B"])
        let warning = try await service.checkPriorScan(documents: batch, userId: userId)
        #expect(warning == nil)
        _ = try await scan(service, documents: batch, userId: userId)
        #expect(scanner.callCount == 1)
    }

    @Test("B: exact prior batch warns and skips scanner")
    func exactBatchWarnsBeforeScan() async throws {
        let scanner = CountingDebtScanner()
        let (service, container, userId) = try await makeService(scanner: scanner)
        let batch = docs(["A", "B"])
        let debtId = UUID()
        try await seedDebt(id: debtId, userId: userId, lender: "测试银行", container: container)
        try await seedProvenance(documents: batch, debtIds: [debtId], userId: userId, container: container)

        let warning = try await service.checkPriorScan(documents: batch, userId: userId)
        #expect(warning != nil)
        #expect(warning?.existingDebts.count == 1)
        #expect(warning?.existingDebts[0].id == debtId)
        #expect(scanner.callCount == 0)
    }

    @Test("C: reordered batch matches prior provenance")
    func reorderedBatchMatches() async throws {
        let (service, container, userId) = try await makeService()
        let firstBatch = docs(["A", "B"])
        let debtId = UUID()
        try await seedDebt(id: debtId, userId: userId, lender: "测试银行", container: container)
        try await seedProvenance(documents: firstBatch, debtIds: [debtId], userId: userId, container: container)

        let warning = try await service.checkPriorScan(documents: docs(["B", "A"]), userId: userId)
        #expect(warning != nil)
        #expect(warning?.existingDebts[0].id == debtId)
    }

    @Test("D: multiplicity-sensitive mismatch")
    func multiplicityMismatch() async throws {
        let (service, container, userId) = try await makeService()
        let batchAB = docs(["A", "B"])
        let debtId = UUID()
        try await seedDebt(id: debtId, userId: userId, lender: "测试银行", container: container)
        try await seedProvenance(documents: batchAB, debtIds: [debtId], userId: userId, container: container)

        let warning = try await service.checkPriorScan(documents: docs(["A", "A", "B"]), userId: userId)
        #expect(warning == nil)
    }

    @Test("E: different batch does not warn")
    func differentBatchNoWarning() async throws {
        let (service, container, userId) = try await makeService()
        let debtId = UUID()
        try await seedDebt(id: debtId, userId: userId, lender: "测试银行", container: container)
        try await seedProvenance(documents: docs(["A", "B"]), debtIds: [debtId], userId: userId, container: container)

        let warning = try await service.checkPriorScan(documents: docs(["A", "C"]), userId: userId)
        #expect(warning == nil)
    }

    @Test("H: first successful confirm writes one provenance row")
    func firstConfirmWritesProvenance() async throws {
        let (service, container, userId) = try await makeService()
        let batch = docs(["scan-x"])
        let result = try await accept(service, documents: batch, userId: userId)
        let candidate = result.candidates[0]
        let token = UUID()
        let outcome = await service.confirm(
            requests: [
                ConfirmDebtCandidateInput(
                    reviewItemId: candidate.id,
                    confirmationToken: token,
                    candidate: candidate
                )
            ],
            userId: userId,
            importIdentity: result.importIdentity
        )

        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(rows[0].confirmedEntityReferences == [.debt(outcome.succeeded[0].debtId!)])
        #expect(rows[0].sourceFingerprints == result.importIdentity.sourceFingerprints)
    }

    @Test("I: multiple successes merge into one row")
    func multipleSuccessesMerge() async throws {
        let (service, container, userId) = try await makeService()
        let batch = docs(["multi"])
        let result = try await accept(service, documents: batch, userId: userId)
        let outcome = await service.confirm(
            candidates: result.candidates,
            userId: userId,
            importIdentity: result.importIdentity
        )

        #expect(outcome.succeeded.count == 2)
        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(Set(rows[0].confirmedEntityReferences).count == 2)
    }

    @Test("J: partial confirmation records only successful debts")
    func partialConfirmationProvenance() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Partial"))
        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let failToken = UUID()
        let (service, _, _) = try await makeService(
            debtManager: FailOnTokenDebtManager(inner: debtService, failTokens: [failToken]),
            existing: (container, userId)
        )
        let batch = docs(["partial"])
        let scanResult = try await scan(service, documents: batch, userId: userId)
        let candidates = threeCandidates(from: batch)
        let requests = candidates.enumerated().map { index, candidate in
            ConfirmDebtCandidateInput(
                reviewItemId: candidate.id,
                confirmationToken: index == 1 ? failToken : UUID(),
                candidate: candidate
            )
        }
        _ = scanResult
        let identity = DebtScanImportIdentity.from(documents: batch)
        let outcome = await service.confirm(
            requests: requests,
            userId: userId,
            importIdentity: identity
        )

        #expect(outcome.succeeded.count == 1)
        #expect(outcome.failed.count == 1)
        #expect(outcome.notAttempted.count == 1)
        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(rows[0].confirmedEntityReferences.count == 1)
    }

    @Test("K: retry extends same provenance row")
    func retryExtendsProvenance() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Retry"))
        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let failToken = UUID()
        let manager = FailOnTokenDebtManager(inner: debtService, failTokens: [failToken])
        let (service, _, _) = try await makeService(debtManager: manager, existing: (container, userId))

        let batch = docs(["retry"])
        let identity = DebtScanImportIdentity.from(documents: batch)
        let candidates = threeCandidates(from: batch)
        let firstRequests = [
            ConfirmDebtCandidateInput(
                reviewItemId: candidates[0].id,
                confirmationToken: UUID(),
                candidate: candidates[0]
            ),
            ConfirmDebtCandidateInput(
                reviewItemId: candidates[1].id,
                confirmationToken: failToken,
                candidate: candidates[1]
            ),
        ]
        let first = await service.confirm(
            requests: firstRequests,
            userId: userId,
            importIdentity: identity
        )
        let d1 = first.succeeded[0].debtId!

        let second = await service.confirm(
            requests: [
                ConfirmDebtCandidateInput(
                    reviewItemId: candidates[1].id,
                    confirmationToken: UUID(),
                    candidate: candidates[1]
                )
            ],
            userId: userId,
            importIdentity: identity,
            cumulativeConfirmedDebtIds: [d1]
        )
        #expect(second.succeeded.count == 1)
        let d2 = second.succeeded[0].debtId!

        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(Set(rows[0].confirmedEntityReferences) == Set([.debt(d1), .debt(d2)]))
    }

    @Test("L: provenance failure after debt persist is degraded only")
    func provenanceFailureDegraded() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Degraded"))
        let throwingRepo = ThrowingProvenanceRepository(
            failUpsert: true,
            base: LocalConfirmedImportProvenanceRepository(store: store)
        )
        let (service, _, _) = try await makeService(
            provenanceRepository: throwingRepo,
            existing: (container, userId)
        )
        let batch = docs(["degraded"])
        let result = try await accept(service, documents: batch, userId: userId)
        let candidate = result.candidates[0]
        let outcome = await service.confirm(
            requests: [
                ConfirmDebtCandidateInput(
                    reviewItemId: candidate.id,
                    confirmationToken: UUID(),
                    candidate: candidate
                )
            ],
            userId: userId,
            importIdentity: result.importIdentity
        )

        #expect(outcome.succeeded.count == 1)
        #expect(outcome.provenanceIssue != nil)
        #expect(try await container.debts.fetchAll(userId: userId).count == 1)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).isEmpty)
    }

    @Test("M: cumulative provenance repair on later success")
    func cumulativeProvenanceRepair() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Repair"))
        let throwingRepo = ThrowingProvenanceRepository(
            failUpsert: true,
            base: LocalConfirmedImportProvenanceRepository(store: store)
        )
        let (service, _, _) = try await makeService(
            provenanceRepository: throwingRepo,
            existing: (container, userId)
        )
        let batch = docs(["repair"])
        let identity = DebtScanImportIdentity.from(documents: batch)
        let candidates = threeCandidates(from: batch)
        let d1Token = UUID()
        let first = await service.confirm(
            requests: [
                ConfirmDebtCandidateInput(
                    reviewItemId: candidates[0].id,
                    confirmationToken: d1Token,
                    candidate: candidates[0]
                )
            ],
            userId: userId,
            importIdentity: identity
        )
        let d1 = first.succeeded[0].debtId!
        #expect(first.provenanceIssue != nil)

        throwingRepo.failUpsert = false
        let second = await service.confirm(
            requests: [
                ConfirmDebtCandidateInput(
                    reviewItemId: candidates[1].id,
                    confirmationToken: UUID(),
                    candidate: candidates[1]
                )
            ],
            userId: userId,
            importIdentity: identity,
            cumulativeConfirmedDebtIds: [d1]
        )
        let d2 = second.succeeded[0].debtId!

        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(Set(rows[0].confirmedEntityReferences) == Set([.debt(d1), .debt(d2)]))
        #expect(second.provenanceIssue == nil)
    }

    @Test("N: same candidate confirm remains idempotent")
    func sameCandidateIdempotent() async throws {
        let (service, container, userId) = try await makeService()
        let batch = docs(["idem"])
        let result = try await accept(service, documents: batch, userId: userId)
        let candidate = result.candidates[0]
        let token = UUID()
        let request = ConfirmDebtCandidateInput(
            reviewItemId: candidate.id,
            confirmationToken: token,
            candidate: candidate
        )
        _ = await service.confirm(
            requests: [request],
            userId: userId,
            importIdentity: result.importIdentity
        )
        _ = await service.confirm(
            requests: [request],
            userId: userId,
            importIdentity: result.importIdentity,
            cumulativeConfirmedDebtIds: []
        )

        #expect(try await container.debts.fetchAll(userId: userId).count == 1)
        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(rows[0].confirmedEntityReferences.count == 1)
    }

    @Test("P: delete final relation removes prior-scan warning")
    func deleteFinalRelation() async throws {
        let (service, container, userId) = try await makeService()
        let batch = docs(["delete-final"])
        let result = try await accept(service, documents: batch, userId: userId)
        let candidate = result.candidates[0]
        let outcome = await service.confirm(
            requests: [
                ConfirmDebtCandidateInput(
                    reviewItemId: candidate.id,
                    confirmationToken: UUID(),
                    candidate: candidate
                )
            ],
            userId: userId,
            importIdentity: result.importIdentity
        )
        let debtId = outcome.succeeded[0].debtId!
        try await container.debts.delete(id: debtId)

        let warning = try await service.checkPriorScan(documents: batch, userId: userId)
        #expect(warning == nil)
    }

    @Test("Q: delete one of multiple refs keeps warning")
    func deleteOneOfMultiple() async throws {
        let (service, container, userId) = try await makeService()
        let batch = docs(["delete-partial"])
        let result = try await accept(service, documents: batch, userId: userId)
        let outcome = await service.confirm(
            candidates: result.candidates,
            userId: userId,
            importIdentity: result.importIdentity
        )
        let ids = outcome.succeeded.compactMap(\.debtId)
        #expect(ids.count == 2)
        try await container.debts.delete(id: ids[0])

        let warning = try await service.checkPriorScan(documents: batch, userId: userId)
        #expect(warning?.existingDebts.count == 1)
        #expect(warning?.existingDebts[0].id == ids[1])
    }

    @Test("R: prior lookup does not require consent")
    func priorLookupNoConsent() async throws {
        let scanner = CountingDebtScanner()
        let (service, container, userId) = try await makeService(scanner: scanner)
        let batch = docs(["A", "B"])
        let debtId = UUID()
        try await seedDebt(id: debtId, userId: userId, lender: "测试银行", container: container)
        try await seedProvenance(documents: batch, debtIds: [debtId], userId: userId, container: container)

        _ = try await service.checkPriorScan(documents: batch, userId: userId)
        #expect(scanner.callCount == 0)
    }

    @Test("multiplicity identity regression")
    func multiplicityIdentityRegression() async throws {
        let identityAB = DebtScanImportIdentity.from(documents: docs(["A", "B"]))
        let identityAAB = DebtScanImportIdentity.from(documents: docs(["A", "A", "B"]))
        #expect(identityAB.operationFingerprint != identityAAB.operationFingerprint)
        #expect(identityAB.sourceFingerprints.count == 2)
        #expect(identityAAB.sourceFingerprints.count == 3)
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
}
