import Foundation
import YoushuDomain

/// Semantic and referential validation for decoded portable backup payloads.
///
/// Mirrors `YoushuStore` upsert invariants so restore preflight does not accept payloads
/// that the live store would reject. Reused by restore commit in a later step.
public enum BackupPayloadV1Validator {
    public static func validate(_ payload: BackupPayloadV1) throws {
        guard payload.metadata.formatVersion == BackupPayloadV1.formatVersion else {
            throw BackupPayloadValidationError.unsupportedPayloadFormat(
                found: payload.metadata.formatVersion,
                supported: BackupPayloadV1.formatVersion
            )
        }

        let data = payload.financialData

        try validateUniqueIDs(data.users.map(\.id), entityType: "User")
        try validateUniqueIDs(data.accounts.map(\.id), entityType: "Account")
        try validateUniqueIDs(data.transactions.map(\.id), entityType: "Transaction")
        try validateUniqueIDs(data.assets.map(\.id), entityType: "Asset")
        try validateUniqueIDs(data.debts.map(\.id), entityType: "Debt")
        try validateUniqueIDs(data.debtEvents.map(\.id), entityType: "DebtEvent")
        try validateUniqueIDs(data.repaymentPlans.map(\.id), entityType: "RepaymentPlan")
        try validateUniqueIDs(data.budgets.map(\.id), entityType: "Budget")
        try validateUniqueIDs(data.goals.map(\.id), entityType: "Goal")
        try validateUniqueIDs(data.subscriptions.map(\.id), entityType: "Subscription")

        let userIDs = Set(data.users.map(\.id))
        let accountsByID = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
        let debtsByID = Dictionary(uniqueKeysWithValues: data.debts.map { ($0.id, $0) })
        let transactionsByID = Dictionary(uniqueKeysWithValues: data.transactions.map { ($0.id, $0) })

        try requireOwners(userIDs: userIDs, entityType: "Account", ownerIDs: data.accounts.map(\.userId))
        try requireOwners(userIDs: userIDs, entityType: "Transaction", ownerIDs: data.transactions.map(\.userId))
        try requireOwners(userIDs: userIDs, entityType: "Asset", ownerIDs: data.assets.map(\.userId))
        try requireOwners(userIDs: userIDs, entityType: "Debt", ownerIDs: data.debts.map(\.userId))
        try requireOwners(userIDs: userIDs, entityType: "DebtEvent", ownerIDs: data.debtEvents.map(\.userId))
        try requireOwners(
            userIDs: userIDs,
            entityType: "RepaymentPlan",
            ownerIDs: data.repaymentPlans.map(\.userId)
        )
        try requireOwners(userIDs: userIDs, entityType: "Budget", ownerIDs: data.budgets.map(\.userId))
        try requireOwners(userIDs: userIDs, entityType: "Goal", ownerIDs: data.goals.map(\.userId))
        try requireOwners(
            userIDs: userIDs,
            entityType: "Subscription",
            ownerIDs: data.subscriptions.map(\.userId)
        )

        for transaction in data.transactions {
            guard let account = accountsByID[transaction.accountId] else {
                throw BackupPayloadValidationError.invalidReference(field: "Transaction.accountId")
            }
            guard account.userId == transaction.userId else {
                throw BackupPayloadValidationError.crossUserReference(field: "Transaction.accountId")
            }
            if let debtId = transaction.relatedDebtId {
                guard let debt = debtsByID[debtId] else {
                    throw BackupPayloadValidationError.invalidReference(field: "Transaction.relatedDebtId")
                }
                guard debt.userId == transaction.userId else {
                    throw BackupPayloadValidationError.crossUserReference(field: "Transaction.relatedDebtId")
                }
            }
        }

        for event in data.debtEvents {
            guard let debt = debtsByID[event.debtId] else {
                throw BackupPayloadValidationError.invalidReference(field: "DebtEvent.debtId")
            }
            guard debt.userId == event.userId else {
                throw BackupPayloadValidationError.crossUserReference(field: "DebtEvent.debtId")
            }
            if let transactionId = event.relatedTransactionId {
                guard let transaction = transactionsByID[transactionId] else {
                    throw BackupPayloadValidationError.invalidReference(field: "DebtEvent.relatedTransactionId")
                }
                guard transaction.userId == event.userId else {
                    throw BackupPayloadValidationError.crossUserReference(field: "DebtEvent.relatedTransactionId")
                }
            }
        }

        for plan in data.repaymentPlans {
            guard let debt = debtsByID[plan.debtId] else {
                throw BackupPayloadValidationError.invalidReference(field: "RepaymentPlan.debtId")
            }
            guard debt.userId == plan.userId else {
                throw BackupPayloadValidationError.crossUserReference(field: "RepaymentPlan.debtId")
            }
        }
    }

    private static func validateUniqueIDs(_ ids: [UUID], entityType: String) throws {
        guard ids.count == Set(ids).count else {
            throw BackupPayloadValidationError.duplicateEntityId(entityType: entityType)
        }
    }

    private static func requireOwners(
        userIDs: Set<UUID>,
        entityType: String,
        ownerIDs: [UUID]
    ) throws {
        for ownerID in ownerIDs where !userIDs.contains(ownerID) {
            throw BackupPayloadValidationError.missingRequiredOwner(entityType: entityType)
        }
    }
}
