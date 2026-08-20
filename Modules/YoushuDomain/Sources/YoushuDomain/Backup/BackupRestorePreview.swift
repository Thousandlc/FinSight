import Foundation

/// Entity counts shown in restore confirmation UI — no names, amounts, or identifiers.
public struct BackupRestoreEntityCounts: Sendable, Equatable {
    public var users: Int
    public var accounts: Int
    public var transactions: Int
    public var debts: Int
    public var repaymentPlans: Int
    public var debtEvents: Int
    public var assets: Int
    public var goals: Int
    public var budgets: Int
    public var subscriptions: Int

    public init(
        users: Int = 0,
        accounts: Int = 0,
        transactions: Int = 0,
        debts: Int = 0,
        repaymentPlans: Int = 0,
        debtEvents: Int = 0,
        assets: Int = 0,
        goals: Int = 0,
        budgets: Int = 0,
        subscriptions: Int = 0
    ) {
        self.users = users
        self.accounts = accounts
        self.transactions = transactions
        self.debts = debts
        self.repaymentPlans = repaymentPlans
        self.debtEvents = debtEvents
        self.assets = assets
        self.goals = goals
        self.budgets = budgets
        self.subscriptions = subscriptions
    }
}

/// Restore mode supported by Backup / Restore v1.
public enum BackupRestoreMode: String, Sendable, Equatable {
    case fullReplace
}

/// Safe restore preflight summary for confirmation UI.
///
/// Carries no passphrase, decrypted payload, entity names, amounts, notes, or UUIDs.
public struct BackupRestorePreview: Sendable, Equatable {
    public var createdAt: Date
    public var formatVersion: Int
    public var sourceStoreSchemaVersion: Int
    public var sourceAppVersion: String?
    public var counts: BackupRestoreEntityCounts
    public var restoreMode: BackupRestoreMode

    public init(
        createdAt: Date,
        formatVersion: Int,
        sourceStoreSchemaVersion: Int,
        sourceAppVersion: String? = nil,
        counts: BackupRestoreEntityCounts,
        restoreMode: BackupRestoreMode = .fullReplace
    ) {
        self.createdAt = createdAt
        self.formatVersion = formatVersion
        self.sourceStoreSchemaVersion = sourceStoreSchemaVersion
        self.sourceAppVersion = sourceAppVersion
        self.counts = counts
        self.restoreMode = restoreMode
    }
}
