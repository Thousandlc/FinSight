import Foundation
import YoushuDomain

public struct RemoteFinancialAIProvider: FinancialAssisting {
    public let name = "youshu-gateway"

    private let client: any AIGatewayClientProtocol

    public init(client: any AIGatewayClientProtocol) {
        self.client = client
    }

    public func phraseAnswer(
        request: AssistantRequestDTO,
        facts: AnswerFactPack
    ) async throws -> AssistantAnswerDraft {
        throw AIGatewayError.unsupportedOperation
    }

    public func phraseMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> AssistantAnswerDraft {
        let result = try await client.completeMonthlySummary(
            request: request,
            facts: facts,
            riskAssessment: riskAssessment
        )
        return result.draft
    }

    public func phrasePurchaseScenario(
        request: AssistantRequestDTO,
        scenario: PurchaseScenario
    ) async throws -> AssistantAnswerDraft {
        throw AIGatewayError.unsupportedOperation
    }

    public func phraseInsight(
        request: AssistantRequestDTO,
        facts: InsightFactPack
    ) async throws -> AssistantAnswerDraft {
        throw AIGatewayError.unsupportedOperation
    }
}
