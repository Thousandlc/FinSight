import Foundation
import YoushuDomain

/// Versioned local snapshot. Schema migrations bump `schemaVersion`.
///
/// ## Migration
/// - **v1 → v2**: 新增 `pendingDebtLinks`、`suspectedDebts`。
/// - **v2 → v3**: 新增 `aiDataConsents`、`aiRecognitionRecords`、`mediaArtifacts`（隐私 / 识别审计 / 媒体元数据，默认不含原图二进制）。
/// - **v3 → v4**: `User.debtInventoryEstablishment` 等债务清单语义字段；迁移默认 `unestablished`（不根据 `debts.count` 推断）。
public struct YoushuSnapshot: Codable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var users: [User]
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var assets: [Asset]
    public var debts: [Debt]
    public var debtEvents: [DebtEvent]
    public var repaymentPlans: [RepaymentPlan]
    public var budgets: [Budget]
    public var goals: [Goal]
    public var subscriptions: [Subscription]
    public var insights: [FinancialInsight]
    public var pendingDebtLinks: [PendingDebtLink]
    public var suspectedDebts: [SuspectedDebt]
    public var aiDataConsents: [AIDataConsent]
    public var aiRecognitionRecords: [AIRecognitionRecord]
    public var mediaArtifacts: [MediaArtifact]

    public init(
        schemaVersion: Int = YoushuSnapshot.currentSchemaVersion,
        users: [User] = [],
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        assets: [Asset] = [],
        debts: [Debt] = [],
        debtEvents: [DebtEvent] = [],
        repaymentPlans: [RepaymentPlan] = [],
        budgets: [Budget] = [],
        goals: [Goal] = [],
        subscriptions: [Subscription] = [],
        insights: [FinancialInsight] = [],
        pendingDebtLinks: [PendingDebtLink] = [],
        suspectedDebts: [SuspectedDebt] = [],
        aiDataConsents: [AIDataConsent] = [],
        aiRecognitionRecords: [AIRecognitionRecord] = [],
        mediaArtifacts: [MediaArtifact] = []
    ) {
        self.schemaVersion = schemaVersion
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
        self.insights = insights
        self.pendingDebtLinks = pendingDebtLinks
        self.suspectedDebts = suspectedDebts
        self.aiDataConsents = aiDataConsents
        self.aiRecognitionRecords = aiRecognitionRecords
        self.mediaArtifacts = mediaArtifacts
    }

    public static var empty: YoushuSnapshot { YoushuSnapshot() }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, users, accounts, transactions, assets, debts, debtEvents
        case repaymentPlans, budgets, goals, subscriptions, insights
        case pendingDebtLinks, suspectedDebts
        case aiDataConsents, aiRecognitionRecords, mediaArtifacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        users = try container.decodeIfPresent([User].self, forKey: .users) ?? []
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        transactions = try container.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        debts = try container.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        debtEvents = try container.decodeIfPresent([DebtEvent].self, forKey: .debtEvents) ?? []
        repaymentPlans = try container.decodeIfPresent([RepaymentPlan].self, forKey: .repaymentPlans) ?? []
        budgets = try container.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
        goals = try container.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        subscriptions = try container.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        insights = try container.decodeIfPresent([FinancialInsight].self, forKey: .insights) ?? []
        pendingDebtLinks = try container.decodeIfPresent([PendingDebtLink].self, forKey: .pendingDebtLinks) ?? []
        suspectedDebts = try container.decodeIfPresent([SuspectedDebt].self, forKey: .suspectedDebts) ?? []
        aiDataConsents = try container.decodeIfPresent([AIDataConsent].self, forKey: .aiDataConsents) ?? []
        aiRecognitionRecords = try container.decodeIfPresent([AIRecognitionRecord].self, forKey: .aiRecognitionRecords) ?? []
        mediaArtifacts = try container.decodeIfPresent([MediaArtifact].self, forKey: .mediaArtifacts) ?? []
    }
}
