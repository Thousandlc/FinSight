import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Backup restore preflight service")
struct BackupRestorePreflightServiceTests {
    private static let fixedCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let otherUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private static let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let otherAccountId = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private static let debtId = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let txId = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    private static let assetId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    private static let goalId = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private static let budgetId = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    private static let subscriptionId = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
    private static let planId = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
    private static let eventId = UUID(uuidString: "00000000-0000-0000-0000-000000000A01")!

    private let preflight = BackupRestorePreflightService()

    private func makeCreationService(
        store: YoushuStore,
        createdAt: Date = fixedCreatedAt,
        sourceAppVersion: String? = "1.2.3-test"
    ) -> BackupCreationService {
        BackupCreationService(store: store) {
            BackupCreationMetadata(createdAt: createdAt, sourceAppVersion: sourceAppVersion)
        }
    }

    private func encodeBackup(_ payload: BackupPayloadV1, passphrase: String = "test-passphrase") throws -> Data {
        try BackupCodec.encode(payload: payload, passphrase: passphrase)
    }

    private func representativePayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Self.fixedCreatedAt,
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion,
                sourceAppVersion: "1.2.3-test"
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: Self.userId,
                        displayName: "Ledger Owner",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .partial,
                        createdAt: Self.fixedCreatedAt,
                        updatedAt: Self.fixedCreatedAt
                    ),
                ],
                accounts: [
                    Account(id: Self.accountId, userId: Self.userId, name: "Cash", type: .cash),
                ],
                transactions: [
                    Transaction(
                        id: Self.txId,
                        userId: Self.userId,
                        accountId: Self.accountId,
                        amount: Money(amount: 50, currencyCode: "CNY"),
                        merchant: "Coffee",
                        category: "Food",
                        transactionType: .expense,
                        relatedDebtId: Self.debtId
                    ),
                ],
                assets: [
                    Asset(
                        id: Self.assetId,
                        userId: Self.userId,
                        name: "Fund",
                        type: .cashEquivalent,
                        currentValue: Money(amount: 5_000, currencyCode: "CNY"),
                        linkedAccountId: Self.accountId
                    ),
                ],
                debts: [
                    Debt(
                        id: Self.debtId,
                        userId: Self.userId,
                        lender: "Bank",
                        outstandingBalance: Money(amount: 1_000, currencyCode: "CNY"),
                        status: .active,
                        linkedAccountId: Self.accountId
                    ),
                ],
                debtEvents: [
                    DebtEvent(
                        id: Self.eventId,
                        debtId: Self.debtId,
                        userId: Self.userId,
                        type: .created,
                        amount: Money(amount: 1_000, currencyCode: "CNY"),
                        relatedTransactionId: Self.txId
                    ),
                ],
                repaymentPlans: [
                    RepaymentPlan(
                        id: Self.planId,
                        debtId: Self.debtId,
                        userId: Self.userId,
                        installmentAmount: Money(amount: 100, currencyCode: "CNY"),
                        frequency: .monthly,
                        startDate: Self.fixedCreatedAt
                    ),
                ],
                budgets: [
                    Budget(
                        id: Self.budgetId,
                        userId: Self.userId,
                        name: "Monthly",
                        limit: Money(amount: 3_000, currencyCode: "CNY")
                    ),
                ],
                goals: [
                    Goal(
                        id: Self.goalId,
                        userId: Self.userId,
                        name: "Payoff",
                        type: .debtPayoff,
                        targetAmount: Money(amount: 1_000, currencyCode: "CNY"),
                        relatedDebtId: Self.debtId
                    ),
                ],
                subscriptions: [
                    Subscription(
                        id: Self.subscriptionId,
                        userId: Self.userId,
                        name: "Streaming",
                        amount: Money(amount: 30, currencyCode: "CNY"),
                        accountId: Self.accountId
                    ),
                ]
            )
        )
    }

    @Test("valid backup from creation service passes preflight with safe preview")
    func validBackupPreview() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await populateRepresentativeLedger(in: container)

        let created = try await makeCreationService(store: store).createBackup(passphrase: "ledger-pass")
        let preview = try await preflight.preflight(data: created.data, passphrase: "ledger-pass")

        #expect(preview.createdAt == Self.fixedCreatedAt)
        #expect(preview.formatVersion == BackupPayloadV1.formatVersion)
        #expect(preview.sourceStoreSchemaVersion == YoushuSnapshot.currentSchemaVersion)
        #expect(preview.sourceAppVersion == "1.2.3-test")
        #expect(preview.restoreMode == .fullReplace)
        #expect(preview.counts.users == 1)
        #expect(preview.counts.accounts == 1)
        #expect(preview.counts.transactions == 1)
        #expect(preview.counts.debts == 1)
        #expect(preview.counts.debtEvents == 1)
        #expect(preview.counts.repaymentPlans == 1)
        #expect(preview.counts.assets == 1)
        #expect(preview.counts.goals == 1)
        #expect(preview.counts.budgets == 1)
        #expect(preview.counts.subscriptions == 1)

        let encodedPreview = try JSONEncoder().encode([
            "formatVersion": String(preview.formatVersion),
            "restoreMode": preview.restoreMode.rawValue,
        ])
        let previewText = String(decoding: encodedPreview, as: UTF8.self)
        #expect(!previewText.contains("Ledger Owner"))
        #expect(!previewText.contains("Coffee"))
        #expect(!previewText.contains("Bank"))
        #expect(!previewText.contains(Self.userId.uuidString))
        #expect(!previewText.contains("ledger-pass"))
    }

    @Test("preflight rejects wrong passphrase tampered ciphertext corrupt envelope and unsupported format")
    func authenticationAndEnvelopeFailures() async throws {
        let backupData = try encodeBackup(representativePayload(), passphrase: "correct-pass")

        await #expect(throws: BackupError.authenticationFailure) {
            try await preflight.preflight(data: backupData, passphrase: "wrong-pass")
        }

        var envelopeForTamper = try JSONDecoder().decode(FinSightBackupEnvelopeV1.self, from: backupData)
        envelopeForTamper.ciphertext[envelopeForTamper.ciphertext.startIndex] ^= 0xFF
        let tamperedCiphertext = try JSONEncoder().encode(envelopeForTamper)
        await #expect(throws: BackupError.authenticationFailure) {
            try await preflight.preflight(data: tamperedCiphertext, passphrase: "correct-pass")
        }

        var envelope = try JSONDecoder().decode(FinSightBackupEnvelopeV1.self, from: backupData)
        envelope.kdfIterations = BackupFormatV1Policy.kdfIterations + 1
        let headerTampered = try JSONEncoder().encode(envelope)
        await #expect(throws: BackupError.invalidCryptoParameter(field: "kdfIterations")) {
            try await preflight.preflight(data: headerTampered, passphrase: "correct-pass")
        }

        await #expect(throws: BackupError.malformedEnvelope("invalid envelope json")) {
            try await preflight.preflight(data: Data("{not-json".utf8), passphrase: "correct-pass")
        }

        let unsupportedEnvelope = FinSightBackupEnvelopeV1(
            formatVersion: 99,
            kdfIterations: BackupFormatV1Policy.kdfIterations,
            salt: Data(repeating: 1, count: BackupFormatV1Policy.saltByteCount),
            nonce: Data(repeating: 2, count: BackupFormatV1Policy.nonceByteCount),
            ciphertext: Data(repeating: 3, count: 32),
            authenticationTag: Data(repeating: 4, count: BackupFormatV1Policy.authenticationTagByteCount)
        )
        let unsupportedData = try JSONEncoder().encode(unsupportedEnvelope)
        await #expect(throws: BackupError.unsupportedFormat(found: 99, supported: BackupFormatV1Policy.formatVersion)) {
            try await preflight.preflight(data: unsupportedData, passphrase: "correct-pass")
        }

        let oversized = Data(repeating: 0, count: BackupFormatV1Policy.maximumBackupFileByteCount + 1)
        await #expect(throws: BackupError.backupTooLarge(
            byteCount: BackupFormatV1Policy.maximumBackupFileByteCount + 1,
            limit: BackupFormatV1Policy.maximumBackupFileByteCount
        )) {
            try await preflight.preflight(data: oversized, passphrase: "correct-pass")
        }
    }

    @Test("preflight rejects duplicate account transaction and debt ids")
    func duplicateIdentityRejection() async throws {
        var payload = representativePayload()
        payload.financialData.accounts.append(
            Account(id: Self.accountId, userId: Self.userId, name: "Duplicate", type: .cash)
        )
        let accountDup = try encodeBackup(payload)
        await #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Account")) {
            try await preflight.preflight(data: accountDup, passphrase: "test-passphrase")
        }

        payload = representativePayload()
        payload.financialData.transactions.append(
            Transaction(
                id: Self.txId,
                userId: Self.userId,
                accountId: Self.accountId,
                amount: Money(amount: 1, currencyCode: "CNY"),
                transactionType: .expense
            )
        )
        let txDup = try encodeBackup(payload)
        await #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Transaction")) {
            try await preflight.preflight(data: txDup, passphrase: "test-passphrase")
        }

        payload = representativePayload()
        payload.financialData.debts.append(
            Debt(id: Self.debtId, userId: Self.userId, status: .active)
        )
        let debtDup = try encodeBackup(payload)
        await #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Debt")) {
            try await preflight.preflight(data: debtDup, passphrase: "test-passphrase")
        }
    }

    @Test("preflight rejects entities whose required owner user does not exist")
    func missingOwnerRejection() async throws {
        var payload = representativePayload()
        payload.financialData.accounts = [
            Account(id: Self.accountId, userId: Self.otherUserId, name: "Orphan", type: .cash),
        ]
        let data = try encodeBackup(payload)
        await #expect(throws: BackupPayloadValidationError.missingRequiredOwner(entityType: "Account")) {
            try await preflight.preflight(data: data, passphrase: "test-passphrase")
        }
    }

    @Test("preflight rejects broken required relationships")
    func brokenRelationshipRejection() async throws {
        var payload = representativePayload()
        payload.financialData.transactions[0].accountId = Self.otherAccountId
        await #expect(throws: BackupPayloadValidationError.invalidReference(field: "Transaction.accountId")) {
            try await preflight.preflight(data: try encodeBackup(payload), passphrase: "test-passphrase")
        }

        payload = representativePayload()
        payload.financialData.transactions[0].relatedDebtId = UUID()
        await #expect(throws: BackupPayloadValidationError.invalidReference(field: "Transaction.relatedDebtId")) {
            try await preflight.preflight(data: try encodeBackup(payload), passphrase: "test-passphrase")
        }

        payload = representativePayload()
        payload.financialData.debtEvents[0].debtId = UUID()
        await #expect(throws: BackupPayloadValidationError.invalidReference(field: "DebtEvent.debtId")) {
            try await preflight.preflight(data: try encodeBackup(payload), passphrase: "test-passphrase")
        }

        payload = representativePayload()
        payload.financialData.repaymentPlans[0].debtId = UUID()
        await #expect(throws: BackupPayloadValidationError.invalidReference(field: "RepaymentPlan.debtId")) {
            try await preflight.preflight(data: try encodeBackup(payload), passphrase: "test-passphrase")
        }
    }

    @Test("preflight rejects cross-user account and debt references")
    func crossUserReferenceRejection() async throws {
        var payload = representativePayload()
        payload.financialData.users.append(
            BackupUserV1(
                id: Self.otherUserId,
                displayName: "Other",
                preferredCurrency: "CNY",
                debtInventoryEstablishment: .unestablished,
                createdAt: Self.fixedCreatedAt,
                updatedAt: Self.fixedCreatedAt
            )
        )
        payload.financialData.transactions[0].userId = Self.otherUserId
        await #expect(throws: BackupPayloadValidationError.crossUserReference(field: "Transaction.accountId")) {
            try await preflight.preflight(data: try encodeBackup(payload), passphrase: "test-passphrase")
        }

        payload = representativePayload()
        payload.financialData.users.append(
            BackupUserV1(
                id: Self.otherUserId,
                displayName: "Other",
                preferredCurrency: "CNY",
                debtInventoryEstablishment: .unestablished,
                createdAt: Self.fixedCreatedAt,
                updatedAt: Self.fixedCreatedAt
            )
        )
        payload.financialData.debts[0].userId = Self.otherUserId
        payload.financialData.transactions[0].relatedDebtId = Self.debtId
        await #expect(throws: BackupPayloadValidationError.crossUserReference(field: "Transaction.relatedDebtId")) {
            try await preflight.preflight(data: try encodeBackup(payload), passphrase: "test-passphrase")
        }
    }

    @Test("candidate builder resets excluded collections and import transient state")
    func candidateResetSemantics() throws {
        let payload = representativePayload()
        let candidate = BackupRestoreCandidateBuilder.build(from: payload)

        #expect(candidate.insights.isEmpty)
        #expect(candidate.aiDataConsents.isEmpty)
        #expect(candidate.aiRecognitionRecords.isEmpty)
        #expect(candidate.mediaArtifacts.isEmpty)
        #expect(candidate.pendingDebtLinks.isEmpty)
        #expect(candidate.suspectedDebts.isEmpty)
        #expect(candidate.users.first?.debtImportInProgress == false)
    }

    @Test("candidate uses current schema version not source provenance metadata")
    func candidateSchemaVersion() {
        var payload = representativePayload()
        payload.metadata.sourceStoreSchemaVersion = 1
        let candidate = BackupRestoreCandidateBuilder.build(from: payload)
        #expect(candidate.schemaVersion == YoushuSnapshot.currentSchemaVersion)
        #expect(candidate.schemaVersion != payload.metadata.sourceStoreSchemaVersion)
    }

    @Test("empty minimal backup passes preflight")
    func emptyMinimalBackup() async throws {
        let store = YoushuStore()
        let created = try await makeCreationService(store: store, sourceAppVersion: nil)
            .createBackup(passphrase: "empty-pass")
        let preview = try await preflight.preflight(data: created.data, passphrase: "empty-pass")

        #expect(preview.counts.users == 0)
        #expect(preview.counts.accounts == 0)
        #expect(preview.counts.transactions == 0)
        #expect(preview.sourceAppVersion == nil)
    }

    private func snapshotFingerprint(_ snapshot: YoushuSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    @Test("preflight does not mutate live store on success or failure")
    func sideEffectFreeGuarantee() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await populateRepresentativeLedger(in: container)
        let before = try snapshotFingerprint(await store.currentSnapshot())

        let created = try await makeCreationService(store: store).createBackup(passphrase: "side-effect-pass")
        _ = try await preflight.preflight(data: created.data, passphrase: "side-effect-pass")
        let afterSuccess = try snapshotFingerprint(await store.currentSnapshot())
        #expect(afterSuccess == before)

        var invalidPayload = representativePayload()
        invalidPayload.financialData.accounts.append(
            Account(id: Self.accountId, userId: Self.userId, name: "Dup", type: .cash)
        )
        let invalidData = try encodeBackup(invalidPayload, passphrase: "side-effect-pass")
        await #expect(throws: BackupPayloadValidationError.self) {
            try await preflight.preflight(data: invalidData, passphrase: "side-effect-pass")
        }
        let afterFailure = try snapshotFingerprint(await store.currentSnapshot())
        #expect(afterFailure == before)
    }

    @Test("preflight service structurally has no store dependency")
    func noStoreDependency() {
        let mirror = Mirror(reflecting: BackupRestorePreflightService())
        #expect(mirror.children.isEmpty)
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
        try await container.accounts.upsert(
            Account(id: Self.accountId, userId: Self.userId, name: "Cash", type: .cash)
        )
        try await container.debts.upsert(
            Debt(
                id: Self.debtId,
                userId: Self.userId,
                lender: "Bank",
                outstandingBalance: Money(amount: 1_000, currencyCode: "CNY"),
                status: .active,
                linkedAccountId: Self.accountId
            )
        )
        try await container.transactions.upsert(
            Transaction(
                id: Self.txId,
                userId: Self.userId,
                accountId: Self.accountId,
                amount: Money(amount: 50, currencyCode: "CNY"),
                merchant: "Coffee",
                category: "Food",
                transactionType: .expense,
                relatedDebtId: Self.debtId
            )
        )
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
