import Foundation

/// 财务助手语言层：只接收 AI 安全 DTO / 事实包，不访问数据库，不改算金额。
public protocol FinancialAssisting: AIProviding {
    func phraseAnswer(
        request: AssistantRequestDTO,
        facts: AnswerFactPack
    ) async throws -> AssistantAnswerDraft

    func phraseMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> AssistantAnswerDraft

    func phrasePurchaseScenario(
        request: AssistantRequestDTO,
        scenario: PurchaseScenario
    ) async throws -> AssistantAnswerDraft

    func phraseInsight(
        request: AssistantRequestDTO,
        facts: InsightFactPack
    ) async throws -> AssistantAnswerDraft
}
