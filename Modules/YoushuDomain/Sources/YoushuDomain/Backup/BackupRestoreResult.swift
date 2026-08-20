import Foundation

/// Safe operational result after a successful full-replace restore commit.
public struct BackupRestoreResult: Sendable, Equatable {
    public let restoredAt: Date
    public let backupCreatedAt: Date
    public let counts: BackupRestoreEntityCounts
    /// Always true after successful full-replace restore; callers must refresh session and ViewModels.
    public let requiresApplicationReload: Bool
    /// True when restored user IDs differ from pre-restore IDs (identity handoff).
    public let userIdentityChanged: Bool

    public init(
        restoredAt: Date,
        backupCreatedAt: Date,
        counts: BackupRestoreEntityCounts,
        requiresApplicationReload: Bool,
        userIdentityChanged: Bool
    ) {
        self.restoredAt = restoredAt
        self.backupCreatedAt = backupCreatedAt
        self.counts = counts
        self.requiresApplicationReload = requiresApplicationReload
        self.userIdentityChanged = userIdentityChanged
    }
}
