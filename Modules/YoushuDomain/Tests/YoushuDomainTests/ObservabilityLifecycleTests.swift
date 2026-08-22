import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("iOS assistant/Home observability lifecycle")
struct ObservabilityLifecycleTests {
    private struct InventingAssistant: FinancialAssisting {
        let name = "inventing"

        func phraseAnswer(
            request: AssistantRequestDTO,
            facts: AnswerFactPack
        ) async throws -> AssistantAnswerDraft {
            AssistantAnswerDraft(title: "回答", body: "占位")
        }

        func phraseMonthlySummary(
            request: AssistantRequestDTO,
            facts: MonthlySummaryFacts,
            riskAssessment: FinancialRiskAssessment
        ) async throws -> AssistantAnswerDraft {
            let text = "本月神秘支出 ¥88888001 VALIDATOR_AMOUNT_CANARY。"
            return AssistantAnswerDraft(title: "本月摘要", body: text, answer: text)
        }

        func phrasePurchaseScenario(
            request: AssistantRequestDTO,
            scenario: PurchaseScenario
        ) async throws -> AssistantAnswerDraft {
            AssistantAnswerDraft(title: "购买", body: "占位")
        }

        func phraseInsight(
            request: AssistantRequestDTO,
            facts: InsightFactPack
        ) async throws -> AssistantAnswerDraft {
            AssistantAnswerDraft(title: "洞察", body: "占位")
        }
    }

    private actor ThrowingInsightRepository: FinancialInsightRepository {
        func upsert(_ insight: FinancialInsight) async throws {
            throw DataError.persistenceFailed(
                "SOURCE_ID_CANARY title=\(insight.title) body=\(insight.body)"
            )
        }

        func fetchAll(userId: UUID) async throws -> [FinancialInsight] { [] }
        func delete(id: UUID) async throws {}
    }

    private func seedLedger(container: RepositoryContainer, userId: UUID) async throws {
        try await container.users.upsert(User(id: userId, displayName: "Obs"))
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
                merchant: "MERCHANT_SECRET_CANARY",
                category: "工资",
                transactionType: .income,
                note: "NOTE_SECRET_CANARY"
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
    }

    private func makeService(
        container: RepositoryContainer,
        assistant: any FinancialAssisting,
        insights: any FinancialInsightRepository,
        consentService: AIDataConsentService? = nil
    ) -> FinancialAssistantService {
        FinancialAssistantService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: insights,
            users: container.users,
            assistant: assistant,
            consentService: consentService
        )
    }

    private func assertNoCanaries(_ text: String) {
        for canary in [
            "QUESTION_SECRET_CANARY",
            "FINANCIAL_CONTEXT_SECRET_CANARY",
            "MERCHANT_SECRET_CANARY",
            "NOTE_SECRET_CANARY",
            "AUTH_SECRET_CANARY",
            "RAW_RESPONSE_SECRET_CANARY",
            "VALIDATOR_AMOUNT_CANARY",
            "88888001",
            "SOURCE_ID_CANARY",
            "localizedDescription",
            "财务助手 Context",
        ] {
            #expect(!text.contains(canary), "telemetry leaked \(canary)")
        }
    }

    @Test("validator rejection emits allowlisted type without associated amount")
    func validatorTelemetryOmitsAmount() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let service = makeService(
            container: container,
            assistant: InventingAssistant(),
            insights: container.insights
        )
        let collector = ObservabilityEventCollector()
        do {
            _ = try await ObservabilityEmission.$collector.withValue(collector) {
                try await service.generateMonthlySummaryWithRiskAssessment(userId: userId)
            }
            Issue.record("expected validator rejection")
        } catch let error as AssistantValidationError {
            #expect(error == .inventedAmount("88888001"))
        }
        let event = try #require(collector.last)
        #expect(event.outcome == .failed)
        #expect(event.failureStage == .assistantValidation)
        #expect(event.errorCode == .validationRejected)
        #expect(event.validatorFailureType == .inventedAmount)
        #expect(event.retryability == .notRetryable)
        let text = try collector.encodedProductionOutput()
        assertNoCanaries(text)
        #expect(text.contains("inventedAmount"))
    }

    @Test("insight upsert failure emits insightPersistence without content or source ids")
    func persistenceTelemetry() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let service = makeService(
            container: container,
            assistant: MockAIProvider(),
            insights: ThrowingInsightRepository()
        )
        let collector = ObservabilityEventCollector()
        do {
            _ = try await ObservabilityEmission.$collector.withValue(collector) {
                try await service.generateMonthlySummaryWithRiskAssessment(userId: userId)
            }
            Issue.record("expected persistence failure")
        } catch let error as DataError {
            if case .persistenceFailed(let message) = error {
                #expect(message.contains("SOURCE_ID_CANARY"))
            } else {
                Issue.record("expected persistenceFailed")
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
        let event = try #require(collector.last)
        #expect(event.outcome == .failed)
        #expect(event.failureStage == .insightPersistence)
        #expect(event.errorCode == .persistenceFailure)
        #expect(event.retryability == .notRetryable)
        let text = try collector.encodedProductionOutput()
        assertNoCanaries(text)
        #expect(!text.contains("本月财务摘要"))
        #expect(!text.contains("主要压力"))
    }

    @Test("attempted monthly summary without consent emits consentRequired")
    func consentTelemetryOnAttemptedOperation() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let service = makeService(
            container: container,
            assistant: MockAIProvider(),
            insights: container.insights,
            consentService: consentService
        )
        let collector = ObservabilityEventCollector()
        do {
            _ = try await ObservabilityEmission.$collector.withValue(collector) {
                try await service.generateMonthlySummaryWithRiskAssessment(userId: userId)
            }
            Issue.record("expected consentRequired")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("财务助手 Context"))
        }
        let event = try #require(collector.last)
        #expect(event.failureStage == .consent)
        #expect(event.errorCode == .consentRequired)
        #expect(event.outcome == .failed)
        assertNoCanaries(try collector.encodedProductionOutput())
    }
}
