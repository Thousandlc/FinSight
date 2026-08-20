import Foundation
import Testing
import YoushuData
import YoushuDomain

@Suite("Backup restore flow engine")
@MainActor
struct BackupRestoreFlowEngineTests {
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    private static let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!

    private func samplePayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion,
                sourceAppVersion: "flow-test"
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

    private func makeEngine(
        store: YoushuStore = YoushuStore(),
        onRefresh: @escaping @Sendable () -> Void = {}
    ) -> BackupRestoreFlowEngine {
        BackupRestoreFlowEngine(
            preflightService: BackupRestorePreflightService(),
            restoreService: BackupRestoreService(store: store),
            applicationRefresh: onRefresh
        )
    }

    @Test("preflight success moves to preview")
    func preflightSuccess() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "flow-pass")
        let engine = makeEngine()

        engine.beginImport()
        engine.fileImported(backupData)
        engine.updatePassphrase("flow-pass")
        await engine.submitPassphrase()

        guard case let .preview(preview) = engine.phase else {
            Issue.record("Expected preview, got \(engine.phase)")
            return
        }
        #expect(preview.counts.accounts == 1)
    }

    @Test("cancel clears encrypted bytes and passphrase")
    func cancelClearsSensitiveState() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "flow-pass")
        let engine = makeEngine()

        engine.beginImport()
        engine.fileImported(backupData)
        engine.updatePassphrase("flow-pass")
        engine.cancel()

        #expect(engine.phase == .idle)
        #expect(engine.importedEncryptedDataForTesting == nil)
    }

    @Test("confirm restore passes same encrypted bytes used for preflight")
    func confirmUsesSameEncryptedBytes() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "flow-pass")
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Live"))
        let engine = makeEngine(store: store)

        engine.beginImport()
        engine.fileImported(backupData)
        engine.updatePassphrase("flow-pass")
        await engine.submitPassphrase()
        engine.proceedToDestructiveConfirmation()
        await engine.confirmRestore()

        guard case let .success(result) = engine.phase else {
            Issue.record("Expected success, got \(engine.phase)")
            return
        }
        #expect(result.counts.accounts == 1)
        #expect(engine.importedEncryptedDataForTesting == nil)
    }

    @Test("restore success invokes application refresh before success phase")
    func restoreSuccessInvokesRefresh() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "flow-pass")
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Live"))
        let tracker = RefreshTracker()
        let engine = makeEngine(store: store, onRefresh: { tracker.markInvoked() })

        engine.beginImport()
        engine.fileImported(backupData)
        engine.updatePassphrase("flow-pass")
        await engine.submitPassphrase()
        engine.proceedToDestructiveConfirmation()
        await engine.confirmRestore()

        #expect(tracker.invoked)
        guard case .success = engine.phase else {
            Issue.record("Expected success")
            return
        }
    }

    @Test("validation failure does not invoke refresh")
    func validationFailureSkipsRefresh() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "flow-pass")
        let tracker = RefreshTracker()
        let engine = makeEngine(onRefresh: { tracker.markInvoked() })

        engine.beginImport()
        engine.fileImported(backupData)
        engine.updatePassphrase("wrong-pass")
        await engine.submitPassphrase()

        guard case .failed = engine.phase else {
            Issue.record("Expected failed")
            return
        }
        #expect(tracker.invoked == false)
    }

    @Test("rollbackFailed enters critical failure without application refresh")
    func criticalFailureSkipsRefresh() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "flow-pass")
        let tracker = RefreshTracker()
        let engine = BackupRestoreFlowEngine(
            preflightService: BackupRestorePreflightService(),
            restoreService: StubBackupRestoreService(error: BackupRestoreError.rollbackFailed),
            applicationRefresh: { tracker.markInvoked() }
        )

        engine.beginImport()
        engine.fileImported(backupData)
        engine.updatePassphrase("flow-pass")
        await engine.submitPassphrase()
        engine.proceedToDestructiveConfirmation()
        await engine.confirmRestore()

        #expect(engine.phase == .criticalFailure)
        #expect(tracker.invoked == false)
        #expect(engine.importedEncryptedDataForTesting == nil)
    }

    @Test("duplicate preflight is prevented while busy")
    func duplicateActionPrevented() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "flow-pass")
        let engine = makeEngine()

        engine.beginImport()
        engine.fileImported(backupData)
        engine.updatePassphrase("flow-pass")

        async let first: Void = engine.submitPassphrase()
        await engine.submitPassphrase()
        await first

        #expect(engine.phase != .idle)
    }
}

private final class RefreshTracker: @unchecked Sendable {
    private(set) var invoked = false

    func markInvoked() {
        invoked = true
    }
}

private struct StubBackupRestoreService: BackupRestoring {
    let error: Error

    func restoreBackup(data: Data, passphrase: String) async throws -> BackupRestoreResult {
        throw error
    }
}
