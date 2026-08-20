import Foundation
import Testing
import YoushuData
import YoushuDomain

@Suite("Backup passphrase policy")
struct BackupPassphrasePolicyTests {
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

    private func samplePayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion,
                sourceAppVersion: "passphrase-test"
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: Self.userId,
                        displayName: "Owner",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .partial,
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ],
                accounts: [
                    Account(id: Self.accountId, userId: Self.userId, name: "Cash", type: .cash),
                ]
            )
        )
    }

    @Test("BackupPassphrasePolicy rejects empty passphrase")
    func policyRejectsEmpty() {
        #expect(throws: BackupError.invalidPassphrase) {
            try BackupPassphrasePolicy.validate("")
        }
    }

    @Test("whitespace-only passphrase is not normalized away")
    func whitespacePassphraseIsAcceptedAsNonEmpty() throws {
        #expect(throws: Never.self) {
            try BackupPassphrasePolicy.validate("   ")
        }
    }

    @Test("BackupCodec encode rejects empty passphrase before KDF")
    func encodeRejectsEmpty() {
        #expect(throws: BackupError.invalidPassphrase) {
            try BackupCodec.encode(payload: samplePayload(), passphrase: "")
        }
    }

    @Test("BackupCodec decode rejects empty passphrase before KDF")
    func decodeRejectsEmpty() throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "valid-pass")
        #expect(throws: BackupError.invalidPassphrase) {
            try BackupCodec.decode(backupData: backupData, passphrase: "")
        }
    }

    @Test("BackupCreationService rejects empty passphrase without store mutation")
    func creationRejectsEmpty() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Owner"))
        let before = await store.currentSnapshot()

        let service = BackupCreationService(store: store)
        await #expect(throws: BackupError.invalidPassphrase) {
            try await service.createBackup(passphrase: "")
        }

        let after = await store.currentSnapshot()
        #expect(before.users.count == after.users.count)
    }

    @Test("BackupRestorePreflightService rejects empty passphrase")
    func preflightRejectsEmpty() async throws {
        let payload = samplePayload()
        let backupData = try BackupCodec.encode(payload: payload, passphrase: "valid-pass")
        let preflight = BackupRestorePreflightService()

        await #expect(throws: BackupError.invalidPassphrase) {
            try await preflight.preflight(data: backupData, passphrase: "")
        }
    }

    @Test("BackupRestoreService rejects empty passphrase without persistence mutation")
    func restoreRejectsEmpty() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("youshu-store.json")
        let store = YoushuStore(fileURL: url)
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Owner"))
        try await store.persist()
        let before = try await YoushuStore.load(from: url)

        let payload = samplePayload()
        let backupData = try BackupCodec.encode(payload: payload, passphrase: "valid-pass")
        let service = BackupRestoreService(store: store)

        await #expect(throws: BackupError.invalidPassphrase) {
            try await service.restoreBackup(data: backupData, passphrase: "")
        }

        let reloaded = try await YoushuStore.load(from: url)
        let beforeSnapshot = await before.currentSnapshot()
        let afterSnapshot = await reloaded.currentSnapshot()
        #expect(beforeSnapshot.users.count == afterSnapshot.users.count)
    }
}

@Suite("Backup restore failure classification")
struct BackupRestoreFailureClassificationTests {
    @Test("rollbackFailed is critical persistence failure")
    func rollbackFailedClassification() {
        let category = BackupRestoreFailureClassifier.classify(BackupRestoreError.rollbackFailed)
        #expect(category == .criticalPersistenceFailure)
        #expect(BackupRestoreFailureClassifier.isCriticalPersistenceFailure(BackupRestoreError.rollbackFailed))
    }

    @Test("commit and verification failures are commit failures not critical")
    func commitFailureClassification() {
        #expect(
            BackupRestoreFailureClassifier.classify(BackupRestoreError.commitPersistenceFailure)
                == .commitFailure
        )
        #expect(
            BackupRestoreFailureClassifier.classify(BackupRestoreError.postWriteVerificationFailure)
                == .commitFailure
        )
        #expect(
            !BackupRestoreFailureClassifier.isCriticalPersistenceFailure(
                BackupRestoreError.postWriteVerificationFailure
            )
        )
    }

    @Test("backup validation errors classify as validation failures")
    func validationFailureClassification() {
        #expect(
            BackupRestoreFailureClassifier.classify(BackupError.invalidPassphrase)
                == .validationFailure
        )
        #expect(
            BackupRestoreFailureClassifier.classify(
                BackupPayloadValidationError.duplicateEntityId(entityType: "account")
            ) == .validationFailure
        )
    }
}
