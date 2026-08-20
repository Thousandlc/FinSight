import Foundation

/// Application-facing restore failure categories for future UI handling.
public enum BackupRestoreFailureCategory: Equatable, Sendable {
    /// Decode, authentication, envelope, or semantic payload validation failure.
    case validationFailure
    /// Restore commit persistence or post-write verification failure (rollback succeeded).
    case commitFailure
    /// Rollback could not restore prior durable state; store integrity may be uncertain.
    case criticalPersistenceFailure
}

public enum BackupRestoreFailureClassifier {
    public static func classify(_ error: Error) -> BackupRestoreFailureCategory? {
        if let restoreError = error as? BackupRestoreError {
            switch restoreError {
            case .rollbackFailed:
                return .criticalPersistenceFailure
            case .commitPersistenceFailure, .postWriteVerificationFailure:
                return .commitFailure
            }
        }
        if error is BackupError {
            return .validationFailure
        }
        if error is BackupPayloadValidationError {
            return .validationFailure
        }
        return nil
    }

    public static func isCriticalPersistenceFailure(_ error: Error) -> Bool {
        classify(error) == .criticalPersistenceFailure
    }
}
