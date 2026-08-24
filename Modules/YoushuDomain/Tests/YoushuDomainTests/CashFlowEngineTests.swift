import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Financial summary engine")
struct FinancialSummaryEngineTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("normal cash flow matches accounts and month-to-date transactions")
    func normalCashFlow() {
        let userId = UUID()
        let cash = Account(
            userId: userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 10_000, currencyCode: "CNY")
        )
        let asOf = date(2024, 6, 15)
        let txs = [
            Transaction(
                userId: userId,
                accountId: cash.id,
                amount: Money(amount: 8_000, currencyCode: "CNY"),
                date: date(2024, 6, 5),
                merchant: "公司",
                category: "工资",
                transactionType: .income
            ),
            Transaction(
                userId: userId,
                accountId: cash.id,
                amount: Money(amount: 2_000, currencyCode: "CNY"),
                date: date(2024, 6, 8),
                merchant: "超市",
                category: "生活",
                transactionType: .expense
            ),
            Transaction(
                userId: userId,
                accountId: cash.id,
                amount: Money(amount: 1_500, currencyCode: "CNY"),
                date: date(2024, 6, 10),
                merchant: "微粒贷",
                category: "生活",
                transactionType: .repayment
            ),
        ]

        let summary = FinancialSummaryEngine.summarize(
            .init(
                accounts: [cash],
                transactions: txs,
                asOf: asOf,
                calendar: calendar,
                safeBalance: Money(amount: 2_000, currencyCode: "CNY")
            )
        )

        // 10000 + 8000 - 2000 - 1500 = 14500
        #expect(summary.availableCash.amount == 14_500)
        #expect(summary.monthlyIncome.amount == 8_000)
        #expect(summary.monthlyExpense.amount == 2_000)
        #expect(summary.monthlyDebtPayment.amount == 1_500)
        // 月底结余基于剩余天数预测，不应再把本月已发生收支加一遍
        #expect(summary.estimatedMonthEndBalance.amount != summary.availableCash.amount + 8_000)
        #expect(summary.financialHealthScore != nil)
    }

    @Test("income increase raises available cash and monthly income")
    func incomeIncrease() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行卡",
            type: .bankCard,
            openingBalance: Money(amount: 5_000, currencyCode: "CNY")
        )
        let asOf = date(2024, 7, 20)
        let base = FinancialSummaryEngine.summarize(
            .init(accounts: [account], transactions: [], asOf: asOf, calendar: calendar)
        )
        let withIncome = FinancialSummaryEngine.summarize(
            .init(
                accounts: [account],
                transactions: [
                    Transaction(
                        userId: userId,
                        accountId: account.id,
                        amount: Money(amount: 12_000, currencyCode: "CNY"),
                        date: date(2024, 7, 3),
                        category: "工资",
                        transactionType: .income
                    ),
                ],
                asOf: asOf,
                calendar: calendar
            )
        )
        #expect(withIncome.monthlyIncome.amount == 12_000)
        #expect(withIncome.availableCash.amount == base.availableCash.amount + 12_000)
    }

    @Test("large expense reduces available cash and monthly expense")
    func largeExpense() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行卡",
            type: .bankCard,
            openingBalance: Money(amount: 20_000, currencyCode: "CNY")
        )
        let asOf = date(2024, 8, 12)
        let summary = FinancialSummaryEngine.summarize(
            .init(
                accounts: [account],
                transactions: [
                    Transaction(
                        userId: userId,
                        accountId: account.id,
                        amount: Money(amount: 9_999, currencyCode: "CNY"),
                        date: date(2024, 8, 4),
                        merchant: "电器",
                        category: "购物",
                        transactionType: .expense
                    ),
                ],
                asOf: asOf,
                calendar: calendar
            )
        )
        #expect(summary.monthlyExpense.amount == 9_999)
        #expect(summary.availableCash.amount == 10_001)
    }

    @Test("multi-account available cash sums asset accounts only")
    func multiAccount() {
        let userId = UUID()
        let cash = Account(
            userId: userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 1_000, currencyCode: "CNY")
        )
        let bank = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 4_000, currencyCode: "CNY")
        )
        let card = Account(
            userId: userId,
            name: "信用卡",
            type: .creditCard,
            openingBalance: Money(amount: -3_000, currencyCode: "CNY")
        )
        let summary = FinancialSummaryEngine.summarize(
            .init(
                accounts: [cash, bank, card],
                transactions: [],
                asOf: date(2024, 5, 1),
                calendar: calendar
            )
        )
        #expect(summary.availableCash.amount == 5_000)
    }
}

@Suite("Cash flow engine")
struct CashFlowEngineTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("debt repayment creates discrete outflow and may trigger risk")
    func debtRepayment() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 5_000, currencyCode: "CNY")
        )
        let asOf = date(2024, 9, 1)
        let debt = Debt(
            userId: userId,
            lender: "信用卡",
            outstandingPrincipal: Money(amount: 10_000, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 10_000, currencyCode: "CNY"),
            currentDue: Money(amount: 3_500, currencyCode: "CNY"),
            installmentAmount: Money(amount: 3_500, currencyCode: "CNY"),
            dueDate: date(2024, 9, 18),
            status: .active
        )

        let projection = CashFlowEngine.project(
            .init(
                accounts: [account],
                transactions: [],
                debts: [debt],
                asOf: asOf,
                horizonDays: 30,
                calendar: calendar,
                safeBalance: Money(amount: 2_000, currencyCode: "CNY")
            )
        )

        #expect(projection.peakRepayment?.amount == 3_500)
        #expect(projection.drivers.contains { $0.kind == .debtRepayment && $0.amount.amount == 3_500 })
        #expect(projection.endingBalance.amount == 1_500)
        #expect(projection.risk != nil)
        let text = CashFlowExplanationBuilder.build(from: projection.risk!)
        #expect(text.contains("3,500") || text.contains("3500") || text.contains("¥3500") || text.contains("¥3,500"))
        #expect(text.contains("信用卡") || text.contains("还款"))
    }

    @Test("known due date with unknown payment amounts does not invent a zero outflow")
    func unknownDebtPaymentAmountIsNotProjectedAsZero() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 5_000, currencyCode: "CNY")
        )
        let asOf = date(2024, 9, 1)
        let debt = Debt(
            userId: userId,
            lender: "信用卡",
            outstandingBalance: Money(amount: 10_000, currencyCode: "CNY"),
            dueDate: date(2024, 9, 18),
            status: .active
        )

        let projection = CashFlowEngine.project(
            .init(
                accounts: [account],
                transactions: [],
                debts: [debt],
                asOf: asOf,
                horizonDays: 30,
                calendar: calendar,
                safeBalance: Money(amount: 2_000, currencyCode: "CNY")
            )
        )

        #expect(projection.drivers.contains { $0.kind == .debtRepayment } == false)
        #expect(projection.peakRepayment == nil)
        #expect(projection.endingBalance.amount == 5_000)
    }

    @Test("fixed recurring expense is scheduled on future dates")
    func fixedExpense() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 20_000, currencyCode: "CNY")
        )
        let asOf = date(2024, 9, 1)
        let rent = Transaction(
            userId: userId,
            accountId: account.id,
            amount: Money(amount: 4_000, currencyCode: "CNY"),
            date: date(2024, 8, 18),
            merchant: "房租",
            category: "住房",
            transactionType: .expense,
            recurringRule: RecurringRule(
                frequency: .monthly,
                nextDate: date(2024, 9, 18)
            )
        )

        let projection = CashFlowEngine.project(
            .init(
                accounts: [account],
                transactions: [rent],
                asOf: asOf,
                horizonDays: 30,
                calendar: calendar,
                safeBalance: Money(amount: 1_000, currencyCode: "CNY")
            )
        )

        #expect(projection.drivers.contains { $0.kind == .fixedExpense && $0.label == "房租" })
        // 历史房租已计入余额(20000-4000)，再排未来一期 → 12000
        #expect(projection.endingBalance.amount == 12_000)
    }

    @Test("insufficient balance generates CashFlowRisk with explanation facts")
    func belowSafeBalance() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            // 期初 7000 - 历史房租 4000 = 当前可用 3000
            openingBalance: Money(amount: 7_000, currencyCode: "CNY")
        )
        let asOf = date(2024, 9, 1)
        let debt = Debt(
            userId: userId,
            lender: "信用卡",
            outstandingBalance: Money(amount: 8_000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 3_500, currencyCode: "CNY"),
            dueDate: date(2024, 9, 18),
            status: .active
        )
        let rent = Transaction(
            userId: userId,
            accountId: account.id,
            amount: Money(amount: 4_000, currencyCode: "CNY"),
            date: date(2024, 8, 18),
            merchant: "房租",
            category: "住房",
            transactionType: .expense,
            recurringRule: RecurringRule(frequency: .monthly, nextDate: date(2024, 9, 18))
        )

        let projection = CashFlowEngine.project(
            .init(
                accounts: [account],
                transactions: [rent],
                debts: [debt],
                asOf: asOf,
                horizonDays: 30,
                calendar: calendar,
                safeBalance: Money(amount: 2_000, currencyCode: "CNY")
            )
        )

        // 3000 - 4000(房租) - 3500(信用卡) = -4500
        #expect(projection.minimumBalance.amount == -4_500)
        #expect(projection.risk != nil)
        #expect(projection.risk?.explanationFacts.isBelowSafeBalance == true)
        let text = CashFlowExplanationBuilder.build(from: projection.risk!)
        #expect(text.contains("9月18日"))
        #expect(text.contains("房租") || text.contains("信用卡"))
    }

    @Test("projects all four horizons")
    func allHorizons() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 8_000, currencyCode: "CNY")
        )
        let projections = CashFlowEngine.projectAllHorizons(
            .init(
                accounts: [account],
                transactions: [],
                asOf: date(2024, 1, 1),
                horizonDays: 30,
                calendar: calendar
            )
        )
        #expect(Set(projections.map(\.horizon)) == Set(CashFlowHorizon.allCases))
    }

    @Test("repayment plan drives scheduled debt payments")
    func repaymentPlan() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 10_000, currencyCode: "CNY")
        )
        let debt = Debt(
            userId: userId,
            lender: "消金",
            outstandingBalance: Money(amount: 6_000, currencyCode: "CNY"),
            status: .active
        )
        let plan = RepaymentPlan(
            debtId: debt.id,
            userId: userId,
            installmentAmount: Money(amount: 2_000, currencyCode: "CNY"),
            frequency: .monthly,
            startDate: date(2024, 10, 10)
        )
        let projection = CashFlowEngine.project(
            .init(
                accounts: [account],
                transactions: [],
                debts: [debt],
                repaymentPlans: [plan],
                asOf: date(2024, 10, 1),
                horizonDays: 30,
                calendar: calendar,
                safeBalance: Money(amount: 500, currencyCode: "CNY")
            )
        )
        #expect(projection.drivers.contains { $0.kind == .debtRepayment && $0.amount.amount == 2_000 })
        #expect(projection.endingBalance.amount == 8_000)
    }
}

@Suite("Home overview service")
struct HomeOverviewServiceTests {
    @Test("returns empty overview when no accounts or transactions")
    func emptyOverview() async throws {
        let service = HomeOverviewService(
            accounts: InMemoryAccountRepository(),
            transactions: InMemoryTransactionRepository(),
            debts: InMemoryDebtRepository(),
            repaymentPlans: InMemoryRepaymentPlanRepository(),
            assets: InMemoryAssetRepository(),
            budgets: InMemoryBudgetRepository(),
            goals: InMemoryGoalRepository(),
            insights: InMemoryInsightRepository(),
            users: InMemoryUserRepository()
        )
        let overview = try await service.loadOverview(userId: UUID())
        #expect(overview.isEmpty)
    }

    @Test("home metrics stay consistent with transactions accounts and debts")
    func consistentWithLedger() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "H"))
        let cash = Account(
            userId: userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 10_000, currencyCode: "CNY")
        )
        let bank = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 5_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(cash)
        try await container.accounts.upsert(bank)

        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 3_000,
                merchant: "公司",
                category: "工资",
                accountId: bank.id,
                formType: .income
            ),
            userId: userId
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 500,
                merchant: "午餐",
                category: "餐饮",
                accountId: cash.id,
                formType: .expense
            ),
            userId: userId
        )

        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let debt = try await debtService.create(
            CreateDebtInput(lender: "借呗", approximateBalance: 2_000, installmentAmount: 500),
            userId: userId
        )
        _ = try await debtService.recordRepayment(
            RecordDebtRepaymentInput(debtId: debt.id, amount: 500, accountId: bank.id),
            userId: userId
        )

        let home = OverviewServiceContainer(
            repositories: container,
            financialAssisting: NoOpFinancialAssisting()
        ).home
        let overview = try await home.loadOverview(userId: userId)

        let txs = try await container.transactions.fetchAll(userId: userId)
        let expectedAvailable = AccountBalanceEngine.availableFunds(
            accounts: [cash, bank],
            transactions: txs
        )
        #expect(overview.availableFunds == expectedAvailable)
        #expect(overview.monthlyIncome.amount == 3_000)
        #expect(overview.monthlyLivingExpense.amount == 500)
        #expect(overview.monthlyDebtRepayment.amount == 500)
        #expect(overview.cashFlowProjections.count == CashFlowHorizon.allCases.count)
        #expect(Set(overview.cashFlowProjections.map(\.horizon)) == Set(CashFlowHorizon.allCases))
        let sevenDay = overview.cashFlowProjections.first { $0.horizon == .days7 }
        #expect(sevenDay?.startingBalance == overview.availableFunds)
        #expect(overview.aiSummary != nil)
        #expect(overview.hasAccounts)
        #expect(overview.hasTransactions)

        let section = CashFlowPresentation.makeSection(from: overview)
        for row in section.horizons {
            let source = overview.cashFlowProjections.first { $0.horizon == row.horizon }
            #expect(row.endingBalance == source?.endingBalance)
            #expect(row.status == (source?.risk == nil ? .safe : .risk))
        }
    }
}

/// 测试用：不调用 LLM，phrase 直接失败让首页回退确定性文案。
private struct NoOpFinancialAssisting: FinancialAssisting {
    var name: String { "noop" }
    func phraseAnswer(request: AssistantRequestDTO, facts: AnswerFactPack) async throws -> AssistantAnswerDraft {
        throw AssistantValidationError.cannotAnswer("noop")
    }
    func phraseMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> AssistantAnswerDraft {
        _ = riskAssessment
        throw AssistantValidationError.cannotAnswer("noop")
    }
    func phrasePurchaseScenario(request: AssistantRequestDTO, scenario: PurchaseScenario) async throws -> AssistantAnswerDraft {
        throw AssistantValidationError.cannotAnswer("noop")
    }
    func phraseInsight(request: AssistantRequestDTO, facts: InsightFactPack) async throws -> AssistantAnswerDraft {
        throw AssistantValidationError.cannotAnswer("noop")
    }
}

private actor InMemoryAccountRepository: AccountRepository {
    func upsert(_ account: Account) async throws {}
    func fetch(id: UUID) async throws -> Account? { nil }
    func fetchAll(userId: UUID) async throws -> [Account] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryTransactionRepository: TransactionRepository {
    func upsert(_ transaction: Transaction) async throws {}
    func fetch(id: UUID) async throws -> Transaction? { nil }
    func fetchAll(userId: UUID) async throws -> [Transaction] { [] }
    func fetchAll(accountId: UUID) async throws -> [Transaction] { [] }
    func fetchAll(relatedDebtId: UUID) async throws -> [Transaction] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryDebtRepository: DebtRepository {
    func upsert(_ debt: Debt) async throws {}
    func fetch(id: UUID) async throws -> Debt? { nil }
    func fetchAll(userId: UUID) async throws -> [Debt] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryRepaymentPlanRepository: RepaymentPlanRepository {
    func upsert(_ plan: RepaymentPlan) async throws {}
    func fetch(id: UUID) async throws -> RepaymentPlan? { nil }
    func fetchAll(debtId: UUID) async throws -> [RepaymentPlan] { [] }
    func fetchAll(userId: UUID) async throws -> [RepaymentPlan] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryAssetRepository: AssetRepository {
    func upsert(_ asset: Asset) async throws {}
    func fetchAll(userId: UUID) async throws -> [Asset] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryBudgetRepository: BudgetRepository {
    func upsert(_ budget: Budget) async throws {}
    func fetchAll(userId: UUID) async throws -> [Budget] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryGoalRepository: GoalRepository {
    func upsert(_ goal: Goal) async throws {}
    func fetchAll(userId: UUID) async throws -> [Goal] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryInsightRepository: FinancialInsightRepository {
    func upsert(_ insight: FinancialInsight) async throws {}
    func fetchAll(userId: UUID) async throws -> [FinancialInsight] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryUserRepository: UserRepository {
    func upsert(_ user: User) async throws {}
    func fetch(id: UUID) async throws -> User? { nil }
    func fetchAll() async throws -> [User] { [] }
    func delete(id: UUID) async throws {}
}
