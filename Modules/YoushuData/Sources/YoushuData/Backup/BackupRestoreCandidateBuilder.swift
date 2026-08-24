import Foundation
import YoushuDomain

/// Maps a validated portable backup payload into an in-memory restore candidate snapshot.
///
/// This is not live restore: callers must not persist the returned value during preflight.
public enum BackupRestoreCandidateBuilder {
    public static func build(from payload: BackupPayloadV1) -> YoushuSnapshot {
        YoushuSnapshot(
            schemaVersion: YoushuSnapshot.currentSchemaVersion,
            users: payload.financialData.users.map(makeUser),
            accounts: payload.financialData.accounts,
            transactions: payload.financialData.transactions,
            assets: payload.financialData.assets,
            debts: payload.financialData.debts,
            debtEvents: payload.financialData.debtEvents,
            repaymentPlans: payload.financialData.repaymentPlans,
            budgets: payload.financialData.budgets,
            goals: payload.financialData.goals,
            subscriptions: payload.financialData.subscriptions,
            insights: [],
            pendingDebtLinks: [],
            suspectedDebts: [],
            aiDataConsents: [],
            aiRecognitionRecords: [],
            mediaArtifacts: [],
            confirmedImportProvenances: []
        )
    }

    private static func makeUser(_ backupUser: BackupUserV1) -> User {
        User(
            id: backupUser.id,
            displayName: backupUser.displayName,
            preferredCurrency: backupUser.preferredCurrency,
            debtInventoryEstablishment: backupUser.debtInventoryEstablishment,
            debtInventoryEstablishmentSource: backupUser.debtInventoryEstablishmentSource,
            debtInventoryEstablishedAt: backupUser.debtInventoryEstablishedAt,
            debtImportInProgress: false,
            createdAt: backupUser.createdAt,
            updatedAt: backupUser.updatedAt
        )
    }
}
