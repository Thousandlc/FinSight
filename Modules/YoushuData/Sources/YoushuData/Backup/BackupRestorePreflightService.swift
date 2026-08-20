import Foundation
import YoushuDomain

/// Side-effect-free restore preflight: decrypt → validate → build candidate → safe preview.
///
/// Deliberately holds no `YoushuStore` dependency so live persistence cannot be mutated.
public struct BackupRestorePreflightService: BackupRestorePreflighting, Sendable {
    public init() {}

    public func preflight(data: Data, passphrase: String) async throws -> BackupRestorePreview {
        let (payload, candidate) = try BackupRestoreValidationPipeline.decodeValidateAndBuild(
            data: data,
            passphrase: passphrase
        )
        return makePreview(from: payload, candidate: candidate)
    }

    private func makePreview(from payload: BackupPayloadV1, candidate: YoushuSnapshot) -> BackupRestorePreview {
        BackupRestorePreview(
            createdAt: payload.metadata.createdAt,
            formatVersion: payload.metadata.formatVersion,
            sourceStoreSchemaVersion: payload.metadata.sourceStoreSchemaVersion,
            sourceAppVersion: payload.metadata.sourceAppVersion,
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
            restoreMode: .fullReplace
        )
    }
}
