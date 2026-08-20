import Foundation
import YoushuDomain

/// Full-replace restore commit: re-decode, re-validate, transactional store replacement.
public struct BackupRestoreService: BackupRestoring, Sendable {
    private let store: YoushuStore
    private let restoredAtProvider: @Sendable () -> Date

    public init(
        store: YoushuStore,
        restoredAtProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.restoredAtProvider = restoredAtProvider
    }

    public func restoreBackup(data: Data, passphrase: String) async throws -> BackupRestoreResult {
        let previousUserIDs = Set((await store.currentSnapshot()).users.map(\.id))
        let (payload, candidate) = try BackupRestoreValidationPipeline.decodeValidateAndBuild(
            data: data,
            passphrase: passphrase
        )
        try await store.replaceSnapshotForRestore(candidate)

        let restoredUserIDs = Set(candidate.users.map(\.id))
        let userIdentityChanged = previousUserIDs != restoredUserIDs
        return BackupRestoreResult(
            restoredAt: restoredAtProvider(),
            backupCreatedAt: payload.metadata.createdAt,
            counts: BackupRestoreEntityCounts(
                users: candidate.users.count,
                accounts: candidate.accounts.count,
                transactions: candidate.transactions.count,
                debts: candidate.debts.count,
                repaymentPlans: candidate.repaymentPlans.count,
                debtEvents: candidate.debtEvents.count,
                assets: candidate.assets.count,
                goals: candidate.goals.count,
                budgets: candidate.budgets.count,
                subscriptions: candidate.subscriptions.count
            ),
            requiresApplicationReload: true,
            userIdentityChanged: userIdentityChanged
        )
    }
}
