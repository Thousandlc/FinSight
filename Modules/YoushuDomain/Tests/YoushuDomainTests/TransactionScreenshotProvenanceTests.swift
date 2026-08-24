import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Transaction screenshot provenance (ADR-036 Step D)")
struct TransactionScreenshotProvenanceTests {
    private let imageA = Data("provenance-image-a-bytes".utf8)
    private let imageB = Data("provenance-image-b-bytes".utf8)

    private final class CountingTransactionExtractor: TransactionExtracting, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var callCount = 0
        var name: String { "counting-mock" }

        func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
            lock.withLock { callCount += 1 }
            return try await MockAIProvider(behavior: .success).extractTransactionDraft(fromImageData: data)
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

        func removeConfirmedEntity(
            userId: UUID,
            reference: ConfirmedImportEntityReference
        ) async throws {
            try await base.removeConfirmedEntity(userId: userId, reference: reference)
        }

        func deleteAll(userId: UUID) async throws {
            try await base.deleteAll(userId: userId)
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

    private func makeService(
        extractor: any TransactionExtracting = MockAIProvider(behavior: .success),
        debtLinker: (any TransactionDebtLinking)? = nil,
        provenanceRepository: (any ConfirmedImportProvenanceRepository)? = nil,
        existing: (RepositoryContainer, UUID, Account)? = nil
    ) -> (ScreenshotBookkeepingService, RepositoryContainer, UUID, Account) {
        let container: RepositoryContainer
        let userId: UUID
        let account: Account
        if let existing {
            container = existing.0
            userId = existing.1
            account = existing.2
        } else {
            container = RepositoryContainer(store: YoushuStore())
            userId = UUID()
            account = Account(userId: userId, name: "现金", type: .cash)
        }
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions,
            debtLinker: debtLinker
        )
        let service = ScreenshotBookkeepingService(
            extractor: extractor,
            transactionService: txService,
            accounts: container.accounts,
            transactions: container.transactions,
            confirmedImportProvenances: provenanceRepository ?? container.confirmedImportProvenances
        )
        return (service, container, userId, account)
    }

    private func seed(
        container: RepositoryContainer,
        userId: UUID,
        account: Account
    ) async throws {
        try await container.users.upsert(User(id: userId, displayName: "Provenance"))
        try await container.accounts.upsert(account)
    }

    private func recognize(
        _ service: ScreenshotBookkeepingService,
        imageData: Data,
        userId: UUID
    ) async throws -> PendingScreenshotRecognition {
        let identity = TransactionScreenshotImportIdentity.from(imageData: imageData)
        return try await service.recognize(imageData: imageData, userId: userId, importIdentity: identity)
    }

    private func accept(
        _ service: ScreenshotBookkeepingService,
        imageData: Data,
        userId: UUID
    ) async throws -> ScreenshotRecognitionResult {
        let pending = try await recognize(service, imageData: imageData, userId: userId)
        return try await service.acceptRecognition(pending, userId: userId)
    }

    private func confirmInput(
        from result: ScreenshotRecognitionResult,
        accountId: UUID,
        token: UUID = UUID()
    ) -> ConfirmScreenshotTransactionInput {
        ConfirmScreenshotTransactionInput(
            amount: result.editableDraft.amount!,
            date: result.editableDraft.date ?? Date(),
            merchant: result.editableDraft.merchant,
            category: result.editableDraft.category ?? "交通",
            accountId: accountId,
            formType: .expense,
            recognitionConfidence: result.editableDraft.confidence,
            sourceImageId: result.sourceImageId,
            confirmationToken: token,
            importIdentity: result.importIdentity
        )
    }

    private func seedProvenance(
        imageData: Data,
        transactionId: UUID,
        userId: UUID,
        container: RepositoryContainer
    ) async throws {
        let identity = TransactionScreenshotImportIdentity.from(imageData: imageData)
        let provenance = try ConfirmedImportProvenance(
            userId: userId,
            capability: .transactionScreenshot,
            sourceFingerprints: [identity.sourceFingerprint],
            confirmedEntityReferences: [.transaction(transactionId)]
        )
        _ = try await container.confirmedImportProvenances.upsert(provenance)
    }

    private func seedProvenanceWithTransaction(
        imageData: Data,
        userId: UUID,
        account: Account,
        container: RepositoryContainer,
        transactionId: UUID = UUID()
    ) async throws -> UUID {
        let transaction = Transaction(
            id: transactionId,
            userId: userId,
            accountId: account.id,
            amount: Money(amount: Decimal(string: "36.50")!, currencyCode: "CNY"),
            date: Date(),
            merchant: "地铁出行",
            category: "交通",
            transactionType: .expense,
            source: .screenshot
        )
        try await container.transactions.upsert(transaction)
        try await seedProvenance(
            imageData: imageData,
            transactionId: transactionId,
            userId: userId,
            container: container
        )
        return transactionId
    }

    @Test("A: first import with no provenance proceeds to recognition")
    func firstImportNoWarning() async throws {
        let extractor = CountingTransactionExtractor()
        let (service, container, userId, account) = makeService(extractor: extractor)
        try await seed(container: container, userId: userId, account: account)

        let warning = try await service.checkPriorImport(imageData: imageA, userId: userId)
        #expect(warning == nil)

        _ = try await recognize(service, imageData: imageA, userId: userId)
        #expect(extractor.callCount == 1)
    }

    @Test("B: exact prior match warns and skips recognizer")
    func exactMatchWarnsBeforeRecognition() async throws {
        let extractor = CountingTransactionExtractor()
        let (service, container, userId, account) = makeService(extractor: extractor)
        try await seed(container: container, userId: userId, account: account)

        let transactionId = try await seedProvenanceWithTransaction(
            imageData: imageA,
            userId: userId,
            account: account,
            container: container
        )

        let warning = try await service.checkPriorImport(imageData: imageA, userId: userId)
        #expect(warning != nil)
        #expect(warning?.existingTransactions.count == 1)
        #expect(warning?.existingTransactions[0].id == transactionId)
        #expect(extractor.callCount == 0)
    }

    @Test("C: different image does not warn")
    func differentImageNoWarning() async throws {
        let extractor = CountingTransactionExtractor()
        let (service, container, userId, account) = makeService(extractor: extractor)
        try await seed(container: container, userId: userId, account: account)

        try await seedProvenanceWithTransaction(
            imageData: imageA,
            userId: userId,
            account: account,
            container: container
        )

        let warning = try await service.checkPriorImport(imageData: imageB, userId: userId)
        #expect(warning == nil)
        _ = try await recognize(service, imageData: imageB, userId: userId)
        #expect(extractor.callCount == 1)
    }

    @Test("F: first confirmed import writes one provenance row")
    func firstConfirmWritesProvenance() async throws {
        let (service, container, userId, account) = makeService()
        try await seed(container: container, userId: userId, account: account)

        let result = try await accept(service, imageData: imageA, userId: userId)
        let token = UUID()
        let outcome = try await service.confirm(
            confirmInput(from: result, accountId: account.id, token: token),
            userId: userId
        )

        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(rows[0].confirmedEntityReferences == [.transaction(outcome.transaction.id)])
        #expect(rows[0].sourceFingerprints == [result.importIdentity.sourceFingerprint])
    }

    @Test("G: explicit second import merges entity refs")
    func secondImportMergesRefs() async throws {
        let (service, container, userId, account) = makeService()
        try await seed(container: container, userId: userId, account: account)

        let firstResult = try await accept(service, imageData: imageA, userId: userId)
        let firstToken = UUID()
        let firstOutcome = try await service.confirm(
            confirmInput(from: firstResult, accountId: account.id, token: firstToken),
            userId: userId
        )

        let secondResult = try await accept(service, imageData: imageA, userId: userId)
        let secondToken = UUID()
        let secondOutcome = try await service.confirm(
            confirmInput(from: secondResult, accountId: account.id, token: secondToken),
            userId: userId
        )

        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(Set(rows[0].confirmedEntityReferences) == Set([
            .transaction(firstOutcome.transaction.id),
            .transaction(secondOutcome.transaction.id)
        ]))
    }

    @Test("H: same confirmation token remains idempotent for transaction and provenance ref")
    func sameTokenIdempotent() async throws {
        let (service, container, userId, account) = makeService()
        try await seed(container: container, userId: userId, account: account)

        let result = try await accept(service, imageData: imageA, userId: userId)
        let token = UUID()
        let input = confirmInput(from: result, accountId: account.id, token: token)
        _ = try await service.confirm(input, userId: userId)
        _ = try await service.confirm(input, userId: userId)

        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
        let rows = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(rows.count == 1)
        #expect(rows[0].confirmedEntityReferences.count == 1)
    }

    @Test("I: provenance failure after transaction persist is degraded only")
    func provenanceFailureDegraded() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash)
        try await seed(container: container, userId: userId, account: account)

        let throwingRepo = ThrowingProvenanceRepository(
            failUpsert: true,
            base: LocalConfirmedImportProvenanceRepository(store: store)
        )
        let (service, _, _, _) = makeService(
            provenanceRepository: throwingRepo,
            existing: (container, userId, account)
        )
        let result = try await accept(service, imageData: imageA, userId: userId)
        let outcome = try await service.confirm(
            confirmInput(from: result, accountId: account.id),
            userId: userId
        )

        #expect(outcome.transaction.amount.amount == Decimal(string: "36.50"))
        #expect(outcome.provenanceIssue != nil)
        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).isEmpty)
    }

    @Test("J: retry after provenance failure does not duplicate transaction")
    func retryAfterProvenanceFailure() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash)
        try await seed(container: container, userId: userId, account: account)

        let throwingRepo = ThrowingProvenanceRepository(
            failUpsert: true,
            base: LocalConfirmedImportProvenanceRepository(store: store)
        )
        let (service, _, _, _) = makeService(
            provenanceRepository: throwingRepo,
            existing: (container, userId, account)
        )
        let result = try await accept(service, imageData: imageA, userId: userId)
        let token = UUID()
        let input = confirmInput(from: result, accountId: account.id, token: token)

        _ = try await service.confirm(input, userId: userId)
        throwingRepo.failUpsert = false
        let retry = try await service.confirm(input, userId: userId)

        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
        #expect(retry.provenanceIssue == nil)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).count == 1)
    }

    @Test("K: debt linking and provenance failures are independent")
    func independentSecondaryOutcomes() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash)
        try await seed(container: container, userId: userId, account: account)

        let throwingRepo = ThrowingProvenanceRepository(
            failUpsert: true,
            base: LocalConfirmedImportProvenanceRepository(store: store)
        )
        let (service, _, _, _) = makeService(
            debtLinker: ThrowingDebtLinker(),
            provenanceRepository: throwingRepo,
            existing: (container, userId, account)
        )
        let result = try await accept(service, imageData: imageA, userId: userId)
        let outcome = try await service.confirm(
            confirmInput(from: result, accountId: account.id),
            userId: userId
        )

        #expect(outcome.transaction.amount.amount == Decimal(string: "36.50"))
        #expect(outcome.debtLinkingIssue != nil)
        #expect(outcome.provenanceIssue != nil)
        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
    }

    @Test("L: deleting final relation removes warning")
    func deleteFinalRelationRemovesWarning() async throws {
        let (service, container, userId, account) = makeService()
        try await seed(container: container, userId: userId, account: account)

        let result = try await accept(service, imageData: imageA, userId: userId)
        let outcome = try await service.confirm(
            confirmInput(from: result, accountId: account.id),
            userId: userId
        )

        try await container.transactions.delete(id: outcome.transaction.id)
        let warning = try await service.checkPriorImport(imageData: imageA, userId: userId)
        #expect(warning == nil)
    }

    @Test("M: deleting one of multiple refs keeps warning for remaining")
    func deleteOneOfMultipleRefs() async throws {
        let (service, container, userId, account) = makeService()
        try await seed(container: container, userId: userId, account: account)

        let first = try await accept(service, imageData: imageA, userId: userId)
        let firstOutcome = try await service.confirm(
            confirmInput(from: first, accountId: account.id, token: UUID()),
            userId: userId
        )
        let second = try await accept(service, imageData: imageA, userId: userId)
        _ = try await service.confirm(
            confirmInput(from: second, accountId: account.id, token: UUID()),
            userId: userId
        )

        try await container.transactions.delete(id: firstOutcome.transaction.id)
        let warning = try await service.checkPriorImport(imageData: imageA, userId: userId)
        #expect(warning?.existingTransactions.count == 1)
        #expect(warning?.existingTransactions[0].id != firstOutcome.transaction.id)
    }

    @Test("N: prior lookup does not require consent")
    func priorLookupNoConsent() async throws {
        let extractor = CountingTransactionExtractor()
        let (service, container, userId, account) = makeService(extractor: extractor)
        try await seed(container: container, userId: userId, account: account)
        try await seedProvenanceWithTransaction(
            imageData: imageA,
            userId: userId,
            account: account,
            container: container
        )

        _ = try await service.checkPriorImport(imageData: imageA, userId: userId)
        #expect(extractor.callCount == 0)
    }

    @Test("O: warning lookup uses operation fingerprint not sourceImageId")
    func fingerprintNotSourceImageId() async throws {
        let (service, container, userId, account) = makeService()
        try await seed(container: container, userId: userId, account: account)

        let transactionId = try await seedProvenanceWithTransaction(
            imageData: imageA,
            userId: userId,
            account: account,
            container: container
        )
        let identity = TransactionScreenshotImportIdentity.from(imageData: imageA)
        let wrongMediaId = MediaLifecyclePolicy.makeImageId(for: imageA)
        _ = transactionId

        let byFingerprint = try await service.checkPriorImport(imageData: imageA, userId: userId)
        #expect(byFingerprint != nil)
        #expect(byFingerprint?.importIdentity.operationFingerprint == identity.operationFingerprint)

        let mismatched = try await container.confirmedImportProvenances.find(
            userId: userId,
            capability: .transactionScreenshot,
            operationFingerprint: ImportOperationFingerprint(
                algorithm: .sha256V1,
                canonicalizationScheme: .canonicalV1Sha256,
                digestHex: wrongMediaId
            )
        )
        #expect(mismatched == nil)
        _ = wrongMediaId
    }
}
