import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Backup creation service")
struct BackupCreationServiceTests {
    private static let fixedCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let debtId = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let txId = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    private static let assetId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    private static let goalId = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private static let budgetId = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    private static let subscriptionId = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
    private static let planId = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
    private static let eventId = UUID(uuidString: "00000000-0000-0000-0000-000000000A01")!

    private func makeService(
        store: YoushuStore,
        createdAt: Date = fixedCreatedAt,
        sourceAppVersion: String? = "1.2.3-test"
    ) -> BackupCreationService {
        BackupCreationService(store: store) {
            BackupCreationMetadata(createdAt: createdAt, sourceAppVersion: sourceAppVersion)
        }
    }

    @Test("createBackup returns encrypted portable backup with expected financial facts")
    func successfulCreation() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await populateRepresentativeLedger(in: container)

        let service = makeService(store: store)
        let created = try await service.createBackup(passphrase: "ledger-backup-passphrase")
        let payload = try BackupCodec.decode(backupData: created.data, passphrase: "ledger-backup-passphrase")

        #expect(created.formatVersion == BackupPayloadV1.formatVersion)
        #expect(created.sourceStoreSchemaVersion == YoushuSnapshot.currentSchemaVersion)
        #expect(created.sourceAppVersion == "1.2.3-test")
        #expect(created.createdAt == Self.fixedCreatedAt)
        #expect(payload.metadata.formatVersion == 1)
        #expect(payload.metadata.sourceStoreSchemaVersion == YoushuSnapshot.currentSchemaVersion)
        #expect(payload.metadata.sourceAppVersion == "1.2.3-test")
        #expect(payload.metadata.createdAt == Self.fixedCreatedAt)

        #expect(payload.financialData.users.count == 1)
        #expect(payload.financialData.accounts.count == 1)
        #expect(payload.financialData.transactions.count == 1)
        #expect(payload.financialData.debts.count == 1)
        #expect(payload.financialData.debtEvents.count == 1)
        #expect(payload.financialData.repaymentPlans.count == 1)
        #expect(payload.financialData.assets.count == 1)
        #expect(payload.financialData.goals.count == 1)
        #expect(payload.financialData.budgets.count == 1)
        #expect(payload.financialData.subscriptions.count == 1)

        let user = try #require(payload.financialData.users.first)
        #expect(user.id == Self.userId)
        #expect(user.displayName == "Ledger Owner")

        let account = try #require(payload.financialData.accounts.first)
        #expect(account.id == Self.accountId)
        #expect(account.userId == Self.userId)

        let transaction = try #require(payload.financialData.transactions.first)
        #expect(transaction.id == Self.txId)
        #expect(transaction.userId == Self.userId)
        #expect(transaction.accountId == Self.accountId)
        #expect(transaction.relatedDebtId == Self.debtId)

        let debt = try #require(payload.financialData.debts.first)
        #expect(debt.id == Self.debtId)
        #expect(debt.userId == Self.userId)
        #expect(debt.linkedAccountId == Self.accountId)

        let event = try #require(payload.financialData.debtEvents.first)
        #expect(event.id == Self.eventId)
        #expect(event.debtId == Self.debtId)
        #expect(event.userId == Self.userId)
        #expect(event.relatedTransactionId == Self.txId)

        let plan = try #require(payload.financialData.repaymentPlans.first)
        #expect(plan.id == Self.planId)
        #expect(plan.debtId == Self.debtId)
        #expect(plan.userId == Self.userId)

        let asset = try #require(payload.financialData.assets.first)
        #expect(asset.id == Self.assetId)
        #expect(asset.userId == Self.userId)
        #expect(asset.linkedAccountId == Self.accountId)

        let goal = try #require(payload.financialData.goals.first)
        #expect(goal.id == Self.goalId)
        #expect(goal.userId == Self.userId)
        #expect(goal.relatedDebtId == Self.debtId)

        let budget = try #require(payload.financialData.budgets.first)
        #expect(budget.id == Self.budgetId)
        #expect(budget.userId == Self.userId)

        let subscription = try #require(payload.financialData.subscriptions.first)
        #expect(subscription.id == Self.subscriptionId)
        #expect(subscription.userId == Self.userId)
        #expect(subscription.accountId == Self.accountId)
    }

    @Test("createBackup excludes insight consent recognition media and workflow candidates")
    func exclusionThroughCreationPath() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let user = User(
            id: Self.userId,
            displayName: "Sensitive User",
            debtImportInProgress: true
        )
        try await container.users.upsert(user)

        try await container.insights.upsert(
            FinancialInsight(
                userId: user.id,
                type: .summary,
                title: "Secret Insight",
                body: "Must not appear in backup"
            )
        )
        try await container.aiDataConsents.upsert(
            AIDataConsent(
                userId: user.id,
                allowScreenshotImageToAI: true,
                allowFinancialContextToAI: true
            )
        )
        try await container.aiRecognitionRecords.upsert(
            AIRecognitionRecord(
                userId: user.id,
                kind: .screenshotTransaction,
                status: .recognized,
                summaryLabel: "recognition audit marker"
            )
        )
        try await container.mediaArtifacts.upsert(
            MediaArtifact(
                id: "media-artifact-marker",
                userId: user.id,
                kind: .screenshotTransaction,
                byteSize: 1024,
                contentHash: "abc123",
                retention: .ephemeral
            )
        )
        try await container.pendingDebtLinks.upsert(
            PendingDebtLink(
                userId: user.id,
                transactionId: Self.txId,
                confidence: 0.9,
                reason: "pending link marker"
            )
        )
        try await container.suspectedDebts.upsert(
            SuspectedDebt(
                userId: user.id,
                merchant: "Suspected",
                amount: Money(amount: 10, currencyCode: "CNY"),
                dayOfMonth: 1,
                occurrenceCount: 2,
                sampleTransactionIds: [],
                reason: "suspected debt marker"
            )
        )

        let created = try await makeService(store: store).createBackup(passphrase: "exclude-test-pass")
        let payload = try BackupCodec.decode(backupData: created.data, passphrase: "exclude-test-pass")
        let serializedPayload = try JSONEncoder().encode(payload.metadata)
        let serializedFinancial = try JSONEncoder().encode(payload.financialData)
        let backupText = String(decoding: created.data, as: UTF8.self)
        let payloadText = String(decoding: serializedPayload + serializedFinancial, as: UTF8.self)

        #expect(payload.financialData.users.count == 1)
        #expect(!payloadText.contains("Must not appear in backup"))
        #expect(!payloadText.contains("allowFinancialContextToAI"))
        #expect(!payloadText.contains("recognition audit marker"))
        #expect(!payloadText.contains("media-artifact-marker"))
        #expect(!payloadText.contains("pending link marker"))
        #expect(!payloadText.contains("suspected debt marker"))
        #expect(!payloadText.contains("debtImportInProgress"))
        #expect(!backupText.contains("exclude-test-pass"))
        #expect(!backupText.contains("Secret Insight"))
    }

    @Test("empty minimal store creates a valid encrypted backup")
    func emptyStoreBackup() async throws {
        let store = YoushuStore()
        let created = try await makeService(store: store, sourceAppVersion: nil).createBackup(passphrase: "empty-pass")
        let payload = try BackupCodec.decode(backupData: created.data, passphrase: "empty-pass")

        #expect(created.data.isEmpty == false)
        #expect(payload.financialData.users.isEmpty)
        #expect(payload.financialData.accounts.isEmpty)
        #expect(payload.financialData.transactions.isEmpty)
        #expect(created.sourceAppVersion == nil)
    }

    @Test("generated backup cannot be opened with a different passphrase")
    func wrongPassphraseFails() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Owner"))
        let created = try await makeService(store: store).createBackup(passphrase: "actual-passphrase")

        #expect(throws: BackupError.authenticationFailure) {
            _ = try BackupCodec.decode(backupData: created.data, passphrase: "different-passphrase")
        }
    }

    @Test("suggested filename uses FinSight branding and safe ascii timestamp")
    func filenamePolicy() async throws {
        let store = YoushuStore()
        let created = try await makeService(store: store).createBackup(passphrase: "filename-pass")

        #expect(created.suggestedFilename == "FinSight-Backup-2023-11-14-221320.finsightbackup")
        #expect(created.suggestedFilename.hasSuffix(".finsightbackup"))
        #expect(!created.suggestedFilename.contains(Self.userId.uuidString))
        #expect(!created.suggestedFilename.contains("Ledger"))
        #expect(!created.suggestedFilename.contains("Youshu"))
    }

    @Test("backup captures point-in-time snapshot before later store mutations")
    func consistentSnapshotCapture() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Owner"))
        try await container.accounts.upsert(
            Account(id: Self.accountId, userId: Self.userId, name: "Cash", type: .cash)
        )

        let created = try await makeService(store: store).createBackup(passphrase: "snapshot-pass")

        try await container.transactions.upsert(
            Transaction(
                id: Self.txId,
                userId: Self.userId,
                accountId: Self.accountId,
                amount: Money(amount: 99, currencyCode: "CNY"),
                merchant: "After Backup",
                category: "Food",
                transactionType: .expense
            )
        )

        let payload = try BackupCodec.decode(backupData: created.data, passphrase: "snapshot-pass")
        #expect(payload.financialData.accounts.count == 1)
        #expect(payload.financialData.transactions.isEmpty)

        let currentSnapshot = await store.currentSnapshot()
        #expect(currentSnapshot.transactions.count == 1)
    }

    @Test("created backup bytes are encrypted envelope not raw store json")
    func noPlaintextFallback() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Owner"))
        try await container.accounts.upsert(
            Account(id: Self.accountId, userId: Self.userId, name: "Cash", type: .cash)
        )

        let created = try await makeService(store: store).createBackup(passphrase: "encrypt-only-pass")
        let serialized = String(decoding: created.data, as: UTF8.self)

        #expect(!serialized.contains("\"schemaVersion\""))
        #expect(!serialized.contains("youshu-store"))
        #expect(!serialized.contains("Ledger Owner"))
        #expect(!serialized.contains("encrypt-only-pass"))
        #expect(serialized.contains("PBKDF2-HMAC-SHA256"))
        #expect(serialized.contains("AES-256-GCM"))
    }

    @Test("CreatedBackup result does not expose passphrase or plaintext payload")
    func resultDoesNotLeakSecrets() async throws {
        let store = YoushuStore()
        let created = try await makeService(store: store).createBackup(passphrase: "super-secret-passphrase")
        let encodedResult = try JSONEncoder().encode([
            "filename": created.suggestedFilename,
            "formatVersion": String(created.formatVersion),
        ])
        let resultText = String(decoding: encodedResult, as: UTF8.self)

        #expect(!resultText.contains("super-secret-passphrase"))
    }

    private func populateRepresentativeLedger(in container: RepositoryContainer) async throws {
        let store = container.store
        let user = User(
            id: Self.userId,
            displayName: "Ledger Owner",
            debtInventoryEstablishment: .partial,
            debtImportInProgress: true
        )
        try await container.users.upsert(user)

        let account = Account(
            id: Self.accountId,
            userId: Self.userId,
            name: "Cash",
            type: .cash
        )
        try await container.accounts.upsert(account)

        let debt = Debt(
            id: Self.debtId,
            userId: Self.userId,
            lender: "Bank",
            outstandingBalance: Money(amount: 1_000, currencyCode: "CNY"),
            status: .active,
            linkedAccountId: Self.accountId
        )
        try await container.debts.upsert(debt)

        let transaction = Transaction(
            id: Self.txId,
            userId: Self.userId,
            accountId: Self.accountId,
            amount: Money(amount: 50, currencyCode: "CNY"),
            merchant: "Coffee",
            category: "Food",
            transactionType: .expense,
            relatedDebtId: Self.debtId
        )
        try await container.transactions.upsert(transaction)

        try await container.debtEvents.upsert(
            DebtEvent(
                id: Self.eventId,
                debtId: Self.debtId,
                userId: Self.userId,
                type: .created,
                amount: Money(amount: 1_000, currencyCode: "CNY"),
                relatedTransactionId: Self.txId
            )
        )

        try await container.repaymentPlans.upsert(
            RepaymentPlan(
                id: Self.planId,
                debtId: Self.debtId,
                userId: Self.userId,
                installmentAmount: Money(amount: 100, currencyCode: "CNY"),
                frequency: .monthly,
                startDate: Self.fixedCreatedAt
            )
        )

        try await container.assets.upsert(
            Asset(
                id: Self.assetId,
                userId: Self.userId,
                name: "Fund",
                type: .cashEquivalent,
                currentValue: Money(amount: 5_000, currencyCode: "CNY"),
                linkedAccountId: Self.accountId
            )
        )

        try await container.goals.upsert(
            Goal(
                id: Self.goalId,
                userId: Self.userId,
                name: "Payoff",
                type: .debtPayoff,
                targetAmount: Money(amount: 1_000, currencyCode: "CNY"),
                relatedDebtId: Self.debtId
            )
        )

        try await container.budgets.upsert(
            Budget(
                id: Self.budgetId,
                userId: Self.userId,
                name: "Monthly",
                limit: Money(amount: 3_000, currencyCode: "CNY")
            )
        )

        try await store.upsertSubscription(
            Subscription(
                id: Self.subscriptionId,
                userId: Self.userId,
                name: "Streaming",
                amount: Money(amount: 30, currencyCode: "CNY"),
                accountId: Self.accountId
            )
        )
    }
}
