import Foundation

/// Production use-case for full-replace restore commit from encrypted backup bytes.
///
/// Re-decodes and re-validates the original input; preflight preview is not an authorization token.
public protocol BackupRestoring: Sendable {
    func restoreBackup(data: Data, passphrase: String) async throws -> BackupRestoreResult
}
