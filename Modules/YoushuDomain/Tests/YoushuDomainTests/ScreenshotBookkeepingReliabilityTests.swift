import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Screenshot bookkeeping reliability")
struct ScreenshotBookkeepingReliabilityTests {
    private let sampleImage = Data("reliability-screenshot-bytes".utf8)

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
        debtLinker: (any TransactionDebtLinking)? = nil
    ) -> (ScreenshotBookkeepingService, RepositoryContainer, UUID, Account) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash)
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions,
            debtLinker: debtLinker
        )
        let service = ScreenshotBookkeepingService(
            extractor: MockAIProvider(behavior: .success),
            transactionService: txService,
            accounts: container.accounts,
            transactions: container.transactions,
            confirmedImportProvenances: container.confirmedImportProvenances
        )
        return (service, container, userId, account)
    }

    private func seed(
        container: RepositoryContainer,
        userId: UUID,
        account: Account
    ) async throws {
        try await container.users.upsert(User(id: userId, displayName: "Reliability"))
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

    @Test("transaction persists when post-persist debt linking fails")
    func persistSucceedsWhenLinkingFails() async throws {
        let (service, container, userId, account) = makeService(debtLinker: ThrowingDebtLinker())
        try await seed(container: container, userId: userId, account: account)

        let pending = try await recognize(service, imageData: sampleImage, userId: userId)
        let result = try await service.acceptRecognition(pending, userId: userId)
        let token = UUID()
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
                confirmationToken: token
            ),
            userId: userId
        )

        #expect(outcome.transaction.amount.amount == Decimal(string: "36.50"))
        #expect(outcome.debtLinkingIssue != nil)
        #expect(outcome.isFullySuccessful == false)

        let txs = try await container.transactions.fetchAll(userId: userId)
        #expect(txs.count == 1)
        #expect(txs[0].id == token)
    }

    @Test("retry with same confirmation token does not insert duplicate transaction")
    func retrySameTokenIsIdempotent() async throws {
        let (service, container, userId, account) = makeService(debtLinker: ThrowingDebtLinker())
        try await seed(container: container, userId: userId, account: account)

        let pending = try await recognize(service, imageData: sampleImage, userId: userId)
        let result = try await service.acceptRecognition(pending, userId: userId)
        let token = UUID()
        let input = ConfirmScreenshotTransactionInput(
            amount: result.editableDraft.amount!,
            date: result.editableDraft.date ?? Date(),
            merchant: result.editableDraft.merchant,
            category: result.editableDraft.category ?? "交通",
            accountId: account.id,
            formType: .expense,
            recognitionConfidence: result.editableDraft.confidence,
            sourceImageId: result.sourceImageId,
            confirmationToken: token
        )

        let first = try await service.confirm(input, userId: userId)
        let second = try await service.confirm(input, userId: userId)

        #expect(first.transaction.id == token)
        #expect(second.transaction.id == token)

        let txs = try await container.transactions.fetchAll(userId: userId)
        #expect(txs.count == 1)
    }

    @Test("invalid confirmation is still rejected before persistence")
    func invalidConfirmationRejected() async throws {
        let (service, container, userId, account) = makeService()
        try await seed(container: container, userId: userId, account: account)

        await #expect(throws: DomainError.self) {
            try await service.confirm(
                ConfirmScreenshotTransactionInput(
                    amount: 0,
                    date: Date(),
                    category: "餐饮",
                    accountId: account.id,
                    formType: .expense,
                    confirmationToken: UUID()
                ),
                userId: userId
            )
        }

        #expect(try await container.transactions.fetchAll(userId: userId).isEmpty)
    }

    @Test("record outcome separates primary persist from debt linking failure")
    func recordOutcomeSemantics() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash)
        try await container.users.upsert(User(id: userId, displayName: "Reliability"))
        try await container.accounts.upsert(account)

        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions,
            debtLinker: ThrowingDebtLinker()
        )
        let outcome = try await txService.record(
            RecordTransactionInput(
                amount: 100,
                category: "餐饮",
                accountId: account.id,
                formType: .expense
            ),
            userId: userId
        )

        #expect(outcome.transaction.amount.amount == 100)
        #expect(outcome.debtLinkingIssue != nil)
        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
    }
}
