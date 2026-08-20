import Foundation
import YoushuDomain

/// Non-presentation restore workflow phases for Backup / Restore v1.
public enum BackupRestoreFlowPhase: Equatable, Sendable {
    case idle
    case importing
    case awaitingPassphrase
    case preflighting
    case preview(BackupRestorePreview)
    case confirmingDestructiveRestore(BackupRestorePreview)
    case restoring
    case refreshingApplication
    case success(BackupRestoreResult)
    case failed(message: String, category: BackupRestoreFailureCategory?)
    case criticalFailure
}

/// Orchestrates restore preflight → confirmation → commit using immutable encrypted bytes.
///
/// Keeps passphrase and encrypted payload in memory only for the active flow and clears them
/// on cancel, failure, or success. Does not own SwiftUI state.
@MainActor
public final class BackupRestoreFlowEngine {
    public private(set) var phase: BackupRestoreFlowPhase = .idle

    private let preflightService: any BackupRestorePreflighting
    private let restoreService: any BackupRestoring
    private let applicationRefresh: () async throws -> Void

    private var encryptedData: Data?
    private var passphrase = ""
    private var isOperationInFlight = false

    public init(
        preflightService: any BackupRestorePreflighting,
        restoreService: any BackupRestoring,
        applicationRefresh: @escaping () async throws -> Void
    ) {
        self.preflightService = preflightService
        self.restoreService = restoreService
        self.applicationRefresh = applicationRefresh
    }

    public var hasImportedEncryptedData: Bool {
        encryptedData != nil
    }

    public var importedEncryptedDataForTesting: Data? {
        encryptedData
    }

    public func beginImport() {
        guard !isOperationInFlight else { return }
        clearSensitiveState()
        phase = .importing
    }

    public func importFailed(message: String) {
        clearSensitiveState()
        phase = .failed(message: message, category: nil)
    }

    public func fileImported(_ data: Data) {
        guard case .importing = phase else { return }
        encryptedData = data
        phase = .awaitingPassphrase
    }

    public func updatePassphrase(_ value: String) {
        passphrase = value
    }

    public func submitPassphrase() async {
        guard case .awaitingPassphrase = phase else { return }
        guard !isOperationInFlight else { return }
        guard let encryptedData else {
            phase = .failed(message: "未选择备份文件。", category: nil)
            return
        }
        guard !passphrase.isEmpty else {
            phase = .failed(message: BackupUserFacingErrorMapper.message(for: BackupError.invalidPassphrase), category: .validationFailure)
            return
        }

        isOperationInFlight = true
        phase = .preflighting
        defer { isOperationInFlight = false }

        do {
            let preview = try await preflightService.preflight(data: encryptedData, passphrase: passphrase)
            phase = .preview(preview)
        } catch {
            phase = failurePhase(for: error)
        }
    }

    public func proceedToDestructiveConfirmation() {
        guard case let .preview(preview) = phase else { return }
        phase = .confirmingDestructiveRestore(preview)
    }

    public func confirmRestore() async {
        guard case .confirmingDestructiveRestore = phase else { return }
        guard !isOperationInFlight else { return }
        guard let encryptedData else {
            phase = .failed(message: "未选择备份文件。", category: nil)
            return
        }

        isOperationInFlight = true
        phase = .restoring
        defer { isOperationInFlight = false }

        do {
            let result = try await restoreService.restoreBackup(data: encryptedData, passphrase: passphrase)
            phase = .refreshingApplication
            try await applicationRefresh()
            clearPassphrase()
            self.encryptedData = nil
            phase = .success(result)
        } catch {
            if BackupRestoreFailureClassifier.isCriticalPersistenceFailure(error) {
                clearSensitiveState()
                phase = .criticalFailure
            } else {
                phase = failurePhase(for: error)
            }
        }
    }

    public func cancel() {
        clearSensitiveState()
        phase = .idle
    }

    public func dismissOutcome() {
        switch phase {
        case .success, .failed, .criticalFailure:
            clearSensitiveState()
            phase = .idle
        default:
            break
        }
    }

    public var isBusy: Bool {
        switch phase {
        case .importing, .preflighting, .restoring, .refreshingApplication:
            true
        default:
            isOperationInFlight
        }
    }

    private func failurePhase(for error: Error) -> BackupRestoreFlowPhase {
        let category = BackupRestoreFailureClassifier.classify(error)
        let message = BackupUserFacingErrorMapper.message(for: error)
        return .failed(message: message, category: category)
    }

    private func clearSensitiveState() {
        encryptedData = nil
        clearPassphrase()
        isOperationInFlight = false
    }

    private func clearPassphrase() {
        passphrase = ""
    }
}
