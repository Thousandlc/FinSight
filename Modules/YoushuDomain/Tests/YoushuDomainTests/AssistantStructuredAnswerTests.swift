import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Assistant structured answer")
struct AssistantStructuredAnswerTests {
    private func samplePack() -> AnswerFactPack {
        AnswerFactPack(
            intent: .availableCash,
            facts: ["description": "当前可用资金"],
            amounts: ["availableCash": Money(amount: 20_000, currencyCode: "CNY")],
            sourceLabels: ["Account", "Transaction"]
        )
    }

    private func sampleStructured() -> AssistantStructuredAnswer {
        AssistantStructuredAnswer(
            answer: "你当前可用资金约为 ¥20000。",
            keyFacts: [
                AssistantKeyFact(
                    label: "可用资金",
                    value: .money(MoneyDTO(amount: 20_000, currencyCode: "CNY")),
                    kind: .balance,
                    source: "availableCash"
                ),
            ],
            warnings: [
                AssistantWarning(
                    title: "提示",
                    message: "请留意账户波动。",
                    severity: .safe,
                    source: "availableCash"
                ),
            ],
            actions: [
                AssistantAction(title: "查看账户", destination: .accounts),
            ],
            references: [
                AssistantReference(key: "availableCash"),
            ]
        )
    }

    @Test("structured answer can be created")
    func creation() {
        let structured = sampleStructured()
        #expect(!structured.answer.isEmpty)
        #expect(structured.keyFacts.count == 1)
        #expect(structured.warnings.count == 1)
        #expect(structured.actions.count == 1)
        #expect(structured.references.count == 1)
    }

    @Test("structured answer JSON round-trip")
    func jsonRoundTrip() throws {
        let structured = sampleStructured()
        let data = try AssistantStructuredAnswerSerializer.encode(structured)
        let decoded = try AssistantStructuredAnswerSerializer.decode(data)
        #expect(decoded == structured)
        let json = try AssistantStructuredAnswerSerializer.jsonString(structured)
        #expect(json.contains("availableCash"))
        #expect(!json.contains("userId"))
    }

    @Test("valid keyFacts pass validator")
    func validKeyFacts() throws {
        let draft = AssistantAnswerDraft(
            title: "可用资金",
            body: "你当前可用资金约为 ¥20000。",
            answer: "你当前可用资金约为 ¥20000。",
            citedFactKeys: ["availableCash"],
            keyFacts: sampleStructured().keyFacts,
            references: [AssistantReference(key: "availableCash")]
        )
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: samplePack())
        #expect(validated.keyFacts.first?.source == "availableCash")
    }

    @Test("warning severity enum is preserved")
    func warningSeverity() throws {
        let draft = AssistantAnswerDraft(
            title: "风险",
            body: "未来30天余额可能低于安全线。",
            answer: "未来30天余额可能低于安全线。",
            warnings: [
                AssistantWarning(
                    title: "现金流风险",
                    message: "预计余额可能下降。",
                    severity: .risk,
                    source: "cashFlow30"
                ),
            ],
            references: [AssistantReference(key: "cashFlow30")]
        )
        let pack = AnswerFactPack(
            intent: .unknown,
            facts: ["explanation": "预计余额可能下降。"],
            amounts: [
                "minimumBalance": Money(amount: 800, currencyCode: "CNY"),
                "safeBalance": Money(amount: 2_000, currencyCode: "CNY"),
            ],
            sourceLabels: ["CashFlow"]
        )
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        #expect(validated.warnings.first?.severity == .risk)
    }

    @Test("action destination must be known page")
    func actionDestination() throws {
        let draft = AssistantAnswerDraft(
            title: "购买评估",
            body: "建议查看现金流。",
            answer: "建议查看现金流。",
            actions: [AssistantAction(title: "查看未来现金流", destination: .cashFlow)],
            references: [AssistantReference(key: "cashFlow30")]
        )
        let pack = AnswerFactPack(intent: .purchaseAffordability, sourceLabels: ["CashFlow"])
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        #expect(validated.actions.first?.destination == .cashFlow)
    }

    @Test("invalid reference is rejected")
    func invalidReference() {
        let draft = AssistantAnswerDraft(
            title: "错误",
            body: "测试",
            answer: "测试",
            references: [AssistantReference(key: "transactionId")]
        )
        #expect(throws: AssistantValidationError.forbiddenIdentifier("transactionId")) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: samplePack())
        }
    }

    @Test("unknown reference key is rejected")
    func unknownReference() {
        let draft = AssistantAnswerDraft(
            title: "错误",
            body: "测试",
            answer: "测试",
            references: [AssistantReference(key: "madeUpFact")]
        )
        #expect(throws: AssistantValidationError.invalidReference("madeUpFact")) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: samplePack())
        }
    }

    @Test("UUID reference is rejected")
    func uuidReference() {
        let uuid = UUID().uuidString
        let draft = AssistantAnswerDraft(
            title: "错误",
            body: "测试",
            answer: "测试",
            references: [AssistantReference(key: uuid)]
        )
        #expect(throws: AssistantValidationError.forbiddenIdentifier(uuid)) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: samplePack())
        }
    }

    @Test("invented amount in answer is rejected")
    func inventedAmount() {
        let draft = AssistantAnswerDraft(
            title: "错误",
            body: "你有 ¥999999。",
            answer: "你有 ¥999999。",
            keyFacts: sampleStructured().keyFacts,
            references: [AssistantReference(key: "availableCash")]
        )
        #expect(throws: AssistantValidationError.inventedAmount("999999")) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: samplePack())
        }
    }

    @Test("legal amount in answer passes")
    func legalAmount() throws {
        let draft = AssistantAnswerDraft(
            title: "可用资金",
            body: "你当前可用资金约为 ¥20000。",
            answer: "你当前可用资金约为 ¥20000。",
            keyFacts: sampleStructured().keyFacts,
            references: [AssistantReference(key: "availableCash")]
        )
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: samplePack())
        #expect(validated.answer.contains("20000"))
    }

    @Test("risk answer from mock provider passes validation")
    func riskAnswer() async throws {
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
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: answerPack)
        #expect(validated.warnings.contains { $0.severity == .risk })
        #expect(validated.references.contains { $0.key == "cashFlow30" })
    }

    @Test("empty-data draft fails before structured validation")
    func emptyData() {
        let pack = AnswerFactPack(intent: .availableCash, dataInsufficient: true)
        let draft = AssistantAnswerDraft(
            title: "无数据",
            body: "暂无数据",
            answer: "暂无数据"
        )
        #expect(throws: AssistantValidationError.dataInsufficient) {
            _ = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        }
    }

    @Test("mock provider ask returns valid structured answer")
    func mockProviderStructured() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Structured"))
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
                amount: Money(amount: 8_000, currencyCode: "CNY"),
                date: Date(),
                merchant: "公司",
                category: "工资",
                transactionType: .income
            )
        )
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
        let answer = try await service.ask(question: "我现在有多少钱？", userId: userId)
        #expect(!answer.answer.isEmpty)
        #expect(!answer.keyFacts.isEmpty)
        #expect(!answer.references.isEmpty)
        #expect(answer.keyFacts.allSatisfy { $0.source == "availableCash" || !$0.source.isEmpty })
        let json = try AssistantStructuredAnswerSerializer.jsonString(answer.structured)
        #expect(json.contains("keyFacts"))
        #expect(!json.contains("userId"))
    }
}
