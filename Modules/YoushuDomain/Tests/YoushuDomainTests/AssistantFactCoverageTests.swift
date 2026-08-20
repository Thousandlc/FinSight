import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Assistant fact coverage")
struct AssistantFactCoverageTests {
    private func monthlySummaryWithRisk(
        availableCash: Decimal = 1_000,
        minimumBalance: Decimal = 800,
        safeBalance: Decimal = 2_000
    ) -> (MonthlySummaryFacts, FinancialContext) {
        let explanation = "预计8月15日账户余额可能下降至¥\(minimumBalance)，已低于安全余额¥\(safeBalance)。"
        let context = FinancialContext(
            availableCash: Money(amount: availableCash, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            cashFlow30: CashFlowContextSlice(
                endingBalance: Money(amount: 900, currencyCode: "CNY"),
                minimumBalance: Money(amount: minimumBalance, currencyCode: "CNY"),
                minimumBalanceDate: Date(timeIntervalSince1970: 1_700_000_000),
                isBelowSafeBalance: true,
                explanation: explanation
            ),
            hasAccounts: true,
            hasTransactions: true,
            currencyCode: "CNY"
        )
        let base = FinancialContextBuilder.monthlySummaryFacts(from: context)
        let facts = MonthlySummaryFactsEnricher.enrich(
            base,
            context: context,
            safeBalance: Money(amount: safeBalance, currencyCode: "CNY")
        )
        return (facts, context)
    }

    @Test("monthly summary safeBalance passes validator")
    func monthlySummarySafeBalance() async throws {
        let (facts, context) = monthlySummaryWithRisk()
        #expect(facts.safeBalance?.amount == 2_000)
        let request = FinancialAssistantContextMapper.makeRequest(
            question: "",
            intent: .unknown,
            context: context,
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        let draft = try await MockAIProvider().phraseMonthlySummary(
            request: request,
            facts: facts,
            riskAssessment: FinancialRiskTestFixtures.safeKnownNoDebt()
        )
        let policyDraft = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: draft,
            assessment: FinancialRiskTestFixtures.safeKnownNoDebt()
        )
        let validated = try AssistantAnswerValidator.validateSummary(draft: policyDraft, facts: facts)
        #expect(validated.body.contains("生活支出") || validated.body.contains("1500"))
    }

    @Test("cashFlowRiskExplanation yen amounts have fact sources")
    func explanationAmountSources() throws {
        let (facts, _) = monthlySummaryWithRisk()
        let pack = AssistantAnswerValidator.factPack(from: facts)
        #expect(pack.amounts["safeBalance"]?.amount == 2_000)
        #expect(pack.amounts["minimumBalance"]?.amount == 800)
        #expect(facts.cashFlowRiskExplanation?.contains("2000") == true)
    }

    @Test("insight safeBalance continues to pass")
    func insightSafeBalance() async throws {
        let context = FinancialContext(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            cashFlow30: CashFlowContextSlice(
                endingBalance: Money(amount: 1_000, currencyCode: "CNY"),
                minimumBalance: Money(amount: 1_000, currencyCode: "CNY"),
                minimumBalanceDate: Date(),
                isBelowSafeBalance: true,
                explanation: "预计余额可能下降至¥1000，已低于安全余额¥2000。"
            ),
            hasAccounts: true,
            currencyCode: "CNY"
        )
        let safeBalance = Money(amount: 2_000, currencyCode: "CNY")
        let pack = try #require(
            FinancialInsightGenerator.generate(context: context, safeBalance: safeBalance)
                .first { $0.type == .cashFlow }
        )
        #expect(pack.amounts["safeBalance"]?.amount == 2_000)
        let request = FinancialAssistantContextMapper.makeRequest(
            question: "",
            intent: .unknown,
            context: context,
            safeBalance: safeBalance
        )
        let draft = try await MockAIProvider().phraseInsight(request: request, facts: pack)
        let answerPack = AnswerFactPack(
            intent: .unknown,
            facts: pack.facts,
            amounts: pack.amounts,
            sourceLabels: pack.sourceLabels
        )
        _ = try AssistantAnswerValidator.validate(draft: draft, against: answerPack)
    }

    @Test("unauthorized amount still triggers inventedAmount")
    func inventedAmountStillRejected() {
        let pack = AnswerFactPack(
            intent: .availableCash,
            amounts: ["availableCash": Money(amount: 1_000, currencyCode: "CNY")]
        )
        let draft = AssistantAnswerDraft(
            title: "错误",
            body: "你有 ¥999999。",
            answer: "你有 ¥999999。"
        )
        #expect(throws: AssistantValidationError.inventedAmount("999999")) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        }
    }

    @Test("legal percent keyFact passes")
    func legalPercentKeyFact() throws {
        let pack = AnswerFactPack(
            intent: .unknown,
            facts: ["debtPaymentToIncomePercent": "31"],
            amounts: ["monthlyIncome": Money(amount: 10_000, currencyCode: "CNY")]
        )
        let draft = AssistantAnswerDraft(
            title: "摘要",
            body: "债务还款占比较高。",
            answer: "债务还款占比较高。",
            keyFacts: [
                AssistantKeyFact(
                    label: "债务还款占比",
                    value: .percent(31),
                    kind: .debt,
                    source: "debtPaymentToIncomePercent"
                ),
            ],
            references: [AssistantReference(key: "debtPaymentToIncomePercent")]
        )
        _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
    }

    @Test("illegal percent keyFact is rejected")
    func illegalPercentKeyFact() {
        let pack = AnswerFactPack(
            intent: .unknown,
            facts: ["debtPaymentToIncomePercent": "31"],
            amounts: [:]
        )
        let draft = AssistantAnswerDraft(
            title: "摘要",
            body: "债务还款占比较高。",
            answer: "债务还款占比较高。",
            keyFacts: [
                AssistantKeyFact(
                    label: "债务还款占比",
                    value: .percent(99),
                    kind: .debt,
                    source: "debtPaymentToIncomePercent"
                ),
            ]
        )
        #expect(throws: AssistantValidationError.invalidKeyFactValue("debtPaymentToIncomePercent")) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        }
    }

    @Test("legal date keyFact passes with ISO8601 fact")
    func legalDateKeyFact() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter().string(from: date)
        let pack = AnswerFactPack(
            intent: .debtFreeDate,
            facts: ["estimatedDebtFreeDate": iso],
            amounts: ["totalDebt": Money(amount: 8_000, currencyCode: "CNY")]
        )
        let draft = AssistantAnswerDraft(
            title: "清偿",
            body: "预计可还清。",
            answer: "预计可还清。",
            keyFacts: [
                AssistantKeyFact(
                    label: "预计清偿",
                    value: .date(date),
                    kind: .debt,
                    source: "estimatedDebtFreeDate"
                ),
            ],
            references: [AssistantReference(key: "estimatedDebtFreeDate")]
        )
        _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
    }

    @Test("illegal date keyFact is rejected")
    func illegalDateKeyFact() {
        let pack = AnswerFactPack(
            intent: .debtFreeDate,
            facts: ["estimatedDebtFreeDate": "2026年3月"],
            amounts: ["totalDebt": Money(amount: 8_000, currencyCode: "CNY")]
        )
        let draft = AssistantAnswerDraft(
            title: "清偿",
            body: "预计可还清。",
            answer: "预计可还清。",
            keyFacts: [
                AssistantKeyFact(
                    label: "预计清偿",
                    value: .date(Date()),
                    kind: .debt,
                    source: "estimatedDebtFreeDate"
                ),
            ]
        )
        #expect(throws: AssistantValidationError.invalidKeyFactValue("estimatedDebtFreeDate")) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        }
    }

    @Test("categoryAmount_0 passes when present in fact pack")
    func legalCategoryAmountReference() throws {
        let pack = AnswerFactPack(
            intent: .spendingBreakdown,
            facts: ["category_0": "餐饮"],
            amounts: [
                "monthlyExpense": Money(amount: 3_000, currencyCode: "CNY"),
                "categoryAmount_0": Money(amount: 1_200, currencyCode: "CNY"),
            ]
        )
        let draft = AssistantAnswerDraft(
            title: "支出",
            body: "本月生活支出合计 ¥3000。",
            answer: "本月生活支出合计 ¥3000。",
            references: [
                AssistantReference(key: "monthlyExpense"),
                AssistantReference(key: "categoryAmount_0"),
            ]
        )
        _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
    }

    @Test("unknown categoryAmount_N reference is rejected")
    func illegalCategoryAmountReference() {
        let pack = AnswerFactPack(
            intent: .spendingBreakdown,
            facts: ["category_0": "餐饮"],
            amounts: [
                "monthlyExpense": Money(amount: 3_000, currencyCode: "CNY"),
                "categoryAmount_0": Money(amount: 1_200, currencyCode: "CNY"),
            ]
        )
        let draft = AssistantAnswerDraft(
            title: "支出",
            body: "本月生活支出合计 ¥3000。",
            answer: "本月生活支出合计 ¥3000。",
            references: [AssistantReference(key: "categoryAmount_99")]
        )
        #expect(throws: AssistantValidationError.invalidReference("categoryAmount_99")) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        }
    }

    @Test("structured references align with fact pack keys")
    func structuredReferenceAlignment() async throws {
        let (facts, context) = monthlySummaryWithRisk()
        let request = FinancialAssistantContextMapper.makeRequest(
            question: "",
            intent: .unknown,
            context: context,
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        let draft = try await MockAIProvider().phraseMonthlySummary(
            request: request,
            facts: facts,
            riskAssessment: FinancialRiskTestFixtures.safeKnownNoDebt()
        )
        let pack = AssistantAnswerValidator.factPack(from: facts)
        let allowed = Set(AssistantReferenceKey.allCases.map(\.rawValue)).union(pack.facts.keys).union(pack.amounts.keys)
        for reference in draft.references {
            #expect(allowed.contains(reference.key))
        }
    }

    @Test("mock monthly summary end-to-end passes with risk")
    func monthlySummaryEndToEnd() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Summary"))
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 1_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
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
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        let insight = try await service.generateMonthlySummary(userId: userId)
        #expect(!insight.body.isEmpty)
    }
}
