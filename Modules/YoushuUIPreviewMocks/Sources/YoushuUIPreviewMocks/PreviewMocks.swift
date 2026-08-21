import Foundation
import YoushuAI
import YoushuData
import YoushuDesignSystem
import YoushuDomain
import YoushuFoundation
import YoushuUI

/// Preview / development mocks. Never linked as production data source.
public enum PreviewMockData {
    public static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public static var homeOverview: HomeOverview {
        makeHomeOverview(includeRisk: false, includeTransactions: true)
    }

    public static var homeOverviewWithRisk: HomeOverview {
        makeHomeOverview(includeRisk: true, includeTransactions: true)
    }

    public static var homeOverviewInsufficientData: HomeOverview {
        makeHomeOverview(includeRisk: false, includeTransactions: false)
    }

    public static var homeOverviewEmptyCashFlow: HomeOverview {
        HomeOverview(
            availableFunds: Money(amount: 28_650.32, currencyCode: "CNY"),
            monthlyIncome: .zeroCNY,
            monthlyLivingExpense: .zeroCNY,
            monthlyDebtRepayment: .zeroCNY,
            projectedMonthEndBalance: Money(amount: 28_650.32, currencyCode: "CNY"),
            financialHealthScore: nil,
            aiSummary: nil,
            cashFlowProjections: [],
            cashFlowRisk: nil,
            hasAccounts: true,
            hasTransactions: false
        )
    }

    private static func makeHomeOverview(includeRisk: Bool, includeTransactions: Bool) -> HomeOverview {
        let account = Account(
            userId: userId,
            name: "工资卡",
            type: .bankCard,
            openingBalance: Money(amount: includeRisk ? 7_000 : 28_650.32, currencyCode: "CNY")
        )
        var transactions: [Transaction] = []
        if includeTransactions {
            transactions = [
                Transaction(
                    userId: userId,
                    accountId: account.id,
                    amount: Money(amount: 18_000, currencyCode: "CNY"),
                    date: Date().addingTimeInterval(-86400 * 5),
                    merchant: "工资入账",
                    category: "工资",
                    transactionType: .income,
                    source: .manual
                ),
                Transaction(
                    userId: userId,
                    accountId: account.id,
                    amount: Money(amount: 6_240.50, currencyCode: "CNY"),
                    date: Date().addingTimeInterval(-86400 * 3),
                    merchant: "生活支出",
                    category: "生活",
                    transactionType: .expense,
                    source: .manual
                ),
            ]
        }

        var debts: [Debt] = []
        if includeRisk {
            debts = [
                Debt(
                    userId: userId,
                    lender: "招商银行",
                    productName: "信用卡",
                    debtType: .creditCard,
                    outstandingBalance: Money(amount: 8_000, currencyCode: "CNY"),
                    installmentAmount: Money(amount: 3_500, currencyCode: "CNY"),
                    paymentFrequency: .monthly,
                    dueDate: Date().addingTimeInterval(86400 * 18),
                    status: .active,
                    source: .userInput
                ),
            ]
            if includeTransactions {
                transactions.append(
                    Transaction(
                        userId: userId,
                        accountId: account.id,
                        amount: Money(amount: 4_000, currencyCode: "CNY"),
                        date: Date().addingTimeInterval(-86400 * 14),
                        merchant: "房租",
                        category: "住房",
                        transactionType: .expense,
                        recurringRule: RecurringRule(
                            frequency: .monthly,
                            nextDate: Date().addingTimeInterval(86400 * 18)
                        ),
                        source: .manual
                    )
                )
            }
        }

        let projections = CashFlowEngine.projectAllHorizons(
            .init(
                accounts: [account],
                transactions: transactions,
                debts: debts,
                safeBalance: Money(amount: 2_000, currencyCode: "CNY")
            )
        )
        let primaryRisk = projections.first(where: { $0.horizon == .days30 })?.risk
            ?? projections.compactMap(\.risk).first

        return HomeOverview(
            availableFunds: Money(amount: includeRisk ? 3_000 : 28_650.32, currencyCode: "CNY"),
            monthlyIncome: includeTransactions ? Money(amount: 18_000, currencyCode: "CNY") : .zeroCNY,
            monthlyLivingExpense: includeTransactions ? Money(amount: 6_240.50, currencyCode: "CNY") : .zeroCNY,
            monthlyDebtRepayment: includeRisk ? Money(amount: 2_100, currencyCode: "CNY") : .zeroCNY,
            projectedMonthEndBalance: Money(amount: includeRisk ? 1_500 : 38_309.82, currencyCode: "CNY"),
            financialHealthScore: includeRisk ? 58 : 76,
            aiSummary: FinancialInsight(
                userId: userId,
                type: .summary,
                title: includeRisk ? "现金流风险提示" : "本月支出可控",
                body: includeRisk
                    ? (primaryRisk.map { CashFlowExplanationBuilder.build(from: $0) } ?? "预计未来可能出现资金压力。")
                    : "生活支出占收入 34.7%，债务还款按计划进行。建议保持当前节奏。",
                sourceTransactionIds: [],
                sourceDebtIds: [],
                modelName: "preview"
            ),
            cashFlowProjections: projections,
            cashFlowRisk: primaryRisk,
            hasAccounts: true,
            hasTransactions: includeTransactions
        )
    }

    public static var transactions: TransactionListSnapshot {
        let accountId = UUID()
        let account = Account(id: accountId, userId: userId, name: "现金", type: .cash)
        let txs = [
            Transaction(
                userId: userId,
                accountId: accountId,
                amount: Money(amount: 36, currencyCode: "CNY"),
                date: Date(),
                merchant: "地铁出行",
                category: "交通",
                transactionType: .expense,
                source: .manual
            ),
            Transaction(
                userId: userId,
                accountId: accountId,
                amount: Money(amount: 18_000, currencyCode: "CNY"),
                merchant: "工资入账",
                category: "工资",
                transactionType: .income,
                source: .manual
            ),
        ]
        let sections = TransactionGrouper.group(transactions: txs, accounts: [account])
        let stats = MonthlyStatsCalculator.compute(transactions: txs, month: Date(), currencyCode: "CNY")
        return TransactionListSnapshot(sections: sections, monthlyStats: stats)
    }

    public static var debts: DebtListSnapshot {
        let debt = Debt(
            userId: userId,
            lender: "招商银行",
            productName: "信用卡",
            debtType: .creditCard,
            outstandingBalance: Money(amount: 8_200, currencyCode: "CNY"),
            installmentAmount: Money(amount: 2_100, currencyCode: "CNY"),
            paymentFrequency: .monthly,
            dueDate: Date().addingTimeInterval(86400 * 5),
            interestRate: Decimal(string: "0.18"),
            status: .active,
            source: .userInput
        )
        return DebtListSnapshot(
            debts: [debt],
            totalOutstanding: Money(amount: 8_200, currencyCode: "CNY"),
            estimatedMonthlyRepayment: Money(amount: 2_100, currencyCode: "CNY"),
            debtPressureScore: 55,
            debtPressureLevel: .high,
            highCostDebts: [debt],
            debtFreeEstimate: Date().addingTimeInterval(86400 * 180)
        )
    }

    public static var assets: AssetListSnapshot {
        AssetListSnapshot(
            assets: [
                Asset(
                    userId: userId,
                    name: "货币基金",
                    type: .cashEquivalent,
                    currentValue: Money(amount: 50_000, currencyCode: "CNY")
                ),
            ],
            totalValue: Money(amount: 50_000, currencyCode: "CNY")
        )
    }

    public static var aiAssistant: AIAssistantSnapshot {
        AIAssistantSnapshot(recentInsights: [
            FinancialInsight(
                userId: userId,
                type: .actionSuggestion,
                title: "提前还款建议",
                body: "若本月结余超过 ¥5,000，可考虑优先偿还高利率信用卡。",
                modelName: "preview"
            ),
        ])
    }

    public static var aiAssistantWithPlainAnswer: AIAssistantSnapshot {
        AIAssistantSnapshot(
            recentInsights: aiAssistant.recentInsights,
            lastAnswer: assistantAnswerPlain()
        )
    }

    public static var aiAssistantWithStructuredAnswer: AIAssistantSnapshot {
        AIAssistantSnapshot(
            recentInsights: aiAssistant.recentInsights,
            lastAnswer: assistantAnswerFullStructured()
        )
    }

    public static func assistantAnswerPlain() -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: "我现在有多少钱？",
            intent: .availableCash,
            title: "可用资金",
            body: "你当前可用资金约为 ¥28,650.32。",
            factSources: ["Account", "Transaction"]
        )
    }

    public static func assistantAnswerWithKeyFacts() -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: "我现在有多少钱？",
            intent: .availableCash,
            title: "可用资金",
            body: "你当前可用资金约为 ¥28,650.32。",
            answer: "你当前可用资金约为 ¥28,650.32。",
            factSources: ["Account"],
            keyFacts: [
                AssistantKeyFact(
                    label: "可用资金",
                    value: .money(MoneyDTO(amount: 28_650.32, currencyCode: "CNY")),
                    kind: .balance,
                    source: "availableCash"
                ),
            ],
            references: [AssistantReference(key: "availableCash")]
        )
    }

    public static func assistantAnswerWithWarning(severity: AssistantWarningSeverity = .warning) -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: "本月财务怎么样？",
            intent: .unknown,
            title: "本月摘要",
            body: "本月债务还款占收入 31%，需关注现金流。",
            answer: "本月债务还款占收入 31%，需关注现金流。",
            factSources: ["Debt"],
            warnings: [
                AssistantWarning(
                    title: severity == .risk ? "现金流风险" : "债务压力偏高",
                    message: severity == .risk
                        ? "预计余额可能低于安全线。"
                        : "债务还款占收入比例较高。",
                    severity: severity,
                    source: severity == .risk ? "cashFlow30" : "debtPaymentToIncomePercent"
                ),
            ],
            references: [AssistantReference(key: "cashFlow30")]
        )
    }

    public static func assistantAnswerWithActions() -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: "我能不能买 3000 元的东西？",
            intent: .purchaseAffordability,
            title: "购买可行性",
            body: "买后将低于安全储备 ¥2000。",
            answer: "买后将低于安全储备 ¥2000。",
            factSources: ["CashFlow"],
            actions: [
                AssistantAction(title: "查看未来现金流", destination: .cashFlow),
                AssistantAction(title: "查看账户", destination: .accounts),
            ],
            references: [AssistantReference(key: "safetyReserve")]
        )
    }

    public static func assistantAnswerFullStructured() -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: "我能不能买 3000 元的东西？",
            intent: .purchaseAffordability,
            title: "购买可行性",
            body: "按当前账本数据，这笔支出可能挤压安全现金储备。",
            answer: "按当前账本数据，这笔支出可能挤压安全现金储备。",
            factSources: ["Account", "CashFlow"],
            keyFacts: [
                AssistantKeyFact(
                    label: "购买金额",
                    value: .money(MoneyDTO(amount: 3_000, currencyCode: "CNY")),
                    kind: .purchase,
                    source: "purchaseAmount"
                ),
                AssistantKeyFact(
                    label: "安全储备",
                    value: .money(MoneyDTO(amount: 2_000, currencyCode: "CNY")),
                    kind: .cashFlow,
                    source: "safetyReserve"
                ),
            ],
            warnings: [
                AssistantWarning(
                    title: "安全储备不足",
                    message: "购买后可用资金将低于安全储备。",
                    severity: .risk,
                    source: "safetyReserve"
                ),
            ],
            actions: [
                AssistantAction(title: "查看未来现金流", destination: .cashFlow),
                AssistantAction(title: "查看债务", destination: .debt),
            ],
            references: [
                AssistantReference(key: "purchaseAmount"),
                AssistantReference(key: "safetyReserve"),
            ]
        )
    }

    public static func assistantPresentation(from answer: AssistantAnswer) -> AssistantAnswerPresentation {
        AssistantAnswerPresentationMapper.make(from: answer)
    }
}

public struct PreviewHomeOverviewProvider: HomeOverviewProviding {
    public var overview: HomeOverview
    public var shouldThrow: Bool

    public init(overview: HomeOverview = PreviewMockData.homeOverview, shouldThrow: Bool = false) {
        self.overview = overview
        self.shouldThrow = shouldThrow
    }

    public func loadOverview(userId: UUID) async throws -> HomeOverview {
        _ = userId
        if shouldThrow { throw DomainError.validationFailed("preview error") }
        return overview
    }
}

public struct PreviewTransactionListProvider: TransactionListProviding {
    public var snapshot: TransactionListSnapshot
    public init(snapshot: TransactionListSnapshot = PreviewMockData.transactions) {
        self.snapshot = snapshot
    }
    public func loadSnapshot(userId: UUID) async throws -> TransactionListSnapshot {
        _ = userId
        return snapshot
    }
}

public struct PreviewDebtListProvider: DebtListProviding {
    public var snapshot: DebtListSnapshot
    public init(snapshot: DebtListSnapshot = PreviewMockData.debts) {
        self.snapshot = snapshot
    }
    public func loadSnapshot(userId: UUID) async throws -> DebtListSnapshot {
        _ = userId
        return snapshot
    }
}

public struct PreviewDebtManaging: DebtManaging {
    public init() {}
    public func create(_ input: CreateDebtInput, userId: UUID) async throws -> Debt {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
    public func update(_ input: UpdateDebtInput, userId: UUID) async throws -> Debt {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
    public func delete(debtId: UUID, userId: UUID) async throws {
        _ = debtId; _ = userId
    }
    public func recordRepayment(_ input: RecordDebtRepaymentInput, userId: UUID) async throws -> Debt {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
}

public struct PreviewDebtDetailProviding: DebtDetailProviding {
    public init() {}
    public func loadDetail(debtId: UUID, userId: UUID) async throws -> DebtDetailSnapshot {
        _ = userId
        guard let debt = PreviewMockData.debts.debts.first(where: { $0.id == debtId })
            ?? PreviewMockData.debts.debts.first
        else {
            throw DomainError.notFound(entity: "Debt", id: debtId)
        }
        return DebtDetailSnapshot(debt: debt, events: [])
    }
}

public struct PreviewAssetListProvider: AssetListProviding {
    public var snapshot: AssetListSnapshot
    public init(snapshot: AssetListSnapshot = PreviewMockData.assets) {
        self.snapshot = snapshot
    }
    public func loadSnapshot(userId: UUID) async throws -> AssetListSnapshot {
        _ = userId
        return snapshot
    }
}

public struct PreviewAIAssistantProvider: AIAssistantProviding {
    public var snapshot: AIAssistantSnapshot
    public init(snapshot: AIAssistantSnapshot = PreviewMockData.aiAssistant) {
        self.snapshot = snapshot
    }
    public func loadSnapshot(userId: UUID) async throws -> AIAssistantSnapshot {
        _ = userId
        return snapshot
    }
    public func ask(question: String, userId: UUID) async throws -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: question,
            intent: .availableCash,
            title: "预览回答",
            body: "这是预览环境下的示例回答。",
            factSources: ["Account"]
        )
    }
    public func refreshInsights(userId: UUID) async throws -> [FinancialInsight] {
        _ = userId
        return snapshot.recentInsights
    }
}

public struct PreviewCurrentUserProvider: CurrentUserProviding {
    public var userId: UUID?
    public init(userId: UUID? = PreviewMockData.userId) {
        self.userId = userId
    }
    public func currentUserId() async throws -> UUID? { userId }
}

public struct PreviewAccountListProvider: AccountListProviding {
    public var snapshot: AccountListSnapshot
    public init(snapshot: AccountListSnapshot = PreviewMockData.accountList) {
        self.snapshot = snapshot
    }
    public func loadSnapshot(userId: UUID) async throws -> AccountListSnapshot {
        _ = userId
        return snapshot
    }
    public func loadDetail(accountId: UUID, userId: UUID) async throws -> AccountDetailSnapshot {
        _ = userId
        guard let summary = snapshot.accounts.first(where: { $0.id == accountId }) else {
            throw DomainError.notFound(entity: "Account", id: accountId)
        }
        return AccountDetailSnapshot(account: summary.account, currentBalance: summary.currentBalance)
    }
}

public struct PreviewAccountManaging: AccountManaging {
    public init() {}
    public func create(_ input: CreateAccountInput, userId: UUID) async throws -> Account {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
    public func update(_ input: UpdateAccountInput, userId: UUID) async throws -> Account {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
    public func delete(accountId: UUID, userId: UUID) async throws {
        _ = accountId; _ = userId
    }
}

public struct PreviewAccountRepository: AccountRepository {
    public var accounts: [Account]
    public init(accounts: [Account] = PreviewMockData.accounts) {
        self.accounts = accounts
    }
    public func upsert(_ account: Account) async throws {}
    public func fetch(id: UUID) async throws -> Account? { accounts.first { $0.id == id } }
    public func fetchAll(userId: UUID) async throws -> [Account] { accounts.filter { $0.userId == userId } }
    public func delete(id: UUID) async throws {}
}

public struct PreviewTransactionManaging: TransactionManaging {
    public init() {}
    public func record(_ input: RecordTransactionInput, userId: UUID) async throws -> Transaction {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
    public func recordTransfer(_ input: RecordTransferInput, userId: UUID) async throws -> (outbound: Transaction, inbound: Transaction) {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
    public func update(_ input: UpdateTransactionInput, userId: UUID) async throws -> Transaction {
        _ = input; _ = userId
        throw DomainError.validationFailed("preview only")
    }
    public func delete(transactionId: UUID, userId: UUID) async throws {
        _ = transactionId; _ = userId
    }
}

extension PreviewMockData {
    public static var accounts: [Account] {
        [Account(id: UUID(), userId: userId, name: "现金", type: .cash)]
    }

    public static var accountList: AccountListSnapshot {
        let summaries = accounts.map {
            AccountSummary(
                account: $0,
                currentBalance: Money(amount: 28650.32, currencyCode: "CNY"),
                transactionCount: 3
            )
        }
        return AccountListSnapshot(
            accounts: summaries,
            totalAvailableFunds: Money(amount: 28650.32, currencyCode: "CNY")
        )
    }
}

@MainActor
public enum PreviewAppFactory {
    public static func session(userId: UUID = PreviewMockData.userId) -> AppSession {
        let session = AppSession(users: PreviewUserRepository())
        session.configureForPreview(userId: userId)
        return session
    }

    public static func consentService(assistantAuthorized: Bool = false) -> AIDataConsentService {
        let userId = PreviewMockData.userId
        var storage: [UUID: AIDataConsent] = [:]
        if assistantAuthorized {
            storage[userId] = AIDataConsent(userId: userId, allowFinancialContextToAI: true)
        }
        return AIDataConsentService(consents: PreviewAIDataConsentRepository(storage: storage))
    }

    public static func homeViewModel(state: YSPagePhase<HomeOverview>? = nil) -> HomeViewModel {
        let vm = HomeViewModel(homeProvider: PreviewHomeOverviewProvider(), session: session())
        if let state { vm.phase = state }
        return vm
    }

    public static func transactionViewModel(state: YSPagePhase<TransactionListSnapshot>? = nil) -> TransactionViewModel {
        let vm = TransactionViewModel(
            provider: PreviewTransactionListProvider(),
            transactionService: PreviewTransactionManaging(),
            accounts: PreviewAccountRepository(),
            session: session()
        )
        vm.accounts = PreviewMockData.accounts
        if let state { vm.phase = state }
        return vm
    }

    public static func screenshotViewModel() -> ScreenshotBookkeepingViewModel {
        let bookkeeping = ScreenshotBookkeepingService(
            extractor: MockAIProvider(behavior: .success),
            transactionService: PreviewTransactionManaging(),
            accounts: PreviewAccountRepository()
        )
        return ScreenshotBookkeepingViewModel(
            bookkeeping: bookkeeping,
            accounts: PreviewAccountRepository(),
            session: session()
        )
    }

    public static func debtViewModel(state: YSPagePhase<DebtListSnapshot>? = nil) -> DebtViewModel {
        let vm = DebtViewModel(
            provider: PreviewDebtListProvider(),
            debtService: PreviewDebtManaging(),
            detailProvider: PreviewDebtDetailProviding(),
            accounts: PreviewAccountRepository(),
            session: session()
        )
        if let state { vm.phase = state }
        return vm
    }

    public static func debtScannerViewModel() -> DebtScannerViewModel {
        let scanner = DebtScannerService(
            scanner: MockAIProvider(debtScanBehavior: .successMultiDebt),
            debtService: PreviewDebtManaging()
        )
        return DebtScannerViewModel(scanner: scanner, session: session())
    }

    public static func accountViewModel(
        state: YSPagePhase<AccountListSnapshot>? = nil
    ) -> AccountViewModel {
        let vm = AccountViewModel(
            provider: PreviewAccountListProvider(),
            accountService: PreviewAccountManaging(),
            session: session()
        )
        if let state { vm.phase = state }
        return vm
    }

    public static func assetViewModel(state: YSPagePhase<AssetListSnapshot>? = nil) -> AssetViewModel {
        let vm = AssetViewModel(provider: PreviewAssetListProvider(), session: session())
        if let state { vm.phase = state }
        return vm
    }

    public static func aiViewModel(
        state: YSPagePhase<AIAssistantSnapshot>? = nil,
        consentAuthorized: Bool = false,
        consentDeclined: Bool = false
    ) -> AIAssistantViewModel {
        let vm = AIAssistantViewModel(
            provider: PreviewAIAssistantProvider(),
            session: session(),
            consentService: consentService(assistantAuthorized: consentAuthorized)
        )
        if consentAuthorized {
            vm.consentState = .authorized
        } else if consentDeclined {
            vm.consentState = .declined
        } else {
            vm.consentState = .unauthorized
        }
        if let state { vm.phase = state }
        return vm
    }

    public static func dataBackupViewModel() -> DataBackupViewModel {
        AppDependencies(repositories: .inMemory())
            .makeDataBackupViewModel { }
    }

    public static func privacyAISettingsViewModel() -> PrivacyAISettingsViewModel {
        let dependencies = AppDependencies(repositories: .inMemory())
        dependencies.session.configureForPreview(userId: PreviewMockData.userId)
        return dependencies.makePrivacyAISettingsViewModel()
    }
}

private final class PreviewAIDataConsentRepository: AIDataConsentRepository, @unchecked Sendable {
    private var storage: [UUID: AIDataConsent]

    init(storage: [UUID: AIDataConsent] = [:]) {
        self.storage = storage
    }

    func upsert(_ consent: AIDataConsent) async throws {
        storage[consent.userId] = consent
    }

    func fetch(userId: UUID) async throws -> AIDataConsent? {
        storage[userId]
    }
}

/// Minimal user repo for previews only.
private struct PreviewUserRepository: UserRepository {
    func upsert(_ user: User) async throws {}
    func fetch(id: UUID) async throws -> User? { nil }
    func fetchAll() async throws -> [User] { [] }
    func delete(id: UUID) async throws {}
}
