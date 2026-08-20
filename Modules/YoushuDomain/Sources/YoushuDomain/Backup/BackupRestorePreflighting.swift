import Foundation

/// Production use-case for validating an encrypted backup before destructive restore.
///
/// Preflight decrypts and semantically validates untrusted backup bytes and returns a safe
/// preview. It must not mutate the live store or retain decrypted financial content.
public protocol BackupRestorePreflighting: Sendable {
    func preflight(data: Data, passphrase: String) async throws -> BackupRestorePreview
}
