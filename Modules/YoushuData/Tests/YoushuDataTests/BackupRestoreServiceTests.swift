import Foundation
import Testing
@testable import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Backup restore commit service")
struct BackupRestoreServiceTests {
    private static let fixedCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let fixedRestoredAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let userA = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let userB = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private static let accountB = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private static let debtB = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let txB = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    private static let localOnlyAccount = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    private static let localOnlyTx = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private static let eventB = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    private static let planB = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!

    private func makeTempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("youshu-store.json")
    }

    private func snapshotFingerprint(_ snapshot: YoushuSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func makePopulatedFileBackedStore(
        simulatedIO: SimulatedYoushuStorePersistenceIO? = nil
    ) async throws -> (store: YoushuStore, url: URL, simulated: SimulatedYoushuStorePersistenceIO?) {
        let seedStore = YoushuStore()
        let seedContainer = RepositoryContainer(store: seedStore)
        try await populateLocalStoreA(container: seedContainer)
        let seededSnapshot = await seedStore.currentSnapshot()

        let url = makeTempStoreURL()
        let persistenceIO: YoushuStorePersistenceIO = simulatedIO ?? FoundationYoushuStorePersistenceIO()
        let store = YoushuStore(fileURL: url, snapshot: seededSnapshot, persistenceIO: persistenceIO)
        try await store.persist()
        simulatedIO?.reset()
        return (store, url, simulatedIO)
    }

    private func makeFileBackedStore(
        simulatedIO: SimulatedYoushuStorePersistenceIO? = nil
    ) -> (store: YoushuStore, url: URL, simulated: SimulatedYoushuStorePersistenceIO?) {
        let url = makeTempStoreURL()
        let persistenceIO: YoushuStorePersistenceIO = simulatedIO ?? FoundationYoushuStorePersistenceIO()
        let store = YoushuStore(fileURL: url, persistenceIO: persistenceIO)
        return (store, url, simulatedIO)
    }

    private func makeRestoreService(
        store: YoushuStore,
        restoredAt: Date = fixedRestoredAt
    ) -> BackupRestoreService {
        BackupRestoreService(store: store) { restoredAt }
    }

    private func makeCreationService(store: YoushuStore) -> BackupCreationService {
        BackupCreationService(store: store) {
            BackupCreationMetadata(createdAt: Self.fixedCreatedAt, sourceAppVersion: "restore-test")
        }
    }

    private func encodeBackup(_ payload: BackupPayloadV1, passphrase: String = "restore-pass") throws -> Data {
        try BackupCodec.encode(payload: payload, passphrase: passphrase)
    }

    private func backupPayloadB() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Self.fixedCreatedAt,
                sourceStoreSchemaVersion: 1,
                sourceAppVersion: "backup-b"
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: Self.userB,
                        displayName: "Backup Owner",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .partial,
                        createdAt: Self.fixedCreatedAt,
                        updatedAt: Self.fixedCreatedAt
                    ),
                ],
                accounts: [
                    Account(id: Self.accountB, userId: Self.userB, name: "Backup Cash", type: .cash),
                ],
                transactions: [
                    Transaction(
                        id: Self.txB,
                        userId: Self.userB,
                        accountId: Self.accountB,
                        amount: Money(amount: 88, currencyCode: "CNY"),
                        merchant: "Backup Shop",
                        category: "Food",
                        transactionType: .expense,
                        relatedDebtId: Self.debtB
                    ),
                ],
                debts: [
                    Debt(
                        id: Self.debtB,
                        userId: Self.userB,
                        lender: "Backup Bank",
                        outstandingBalance: Money(amount: 500, currencyCode: "CNY"),
                        status: .active,
                        linkedAccountId: Self.accountB
                    ),
                ],
                debtEvents: [
                    DebtEvent(
                        id: Self.eventB,
                        debtId: Self.debtB,
                        userId: Self.userB,
                        type: .created,
                        amount: Money(amount: 500, currencyCode: "CNY"),
                        relatedTransactionId: Self.txB
                    ),
                ],
                repaymentPlans: [
                    RepaymentPlan(
                        id: Self.planB,
                        debtId: Self.debtB,
                        userId: Self.userB,
                        installmentAmount: Money(amount: 50, currencyCode: "CNY"),
                        frequency: .monthly,
                        startDate: Self.fixedCreatedAt
                    ),
                ]
            )
        )
    }

    private func populateLocalStoreA(container: RepositoryContainer) async throws {
        try await container.users.upsert(User(id: Self.userA, displayName: "Local Owner"))
        try await container.accounts.upsert(
            Account(id: Self.localOnlyAccount, userId: Self.userA, name: "Local Only", type: .cash)
        )
        try await container.transactions.upsert(
            Transaction(
                id: Self.localOnlyTx,
                userId: Self.userA,
                accountId: Self.localOnlyAccount,
                amount: Money(amount: 999, currencyCode: "CNY"),
                merchant: "Local Only Merchant",
                transactionType: .expense
            )
        )
    }

    private func populateExcludedLocalState(container: RepositoryContainer, userId: UUID) async throws {
        try await container.insights.upsert(
            FinancialInsight(userId: userId, type: .summary, title: "Local Insight", body: "secret")
        )
        try await container.aiDataConsents.upsert(
            AIDataConsent(
                userId: userId,
                allowScreenshotImageToAI: true,
                allowFinancialContextToAI: true
            )
        )
        try await container.aiRecognitionRecords.upsert(
            AIRecognitionRecord(
                userId: userId,
                kind: .screenshotTransaction,
                status: .recognized,
                summaryLabel: "local recognition"
            )
        )
        try await container.mediaArtifacts.upsert(
            MediaArtifact(
                id: "local-media",
                userId: userId,
                kind: .screenshotTransaction,
                byteSize: 512,
                contentHash: "hash",
                retention: .ephemeral
            )
        )
        try await container.pendingDebtLinks.upsert(
            PendingDebtLink(
                userId: userId,
                transactionId: Self.localOnlyTx,
                confidence: 0.8,
                reason: "local pending"
            )
        )
        try await container.suspectedDebts.upsert(
            SuspectedDebt(
                userId: userId,
                merchant: "Local Suspected",
                amount: Money(amount: 10, currencyCode: "CNY"),
                dayOfMonth: 1,
                occurrenceCount: 2,
                sampleTransactionIds: [],
                reason: "local suspected"
            )
        )
        _ = try await container.confirmedImportProvenances.upsert(
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .debtScan,
                sourceFingerprints: [ImportSourceFingerprint.sha256(of: Data("local-provenance".utf8))],
                confirmedEntityReferences: [.debt(UUID())]
            )
        )
    }

    @Test("simulated persistence IO read failure is observable")
    func simulatedPersistenceReadFailure() throws {
        let simulated = SimulatedYoushuStorePersistenceIO()
        let url = makeTempStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: url)
        simulated.queueFailures([.read])
        #expect(throws: DataError.self) {
            _ = try simulated.read(from: url)
        }
    }

    @Test("store replaceSnapshotForRestore surfaces post-write verification failure")
    func storePostWriteVerificationFailure() async throws {
        let simulated = SimulatedYoushuStorePersistenceIO()
        let (store, url, io) = try await makePopulatedFileBackedStore(simulatedIO: simulated)
        let beforeMemory = try snapshotFingerprint(await store.currentSnapshot())
        let beforeDisk = try Data(contentsOf: url)
        let candidate = BackupRestoreCandidateBuilder.build(from: backupPayloadB())

        simulated.queueFailures([.read])
        await #expect(throws: BackupRestoreError.postWriteVerificationFailure) {
            try await store.replaceSnapshotForRestore(candidate)
        }

        #expect(try snapshotFingerprint(await store.currentSnapshot()) == beforeMemory)
        #expect(try Data(contentsOf: url) == beforeDisk)
    }

    @Test("successful restore fully replaces live store and survives reload")
    func successfulFullReplacement() async throws {
        let (store, url, _) = try await makePopulatedFileBackedStore()
        let backupData = try encodeBackup(backupPayloadB())

        let result = try await makeRestoreService(store: store).restoreBackup(
            data: backupData,
            passphrase: "restore-pass"
        )

        #expect(result.backupCreatedAt == Self.fixedCreatedAt)
        #expect(result.restoredAt == Self.fixedRestoredAt)
        #expect(result.counts.users == 1)
        #expect(result.counts.transactions == 1)
        #expect(result.requiresApplicationReload)

        let live = await store.currentSnapshot()
        #expect(live.users.first?.id == Self.userB)
        #expect(live.accounts.contains(where: { $0.id == Self.accountB }))
        #expect(!live.accounts.contains(where: { $0.id == Self.localOnlyAccount }))
        #expect(!live.transactions.contains(where: { $0.id == Self.localOnlyTx }))

        let reloaded = try await YoushuStore.load(from: url)
        let diskSnapshot = await reloaded.currentSnapshot()
        #expect(diskSnapshot.users.first?.id == Self.userB)
        #expect(diskSnapshot.schemaVersion == YoushuSnapshot.currentSchemaVersion)
    }

    @Test("restore preserves representative financial relationships")
    func relationshipPreservation() async throws {
        let (store, _, _) = makeFileBackedStore()
        let backupData = try encodeBackup(backupPayloadB())
        _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")

        let snapshot = await store.currentSnapshot()
        let transaction = try #require(snapshot.transactions.first)
        let event = try #require(snapshot.debtEvents.first)
        let plan = try #require(snapshot.repaymentPlans.first)

        #expect(transaction.accountId == Self.accountB)
        #expect(transaction.relatedDebtId == Self.debtB)
        #expect(transaction.userId == Self.userB)
        #expect(event.debtId == Self.debtB)
        #expect(event.relatedTransactionId == Self.txB)
        #expect(plan.debtId == Self.debtB)
        #expect(plan.userId == Self.userB)
    }

    @Test("restore clears excluded AI consent media and workflow state")
    func exclusionAndPrivacyReset() async throws {
        let seedStore = YoushuStore()
        let seedContainer = RepositoryContainer(store: seedStore)
        try await populateLocalStoreA(container: seedContainer)
        try await populateExcludedLocalState(container: seedContainer, userId: Self.userA)
        let seededSnapshot = await seedStore.currentSnapshot()

        let url = makeTempStoreURL()
        let store = YoushuStore(fileURL: url, snapshot: seededSnapshot)
        try await store.persist()
        let container = RepositoryContainer(store: store)

        let backupData = try encodeBackup(backupPayloadB())
        _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")

        let snapshot = await store.currentSnapshot()
        #expect(snapshot.insights.isEmpty)
        #expect(snapshot.aiDataConsents.isEmpty)
        #expect(snapshot.aiRecognitionRecords.isEmpty)
        #expect(snapshot.mediaArtifacts.isEmpty)
        #expect(snapshot.pendingDebtLinks.isEmpty)
        #expect(snapshot.suspectedDebts.isEmpty)
        #expect(snapshot.confirmedImportProvenances.isEmpty)
        #expect(snapshot.users.first?.debtImportInProgress == false)

        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let consent = try await consentService.fetchOrDefault(userId: Self.userB)
        #expect(consent.allowFinancialContextToAI == false)
        #expect(consent.allowScreenshotImageToAI == false)
    }

    @Test("restore does not merge local-only records")
    func noMergeBehavior() async throws {
        let (store, _, _) = try await makePopulatedFileBackedStore()
        let backupData = try encodeBackup(backupPayloadB())

        _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")

        let snapshot = await store.currentSnapshot()
        #expect(snapshot.transactions.allSatisfy { $0.id != Self.localOnlyTx })
        #expect(snapshot.accounts.allSatisfy { $0.id != Self.localOnlyAccount })
        #expect(snapshot.users.allSatisfy { $0.id != Self.userA })
    }

    @Test("commit independently re-validates encrypted bytes and rejects tampered input")
    func revalidationRejectsTamperedBytes() async throws {
        let (store, _, _) = try await makePopulatedFileBackedStore()
        let before = try snapshotFingerprint(await store.currentSnapshot())

        let validBackup = try encodeBackup(backupPayloadB())
        _ = try await BackupRestorePreflightService().preflight(data: validBackup, passphrase: "restore-pass")

        var envelope = try JSONDecoder().decode(FinSightBackupEnvelopeV1.self, from: validBackup)
        envelope.ciphertext[envelope.ciphertext.startIndex] ^= 0xFF
        let tampered = try JSONEncoder().encode(envelope)
        await #expect(throws: BackupError.authenticationFailure) {
            _ = try await makeRestoreService(store: store).restoreBackup(data: tampered, passphrase: "restore-pass")
        }

        let after = try snapshotFingerprint(await store.currentSnapshot())
        #expect(after == before)
    }

    @Test("wrong passphrase leaves memory and disk unchanged")
    func wrongPassphraseNoMutation() async throws {
        let (store, url, _) = try await makePopulatedFileBackedStore()
        let beforeMemory = try snapshotFingerprint(await store.currentSnapshot())
        let beforeDisk = try Data(contentsOf: url)

        let backupData = try encodeBackup(backupPayloadB())
        await #expect(throws: BackupError.authenticationFailure) {
            _ = try await makeRestoreService(store: store).restoreBackup(
                data: backupData,
                passphrase: "wrong-pass"
            )
        }

        let afterMemory = try snapshotFingerprint(await store.currentSnapshot())
        let afterDisk = try Data(contentsOf: url)
        #expect(afterMemory == beforeMemory)
        #expect(afterDisk == beforeDisk)
    }

    @Test("semantic invalid authenticated backup fails before persistence")
    func semanticInvalidBeforePersistence() async throws {
        let (store, url, _) = try await makePopulatedFileBackedStore()
        let beforeMemory = try snapshotFingerprint(await store.currentSnapshot())
        let beforeDisk = try Data(contentsOf: url)

        var payload = backupPayloadB()
        payload.financialData.accounts.append(
            Account(id: Self.accountB, userId: Self.userB, name: "Dup", type: .cash)
        )
        let backupData = try encodeBackup(payload)

        await #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Account")) {
            _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")
        }

        #expect(try snapshotFingerprint(await store.currentSnapshot()) == beforeMemory)
        #expect(try Data(contentsOf: url) == beforeDisk)
    }

    @Test("candidate write failure leaves previous memory and disk intact")
    func candidateWriteFailure() async throws {
        let simulated = SimulatedYoushuStorePersistenceIO()
        let (store, url, io) = try await makePopulatedFileBackedStore(simulatedIO: simulated)
        simulated.queueFailures([.write])
        let beforeMemory = try snapshotFingerprint(await store.currentSnapshot())
        let beforeDisk = try Data(contentsOf: url)

        let backupData = try encodeBackup(backupPayloadB())
        await #expect(throws: BackupRestoreError.commitPersistenceFailure) {
            _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")
        }

        #expect(try snapshotFingerprint(await store.currentSnapshot()) == beforeMemory)
        #expect(try Data(contentsOf: url) == beforeDisk)
    }

    @Test("post-write verification failure rolls back disk and preserves previous memory")
    func postWriteVerificationFailureRollsBack() async throws {
        let simulated = SimulatedYoushuStorePersistenceIO()
        let (store, url, io) = try await makePopulatedFileBackedStore(simulatedIO: simulated)
        simulated.queueFailures([.read])
        let beforeMemory = try snapshotFingerprint(await store.currentSnapshot())
        let beforeDisk = try Data(contentsOf: url)

        let backupData = try encodeBackup(backupPayloadB())
        await #expect(throws: BackupRestoreError.postWriteVerificationFailure) {
            _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")
        }

        #expect(try snapshotFingerprint(await store.currentSnapshot()) == beforeMemory)
        #expect(try Data(contentsOf: url) == beforeDisk)
    }

    @Test("rollback write failure surfaces critical rollback error")
    func rollbackWriteFailure() async throws {
        let simulated = SimulatedYoushuStorePersistenceIO()
        let (store, _, io) = try await makePopulatedFileBackedStore(simulatedIO: simulated)
        simulated.queueFailures([.read, .write])
        let beforeMemory = try snapshotFingerprint(await store.currentSnapshot())

        let backupData = try encodeBackup(backupPayloadB())
        await #expect(throws: BackupRestoreError.rollbackFailed) {
            _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")
        }

        #expect(try snapshotFingerprint(await store.currentSnapshot()) == beforeMemory)
    }

    @Test("rollback verification failure surfaces critical rollback error")
    func rollbackVerificationFailure() async throws {
        let simulated = SimulatedYoushuStorePersistenceIO()
        let (store, url, io) = try await makePopulatedFileBackedStore(simulatedIO: simulated)
        simulated.queueFailures([.read, .read])
        let beforeMemory = try snapshotFingerprint(await store.currentSnapshot())
        let beforeDisk = try Data(contentsOf: url)

        let backupData = try encodeBackup(backupPayloadB())
        await #expect(throws: BackupRestoreError.rollbackFailed) {
            _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")
        }

        #expect(try snapshotFingerprint(await store.currentSnapshot()) == beforeMemory)
        #expect(try Data(contentsOf: url) == beforeDisk)
    }

    @Test("restored disk snapshot uses current schema regardless of backup provenance")
    func currentSchemaPersistence() async throws {
        let (store, url, _) = makeFileBackedStore()
        let backupData = try encodeBackup(backupPayloadB())
        _ = try await makeRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")

        let reloaded = try await YoushuStore.load(from: url)
        let diskSnapshot = await reloaded.currentSnapshot()
        #expect(diskSnapshot.schemaVersion == YoushuSnapshot.currentSchemaVersion)
    }

    @Test("empty minimal backup replaces populated store")
    func emptyMinimalBackupRestore() async throws {
        let (store, _, _) = try await makePopulatedFileBackedStore()

        let emptyBackup = try await makeCreationService(store: YoushuStore())
            .createBackup(passphrase: "minimal-pass")
        _ = try await makeRestoreService(store: store).restoreBackup(
            data: emptyBackup.data,
            passphrase: "minimal-pass"
        )

        let snapshot = await store.currentSnapshot()
        #expect(snapshot.users.isEmpty)
        #expect(snapshot.accounts.isEmpty)
        #expect(snapshot.transactions.isEmpty)
    }

    @Test("restore reports identity reload when backup user ids differ")
    func userIdentityTransitionFlag() async throws {
        let (store, _, _) = try await makePopulatedFileBackedStore()

        let backupData = try encodeBackup(backupPayloadB())
        let result = try await makeRestoreService(store: store).restoreBackup(
            data: backupData,
            passphrase: "restore-pass"
        )

        #expect(result.requiresApplicationReload)
        #expect(result.userIdentityChanged)
        #expect(await store.currentSnapshot().users.first?.id == Self.userB)
    }

    @Test("same user id restore still requires application reload")
    func sameUserIdentityStillRequiresReload() async throws {
        let (store, _, _) = makeFileBackedStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userB, displayName: "Same User"))
        try await container.accounts.upsert(
            Account(id: Self.localOnlyAccount, userId: Self.userB, name: "Old", type: .cash)
        )

        let backupData = try encodeBackup(backupPayloadB())
        let result = try await makeRestoreService(store: store).restoreBackup(
            data: backupData,
            passphrase: "restore-pass"
        )

        #expect(result.requiresApplicationReload)
        #expect(result.userIdentityChanged == false)
    }
}
