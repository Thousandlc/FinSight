import Foundation

/// Portable backup format errors.
///
/// No case carries passphrase material, derived keys, or decrypted financial content.
/// Diagnostic strings are fixed literals chosen at the throw site, never untrusted file content.
public enum BackupError: Error, Equatable, Sendable {
    case unsupportedFormat(found: Int, supported: Int)
    case unsupportedAlgorithm(field: String)
    case invalidCryptoParameter(field: String)
    case invalidPassphrase
    case backupTooLarge(byteCount: Int, limit: Int)
    case malformedEnvelope(String)
    case authenticationFailure
    case payloadDecodeFailure(String)
}

/// Independently versioned portable backup payload.
///
/// This is deliberately **not** a serialization of `YoushuSnapshot`: the backup format
/// version evolves independently of the local JSON store schema version.
public struct BackupPayloadV1: Codable, Sendable, Equatable {
    public static let formatVersion = 1

    public var metadata: BackupPayloadMetadataV1
    public var financialData: BackupFinancialDataV1

    public init(metadata: BackupPayloadMetadataV1, financialData: BackupFinancialDataV1) {
        self.metadata = metadata
        self.financialData = financialData
    }
}

public struct BackupPayloadMetadataV1: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var createdAt: Date
    public var sourceStoreSchemaVersion: Int
    public var sourceAppVersion: String?

    public init(
        formatVersion: Int = BackupPayloadV1.formatVersion,
        createdAt: Date,
        sourceStoreSchemaVersion: Int,
        sourceAppVersion: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.sourceStoreSchemaVersion = sourceStoreSchemaVersion
        self.sourceAppVersion = sourceAppVersion
    }
}

/// Minimal user representation required to preserve owner foreign keys after restore.
///
/// Deliberately narrower than the persisted `User`: `debtImportInProgress` is transient
/// operational state tied to an in-flight import session on the source device and is not a
/// portable financial fact. AI consent and privacy authorization are stored separately in
/// `AIDataConsent` and never reach this type.
public struct BackupUserV1: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var preferredCurrency: String
    public var debtInventoryEstablishment: DebtInventoryEstablishmentState
    public var debtInventoryEstablishmentSource: DebtInventoryEstablishmentSource?
    public var debtInventoryEstablishedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        displayName: String,
        preferredCurrency: String,
        debtInventoryEstablishment: DebtInventoryEstablishmentState,
        debtInventoryEstablishmentSource: DebtInventoryEstablishmentSource? = nil,
        debtInventoryEstablishedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredCurrency = preferredCurrency
        self.debtInventoryEstablishment = debtInventoryEstablishment
        self.debtInventoryEstablishmentSource = debtInventoryEstablishmentSource
        self.debtInventoryEstablishedAt = debtInventoryEstablishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// User-owned financial facts required to reconstruct the confirmed ledger.
///
/// Excluded by design: `FinancialInsight`, AI recognition audit records, `AIDataConsent`,
/// media artifacts, derived read models, and detector candidates awaiting user confirmation
/// (`PendingDebtLink`, `SuspectedDebt`) — the latter are regenerable from transactions and
/// debts and are referenced by no confirmed entity.
public struct BackupFinancialDataV1: Codable, Sendable, Equatable {
    public var users: [BackupUserV1]
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var assets: [Asset]
    public var debts: [Debt]
    public var debtEvents: [DebtEvent]
    public var repaymentPlans: [RepaymentPlan]
    public var budgets: [Budget]
    public var goals: [Goal]
    public var subscriptions: [Subscription]

    public init(
        users: [BackupUserV1] = [],
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        assets: [Asset] = [],
        debts: [Debt] = [],
        debtEvents: [DebtEvent] = [],
        repaymentPlans: [RepaymentPlan] = [],
        budgets: [Budget] = [],
        goals: [Goal] = [],
        subscriptions: [Subscription] = []
    ) {
        self.users = users
        self.accounts = accounts
        self.transactions = transactions
        self.assets = assets
        self.debts = debts
        self.debtEvents = debtEvents
        self.repaymentPlans = repaymentPlans
        self.budgets = budgets
        self.goals = goals
        self.subscriptions = subscriptions
    }
}
