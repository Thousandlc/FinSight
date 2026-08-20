import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Backup payload v1")
struct BackupPayloadV1Tests {
    @Test("mapper excludes insights, consent and detector candidates from portable payload")
    func mapperExcludesNonFinancialData() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let user = User(displayName: "Backup User", debtImportInProgress: true)
        let account = Account(userId: user.id, name: "Cash", type: .cash)
        try await container.users.upsert(user)
        try await container.accounts.upsert(account)

        let tx = Transaction(
            userId: user.id,
            accountId: account.id,
            amount: Money(amount: 100, currencyCode: "CNY"),
            merchant: "Test",
            category: "Food",
            transactionType: .expense
        )
        try await container.transactions.upsert(tx)

        let debt = Debt(
            userId: user.id,
            lender: "Bank",
            outstandingBalance: Money(amount: 1_000, currencyCode: "CNY"),
            status: .active
        )
        try await container.debts.upsert(debt)

        let insight = FinancialInsight(
            userId: user.id,
            type: .summary,
            title: "AI Summary",
            body: "Should not backup",
            modelName: "mock"
        )
        try await container.insights.upsert(insight)

        try await container.aiDataConsents.upsert(
            AIDataConsent(
                userId: user.id,
                allowScreenshotImageToAI: true,
                allowFinancialContextToAI: true
            )
        )

        try await container.pendingDebtLinks.upsert(
            PendingDebtLink(
                userId: user.id,
                transactionId: tx.id,
                suggestedDebtId: debt.id,
                confidence: 0.9,
                reason: "workflow state"
            )
        )

        try await container.suspectedDebts.upsert(
            SuspectedDebt(
                userId: user.id,
                merchant: "Test",
                amount: Money(amount: 100, currencyCode: "CNY"),
                dayOfMonth: 5,
                occurrenceCount: 3,
                sampleTransactionIds: [tx.id],
                reason: "detector candidate"
            )
        )

        let snapshot = await store.currentSnapshot()
        #expect(snapshot.insights.count == 1)
        #expect(snapshot.aiDataConsents.count == 1)
        #expect(snapshot.pendingDebtLinks.count == 1)
        #expect(snapshot.suspectedDebts.count == 1)

        let payload = BackupSnapshotMapper.makePayload(from: snapshot, sourceAppVersion: "test")

        #expect(payload.metadata.formatVersion == BackupPayloadV1.formatVersion)
        #expect(payload.metadata.sourceStoreSchemaVersion == YoushuSnapshot.currentSchemaVersion)
        #expect(payload.financialData.users.count == 1)
        #expect(payload.financialData.accounts.count == 1)
        #expect(payload.financialData.transactions.count == 1)
        #expect(payload.financialData.debts.count == 1)
        #expect(payload.metadata.sourceAppVersion == "test")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let serialized = try String(decoding: encoder.encode(payload), as: UTF8.self)

        #expect(!serialized.contains("Should not backup"))
        #expect(!serialized.contains("allowFinancialContextToAI"))
        #expect(!serialized.contains("allowScreenshotImageToAI"))
        #expect(!serialized.contains("workflow state"))
        #expect(!serialized.contains("detector candidate"))
        #expect(!serialized.contains("debtImportInProgress"))
    }

    @Test("backup user representation carries no consent, secret or transient state")
    func backupUserRepresentationIsMinimal() throws {
        let user = User(
            displayName: "Ledger Owner",
            debtInventoryEstablishment: .confirmedComplete,
            debtInventoryEstablishmentSource: .userConfirmedNoDebt,
            debtInventoryEstablishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            debtImportInProgress: true
        )
        let snapshot = YoushuSnapshot(users: [user])
        let payload = BackupSnapshotMapper.makePayload(from: snapshot)

        let backupUser = try #require(payload.financialData.users.first)
        #expect(backupUser.id == user.id)
        #expect(backupUser.displayName == user.displayName)
        #expect(backupUser.preferredCurrency == user.preferredCurrency)
        #expect(backupUser.debtInventoryEstablishment == .confirmedComplete)
        #expect(backupUser.debtInventoryEstablishmentSource == .userConfirmedNoDebt)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let keys = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(backupUser)) as? [String: Any]
        ).keys.sorted()

        #expect(keys == [
            "createdAt",
            "debtInventoryEstablishedAt",
            "debtInventoryEstablishment",
            "debtInventoryEstablishmentSource",
            "displayName",
            "id",
            "preferredCurrency",
            "updatedAt",
        ])
    }

    @Test("payload JSON round trip preserves financial facts and relationships")
    func payloadRoundTrip() throws {
        let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let debtId = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let txId = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!

        let payload = BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                sourceStoreSchemaVersion: 4,
                sourceAppVersion: "1.0-test"
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: userId,
                        displayName: "Ledger",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .partial,
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ],
                accounts: [Account(id: accountId, userId: userId, name: "Cash", type: .cash)],
                transactions: [
                    Transaction(
                        id: txId,
                        userId: userId,
                        accountId: accountId,
                        amount: Money(amount: 50, currencyCode: "CNY"),
                        merchant: "Coffee",
                        category: "Food",
                        transactionType: .expense,
                        relatedDebtId: debtId
                    ),
                ],
                debts: [
                    Debt(
                        id: debtId,
                        userId: userId,
                        lender: "Card",
                        outstandingBalance: Money(amount: 500, currencyCode: "CNY"),
                        status: .active
                    ),
                ],
                debtEvents: [
                    DebtEvent(
                        debtId: debtId,
                        userId: userId,
                        type: .created,
                        amount: Money(amount: 500, currencyCode: "CNY"),
                        relatedTransactionId: txId
                    ),
                ],
                repaymentPlans: [
                    RepaymentPlan(
                        debtId: debtId,
                        userId: userId,
                        installmentAmount: Money(amount: 100, currencyCode: "CNY"),
                        frequency: .monthly,
                        startDate: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ]
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(BackupPayloadV1.self, from: data)

        #expect(decoded.metadata.formatVersion == 1)
        #expect(decoded.metadata.sourceStoreSchemaVersion == 4)
        #expect(decoded.financialData.users.first?.id == userId)
        #expect(decoded.financialData.accounts.first?.userId == userId)
        #expect(decoded.financialData.transactions.first?.relatedDebtId == debtId)
        #expect(decoded.financialData.transactions.first?.accountId == accountId)
        #expect(decoded.financialData.debtEvents.first?.relatedTransactionId == txId)
        #expect(decoded.financialData.repaymentPlans.first?.debtId == debtId)
    }
}
