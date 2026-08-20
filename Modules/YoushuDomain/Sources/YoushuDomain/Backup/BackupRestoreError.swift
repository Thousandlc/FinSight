import Foundation

/// Restore commit failures distinct from backup decode/semantic validation errors.
///
/// No case carries passphrase material, UUID values, or financial content.
public enum BackupRestoreError: Error, Equatable, Sendable {
    case commitPersistenceFailure
    case postWriteVerificationFailure
    case rollbackFailed
}
