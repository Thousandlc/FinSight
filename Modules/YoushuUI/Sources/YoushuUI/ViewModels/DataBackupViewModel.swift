import Foundation
import YoushuData
import YoushuDomain

public enum BackupCreationPhase: Equatable, Sendable {
    case idle
    case enteringPassphrase
    case creating
    case readyToExport(CreatedBackup)
    case failed(message: String)
}

@Observable
@MainActor
public final class DataBackupViewModel {
    public var creationPhase: BackupCreationPhase = .idle
    public var restoreEngine: BackupRestoreFlowEngine

    public var creationPassphrase = ""
    public var creationPassphraseConfirmation = ""
    public var creationValidationError: String?

    public var restorePassphrase = ""
    public var restoreOutcomeMessage: String?
    public var restoreIdentityChanged = false

    public var isPresentingRestoreImporter = false
    public var isPresentingBackupExporter = false
    public var exportDocument: FinSightBackupExportDocument?
    public var exportFilename = "FinSight-Backup.finsightbackup"

    private let backupCreation: BackupCreationService
    private let fileReader: BackupImportFileReader
    private var isCreatingBackup = false

    public init(
        backupCreation: BackupCreationService,
        backupRestorePreflight: BackupRestorePreflightService,
        backupRestore: BackupRestoreService,
        applicationRefresh: @escaping () async throws -> Void,
        fileReader: BackupImportFileReader = BackupImportFileReader()
    ) {
        self.backupCreation = backupCreation
        self.fileReader = fileReader
        self.restoreEngine = BackupRestoreFlowEngine(
            preflightService: backupRestorePreflight,
            restoreService: backupRestore,
            applicationRefresh: applicationRefresh
        )
    }

    public var isBackupCreationBusy: Bool {
        if case .creating = creationPhase { return true }
        return isCreatingBackup
    }

    public func presentBackupCreation() {
        resetBackupCreationState()
        creationPhase = .enteringPassphrase
    }

    public func cancelBackupCreation() {
        resetBackupCreationState()
        creationPhase = .idle
    }

    public func validateCreationPassphrasesLocally() -> Bool {
        creationValidationError = nil
        guard !creationPassphrase.isEmpty else {
            creationValidationError = "请输入备份密码。"
            return false
        }
        guard creationPassphrase == creationPassphraseConfirmation else {
            creationValidationError = "两次输入的密码不一致。"
            return false
        }
        return true
    }

    public func createBackup() async {
        guard !isCreatingBackup else { return }
        guard validateCreationPassphrasesLocally() else { return }

        isCreatingBackup = true
        creationPhase = .creating
        defer { isCreatingBackup = false }

        do {
            let created = try await backupCreation.createBackup(passphrase: creationPassphrase)
            clearCreationPassphrases()
            exportDocument = FinSightBackupExportDocument(encryptedData: created.data)
            exportFilename = created.suggestedFilename
            creationPhase = .readyToExport(created)
            isPresentingBackupExporter = true
        } catch {
            clearCreationPassphrases()
            creationPhase = .failed(message: BackupUserFacingErrorMapper.backupCreationMessage(for: error))
        }
    }

    public func backupExportCompleted(success: Bool) {
        isPresentingBackupExporter = false
        exportDocument = nil
        resetBackupCreationState()
        creationPhase = .idle
        if !success {
            // User cancellation is not an error; only clear state.
        }
    }

    public func beginRestoreImport() {
        guard !restoreEngine.isBusy else { return }
        restoreOutcomeMessage = nil
        restoreIdentityChanged = false
        restorePassphrase = ""
        restoreEngine.beginImport()
        isPresentingRestoreImporter = true
    }

    public func handleRestoreImportResult(_ result: Result<URL, Error>) {
        isPresentingRestoreImporter = false
        switch result {
        case .success(let url):
            do {
                let data = try fileReader.readBoundedData(from: url)
                restoreEngine.fileImported(data)
            } catch let error as BackupImportFileReaderError {
                restoreEngine.importFailed(message: importErrorMessage(for: error))
            } catch {
                restoreEngine.importFailed(message: "无法读取备份文件，请稍后重试。")
            }
        case .failure:
            restoreEngine.cancel()
        }
    }

    public func updateRestorePassphrase(_ value: String) {
        restorePassphrase = value
        restoreEngine.updatePassphrase(value)
    }

    public func submitRestorePassphrase() async {
        restoreEngine.updatePassphrase(restorePassphrase)
        await restoreEngine.submitPassphrase()
    }

    public func confirmRestore() async {
        await restoreEngine.confirmRestore()
        if case let .success(result) = restoreEngine.phase {
            restoreIdentityChanged = result.userIdentityChanged
            if result.userIdentityChanged {
                restoreOutcomeMessage = "已恢复备份数据，当前账户身份已切换。"
            }
        }
    }

    public func cancelRestoreFlow() {
        restorePassphrase = ""
        restoreEngine.cancel()
    }

    public func dismissRestoreOutcome() {
        restorePassphrase = ""
        restoreOutcomeMessage = nil
        restoreIdentityChanged = false
        restoreEngine.dismissOutcome()
    }

    private func resetBackupCreationState() {
        clearCreationPassphrases()
        creationValidationError = nil
        exportDocument = nil
        isPresentingBackupExporter = false
    }

    private func clearCreationPassphrases() {
        creationPassphrase = ""
        creationPassphraseConfirmation = ""
    }

    private func importErrorMessage(for error: BackupImportFileReaderError) -> String {
        switch error {
        case .accessDenied:
            return "无法访问所选文件，请重新选择。"
        case .readFailed:
            return "无法读取备份文件，请稍后重试。"
        case .emptyFile:
            return "所选文件为空，请选择有效的备份文件。"
        case .fileTooLarge:
            return "备份文件过大，无法处理。"
        }
    }
}
