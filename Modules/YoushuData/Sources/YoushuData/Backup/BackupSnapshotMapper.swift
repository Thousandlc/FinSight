import Foundation
import YoushuDomain
import YoushuFoundation

/// Maps the local persistence snapshot into the portable backup contract.
///
/// The store model deliberately does not conform to the backup contract; this mapper is the
/// only boundary where `YoushuSnapshot` becomes `BackupPayloadV1`, so exclusions are enforced
/// in one reviewable place.
public enum BackupSnapshotMapper {
    public static func makePayload(
        from snapshot: YoushuSnapshot,
        createdAt: Date = Date(),
        sourceAppVersion: String? = nil
    ) -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: createdAt,
                sourceStoreSchemaVersion: snapshot.schemaVersion,
                sourceAppVersion: sourceAppVersion
            ),
            financialData: BackupFinancialDataV1(
                users: snapshot.users.map(makeBackupUser),
                accounts: snapshot.accounts,
                transactions: snapshot.transactions,
                assets: snapshot.assets,
                debts: snapshot.debts,
                debtEvents: snapshot.debtEvents,
                repaymentPlans: snapshot.repaymentPlans,
                budgets: snapshot.budgets,
                goals: snapshot.goals,
                subscriptions: snapshot.subscriptions
            )
        )
    }

    private static func makeBackupUser(_ user: User) -> BackupUserV1 {
        BackupUserV1(
            id: user.id,
            displayName: user.displayName,
            preferredCurrency: user.preferredCurrency,
            debtInventoryEstablishment: user.debtInventoryEstablishment,
            debtInventoryEstablishmentSource: user.debtInventoryEstablishmentSource,
            debtInventoryEstablishedAt: user.debtInventoryEstablishedAt,
            createdAt: user.createdAt,
            updatedAt: user.updatedAt
        )
    }
}
