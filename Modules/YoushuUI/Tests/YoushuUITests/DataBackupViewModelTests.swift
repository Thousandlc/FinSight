import Foundation
import Testing
import YoushuData
import YoushuDomain
@testable import YoushuUI

@Suite("Data backup view model")
@MainActor
struct DataBackupViewModelTests {
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private static let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!

    private func makeViewModel(
        store: YoushuStore = YoushuStore(),
        refreshCalled: @escaping @Sendable () -> Void = {}
    ) -> (DataBackupViewModel, AppDependencies) {
        let tracker = RefreshCallbackTracker(callback: refreshCalled)
        let dependencies = AppDependencies(repositories: RepositoryContainer(store: store))
        let viewModel = dependencies.makeDataBackupViewModel {
            tracker.invoke()
        }
        return (viewModel, dependencies)
    }

    private func samplePayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion,
                sourceAppVersion: "ui-test"
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

    @Test("create flow rejects mismatched confirmation")
    func mismatchedConfirmationRejected() async {
        let (viewModel, _) = makeViewModel()
        viewModel.presentBackupCreation()
        viewModel.creationPassphrase = "secret-one"
        viewModel.creationPassphraseConfirmation = "secret-two"

        await viewModel.createBackup()

        #expect(viewModel.creationValidationError == "两次输入的密码不一致。")
        if case .creating = viewModel.creationPhase {
            Issue.record("Should not enter creating state")
        }
    }

    @Test("create flow hands encrypted document to exporter state")
    func createFlowPreparesExporter() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Owner"))
        let (viewModel, _) = makeViewModel(store: store)

        viewModel.presentBackupCreation()
        viewModel.creationPassphrase = "export-pass"
        viewModel.creationPassphraseConfirmation = "export-pass"
        await viewModel.createBackup()

        guard case let .readyToExport(created) = viewModel.creationPhase else {
            Issue.record("Expected readyToExport")
            return
        }
        #expect(viewModel.isPresentingBackupExporter)
        #expect(viewModel.exportDocument?.encryptedData == created.data)
        #expect(viewModel.exportFilename == created.suggestedFilename)
        #expect(viewModel.creationPassphrase.isEmpty)
        #expect(viewModel.creationPassphraseConfirmation.isEmpty)
    }

    @Test("restore importer stores immutable encrypted bytes for later restore")
    func restoreUsesImportedBytes() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "restore-pass")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-restore-test.finsightbackup")
        try backupData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (viewModel, _) = makeViewModel()
        viewModel.beginRestoreImport()
        viewModel.handleRestoreImportResult(.success(url))

        guard case .awaitingPassphrase = viewModel.restoreEngine.phase else {
            Issue.record("Expected awaitingPassphrase")
            return
        }
        #expect(viewModel.restoreEngine.importedEncryptedDataForTesting == backupData)
    }

    @Test("restore success invokes application refresh through flow engine")
    func restoreSuccessRefreshesApplication() async throws {
        let backupData = try BackupCodec.encode(payload: samplePayload(), passphrase: "restore-pass")
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userId, displayName: "Live"))
        let tracker = RefreshTracker()
        let (viewModel, _) = makeViewModel(store: store, refreshCalled: { tracker.markInvoked() })

        viewModel.restoreEngine.beginImport()
        viewModel.restoreEngine.fileImported(backupData)
        viewModel.updateRestorePassphrase("restore-pass")
        await viewModel.submitRestorePassphrase()
        viewModel.restoreEngine.proceedToDestructiveConfirmation()
        await viewModel.confirmRestore()

        #expect(tracker.invoked)
        guard case .success = viewModel.restoreEngine.phase else {
            Issue.record("Expected success")
            return
        }
    }

    @Test("export completion clears passphrase state")
    func exportCompletionClearsState() {
        let (viewModel, _) = makeViewModel()
        viewModel.creationPassphrase = "temp"
        viewModel.creationPassphraseConfirmation = "temp"
        viewModel.exportDocument = FinSightBackupExportDocument(encryptedData: Data([0x01]))
        viewModel.isPresentingBackupExporter = true

        viewModel.backupExportCompleted(success: true)

        #expect(viewModel.creationPassphrase.isEmpty)
        #expect(viewModel.exportDocument == nil)
        #expect(viewModel.isPresentingBackupExporter == false)
    }
}

private final class RefreshCallbackTracker: @unchecked Sendable {
    private let callback: @Sendable () -> Void
    private(set) var invoked = false

    init(callback: @escaping @Sendable () -> Void) {
        self.callback = callback
    }

    func invoke() {
        invoked = true
        callback()
    }
}

private final class RefreshTracker: @unchecked Sendable {
    private(set) var invoked = false

    func markInvoked() {
        invoked = true
    }
}
