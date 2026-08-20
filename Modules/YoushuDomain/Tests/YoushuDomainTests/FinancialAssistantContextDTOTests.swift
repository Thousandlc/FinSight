import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Financial assistant context DTO")
struct FinancialAssistantContextDTOTests {
    private let userId = UUID()
    private let accountId = UUID()
    private let goalId = UUID()
    private let budgetId = UUID()
    private let transactionId = UUID()
    private let debtId = UUID()

    private func sampleContext() -> FinancialContext {
        FinancialContext(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 8_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            estimatedMonthEndBalance: Money(amount: 4_500, currencyCode: "CNY"),
            totalDebt: Money(amount: 12_000, currencyCode: "CNY"),
            estimatedMonthlyRepayment: Money(amount: 1_200, currencyCode: "CNY"),
            estimatedDebtFreeDate: Date(timeIntervalSince1970: 1_800_000_000),
            debtPaymentToIncomePercent: 6,
            topExpenseCategories: [
                CategoryAmount(category: "餐饮", amount: Money(amount: 1_200, currencyCode: "CNY")),
            ],
            cashFlow30: CashFlowContextSlice(
                endingBalance: Money(amount: 900, currencyCode: "CNY"),
                minimumBalance: Money(amount: 800, currencyCode: "CNY"),
                minimumBalanceDate: Date(timeIntervalSince1970: 1_700_100_000),
                isBelowSafeBalance: true,
                explanation: "预计余额可能下降至¥800，已低于安全余额¥2000。"
            ),
            goals: [
                GoalContextSlice(
                    id: goalId,
                    name: "应急金",
                    type: .emergencyFund,
                    targetAmount: Money(amount: 10_000, currencyCode: "CNY"),
                    currentAmount: Money(amount: 2_000, currencyCode: "CNY"),
                    remainingAmount: Money(amount: 8_000, currencyCode: "CNY"),
                    progressPercent: 20,
                    targetDate: Date(timeIntervalSince1970: 1_900_000_000)
                ),
            ],
            budgets: [
                BudgetContextSlice(
                    id: budgetId,
                    name: "餐饮预算",
                    category: "餐饮",
                    limit: Money(amount: 2_000, currencyCode: "CNY"),
                    spent: Money(amount: 1_200, currencyCode: "CNY"),
                    remaining: Money(amount: 800, currencyCode: "CNY")
                ),
            ],
            hasAccounts: true,
            hasTransactions: true,
            hasDebts: true,
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            currencyCode: "CNY"
        )
    }

    private func sampleRequest() -> AssistantRequestDTO {
        FinancialAssistantContextMapper.makeRequest(
            question: "我现在有多少钱？",
            intent: .availableCash,
            context: sampleContext(),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
    }

    @Test("DTO can be created from domain context")
    func dtoCreation() {
        let dto = FinancialAssistantContextMapper.map(
            context: sampleContext(),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        #expect(dto.balance.availableCash.amount == 1_000)
        #expect(dto.monthly.income.amount == 8_000)
        #expect(dto.debt.totalOutstanding.amount == 12_000)
        #expect(dto.cashFlow30?.safeBalance.amount == 2_000)
        #expect(dto.goals.count == 1)
        #expect(dto.budgets.count == 1)
        #expect(dto.goals[0].name == "应急金")
        #expect(dto.budgets[0].name == "餐饮预算")
    }

    @Test("DTO and request serialize to JSON")
    func serialization() throws {
        let dto = FinancialAssistantContextMapper.map(
            context: sampleContext(),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        let request = sampleRequest()
        let contextJSON = try FinancialAssistantContextSerializer.contextJSONString(dto)
        let requestJSON = try FinancialAssistantContextSerializer.requestJSONString(request)
        #expect(!contextJSON.isEmpty)
        #expect(!requestJSON.isEmpty)
        #expect(contextJSON.contains("availableCash"))
        #expect(contextJSON.contains("monthly"))
        #expect(contextJSON.contains("safeBalance"))
    }

    @Test("serialized JSON excludes forbidden identifiers and PII fields")
    func forbiddenFields() throws {
        let request = sampleRequest()
        let json = try FinancialAssistantContextSerializer.requestJSONString(request).lowercased()
        let forbiddenKeys = [
            "userid", "accountid", "transactionid", "debtid", "goalid", "budgetid",
            "sourcetransactionids", "sourcedebtids", "sourceaccountids",
            "merchant", "note", "displayname", "email", "phone", "address",
        ]
        for key in forbiddenKeys {
            #expect(!json.contains(key), "JSON must not contain \(key)")
        }
        #expect(!json.contains("transaction"))
        #expect(!json.contains("account"))
    }

    @Test("serialized JSON includes required aggregated fields")
    func requiredFields() throws {
        let request = sampleRequest()
        let json = try FinancialAssistantContextSerializer.requestJSONString(request)
        #expect(json.contains("availableCash"))
        #expect(json.contains("income"))
        #expect(json.contains("expense"))
        #expect(json.contains("totalOutstanding"))
        #expect(json.contains("cashFlow30"))
        #expect(json.contains("safeBalance"))
        #expect(json.contains("topCategories"))
    }

    @Test("goal and budget DTOs omit id fields")
    func goalBudgetWithoutId() throws {
        let dto = FinancialAssistantContextMapper.map(
            context: sampleContext(),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        let data = try FinancialAssistantContextSerializer.encodeContext(dto)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let goals = object?["goals"] as? [[String: Any]]
        let budgets = object?["budgets"] as? [[String: Any]]
        #expect(goals?.first?["id"] == nil)
        #expect(budgets?.first?["id"] == nil)
        #expect(goals?.first?["name"] as? String == "应急金")
        #expect(budgets?.first?["name"] as? String == "餐饮预算")
    }

    @Test("deterministic JSON encoding")
    func deterministicEncoding() throws {
        let dto = FinancialAssistantContextMapper.map(
            context: sampleContext(),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        let first = try FinancialAssistantContextSerializer.contextJSONString(dto)
        let second = try FinancialAssistantContextSerializer.contextJSONString(dto)
        #expect(first == second)
    }
}

@Suite("Assistant validator regression")
struct AssistantValidatorRegressionTests {
    @Test("cash flow risk insight accepts safeBalance in explanation")
    func cashFlowRiskSafeBalanceValidation() async throws {
        let context = FinancialContext(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 0, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 0, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 0, currencyCode: "CNY"),
            estimatedMonthEndBalance: Money(amount: 1_000, currencyCode: "CNY"),
            totalDebt: Money(amount: 0, currencyCode: "CNY"),
            estimatedMonthlyRepayment: Money(amount: 0, currencyCode: "CNY"),
            cashFlow30: CashFlowContextSlice(
                endingBalance: Money(amount: 1_000, currencyCode: "CNY"),
                minimumBalance: Money(amount: 1_000, currencyCode: "CNY"),
                minimumBalanceDate: Date(),
                isBelowSafeBalance: true,
                explanation: "预计余额可能下降至¥1000，已低于安全余额¥2000。"
            ),
            hasAccounts: true,
            asOf: Date(),
            currencyCode: "CNY"
        )
        let safeBalance = Money(amount: 2_000, currencyCode: "CNY")
        let packs = FinancialInsightGenerator.generate(
            context: context,
            safeBalance: safeBalance
        )
        let riskPack = try #require(packs.first { $0.type == .cashFlow })
        #expect(riskPack.amounts["safeBalance"]?.amount == 2_000)

        let request = FinancialAssistantContextMapper.makeRequest(
            question: "",
            intent: .unknown,
            context: context,
            safeBalance: safeBalance
        )
        let mock = MockAIProvider()
        let draft = try await mock.phraseInsight(request: request, facts: riskPack)
        let answerPack = AnswerFactPack(
            intent: .unknown,
            facts: riskPack.facts,
            amounts: riskPack.amounts,
            sourceLabels: riskPack.sourceLabels
        )
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: answerPack)
        #expect(validated.body.contains("2000") || validated.body.contains("¥2000"))
    }

    @Test("refresh insights with sparse fixture does not invent safeBalance")
    func refreshInsightsSafeBalance() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Risk"))
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 1_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let service = FinancialAssistantService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: container.insights,
            users: container.users,
            assistant: MockAIProvider(),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY"),
            consentService: consentService
        )
        let insights = try await service.refreshProactiveInsights(userId: userId)
        let risk = try #require(insights.first { $0.type == .cashFlow })
        #expect(!risk.body.isEmpty)
        #expect(risk.title == "现金流风险")
    }
}
