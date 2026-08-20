import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Financial assistant")
struct FinancialAssistantTests {
    private func makeEnv(
        assistantBehavior: MockAIProvider.AssistantBehavior = .success
    ) async throws -> (
        service: FinancialAssistantService,
        container: RepositoryContainer,
        userId: UUID,
        account: Account
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "A"))
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 12_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        try await container.transactions.upsert(
            Transaction(
                userId: userId,
                accountId: account.id,
                amount: Money(amount: 10_000, currencyCode: "CNY"),
                date: Date(),
                merchant: "公司",
                category: "工资",
                transactionType: .income
            )
        )
        try await container.transactions.upsert(
            Transaction(
                userId: userId,
                accountId: account.id,
                amount: Money(amount: 2_000, currencyCode: "CNY"),
                date: Date(),
                merchant: "超市",
                category: "购物",
                transactionType: .expense
            )
        )
        try await container.debts.upsert(
            Debt(
                userId: userId,
                lender: "微粒贷",
                originalAmount: Money(amount: 10_000, currencyCode: "CNY"),
                outstandingPrincipal: Money(amount: 8_000, currencyCode: "CNY"),
                outstandingBalance: Money(amount: 8_000, currencyCode: "CNY"),
                installmentAmount: Money(amount: 1_500, currencyCode: "CNY"),
                remainingInstallments: 6,
                status: .active
            )
        )
        let mock = MockAIProvider(assistantBehavior: assistantBehavior)
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
            assistant: mock
        )
        return (service, container, userId, account)
    }

    @Test("normal question uses real ledger amounts")
    func normalQuestion() async throws {
        let env = try await makeEnv()
        let answer = try await env.service.ask(question: "我现在有多少钱？", userId: env.userId)
        #expect(answer.intent == .availableCash)
        #expect(answer.body.contains("20000") || answer.body.contains("¥20000"))
        #expect(answer.factSources.contains("Account"))
        #expect(answer.modelName == "mock")
    }

    @Test("data insufficient fails loudly")
    func dataInsufficient() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "E"))
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
            assistant: MockAIProvider()
        )
        await #expect(throws: AssistantValidationError.dataInsufficient) {
            _ = try await service.ask(question: "我现在有多少钱？", userId: userId)
        }
    }

    @Test("unknown question cannot answer")
    func cannotAnswer() async throws {
        let env = try await makeEnv()
        do {
            _ = try await env.service.ask(question: "今天天气怎么样？", userId: env.userId)
            Issue.record("Expected cannotAnswer")
        } catch let error as AssistantValidationError {
            guard case .cannotAnswer = error else {
                Issue.record("Unexpected \(error)")
                return
            }
        }
    }

    @Test("AI invented amount is rejected by validator")
    func inventedAmountRejected() async throws {
        let env = try await makeEnv(assistantBehavior: .inventAmount)
        await #expect(throws: AssistantValidationError.inventedAmount("999999")) {
            _ = try await env.service.ask(question: "我现在有多少钱？", userId: env.userId)
        }
    }

    @Test("advice without disclaimer is rejected")
    func missingDisclaimer() async throws {
        let env = try await makeEnv(assistantBehavior: .missingDisclaimer)
        await #expect(throws: AssistantValidationError.missingDisclaimer) {
            _ = try await env.service.ask(question: "我每个月应该存多少钱？", userId: env.userId)
        }
    }

    @Test("purchase scenario is deterministic and explained with disclaimer")
    func purchaseScenario() async throws {
        let env = try await makeEnv()
        let (scenario, answer) = try await env.service.evaluatePurchase(amount: 3_000, userId: env.userId)
        #expect(scenario.purchaseAmount.amount == 3_000)
        #expect(scenario.cashAfterPurchase.amount == 17_000)
        #expect(answer.disclaimer != nil || answer.body.contains("不构成") || answer.body.contains("仅供参考") || answer.body.contains("假设"))
        #expect(answer.factSources.contains("CashFlow") || answer.factSources.contains("Account"))
    }

    @Test("monthly summary percent comes from engine facts")
    func monthlySummary() async throws {
        let env = try await makeEnv()
        // 再记一笔还款，使债务还款/收入比 >= 20%
        try await env.container.transactions.upsert(
            Transaction(
                userId: env.userId,
                accountId: env.account.id,
                amount: Money(amount: 3_100, currencyCode: "CNY"),
                date: Date(),
                merchant: "微粒贷还款",
                category: "生活",
                transactionType: .repayment
            )
        )
        let insight = try await env.service.generateMonthlySummary(userId: env.userId)
        #expect(insight.type == .summary)
        #expect(insight.body.contains("%") || insight.body.contains("压力"))
        #expect(insight.modelName == "mock")
        // 助手不得改写核心财务实体
        let debts = try await env.container.debts.fetchAll(userId: env.userId)
        #expect(debts.first?.outstandingBalance?.amount == 8_000)
    }

    @Test("conflicting or empty AI body is rejected")
    func emptyAIBody() async throws {
        let env = try await makeEnv(assistantBehavior: .emptyBody)
        await #expect(throws: AssistantValidationError.emptyBody) {
            _ = try await env.service.ask(question: "我总共欠多少钱？", userId: env.userId)
        }
    }

    @Test("context builder does not expose raw repository access to AI")
    func contextIsMinimized() async throws {
        let env = try await makeEnv()
        let context = try await env.service.loadContext(userId: env.userId)
        #expect(context.availableCash.amount == 20_000) // 12000 opening + 10000 income - 2000 expense
        #expect(context.totalDebt.amount == 8_000)
        #expect(!context.topExpenseCategories.isEmpty)
    }

    @Test("router extracts purchase amount")
    func routerPurchaseAmount() {
        #expect(FinancialQuestionRouter.classify("我能不能买3000元的东西？") == .purchaseAffordability)
        #expect(FinancialQuestionRouter.extractPurchaseAmount(from: "我能不能买3000元的东西？") == 3_000)
    }
}
