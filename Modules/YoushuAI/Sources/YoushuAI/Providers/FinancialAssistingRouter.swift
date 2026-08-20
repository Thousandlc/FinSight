import Foundation
import YoushuDomain

public struct FinancialAssistingRouter: FinancialAssisting {
    public let mode: FinancialAssistingMode
    private let mock: MockAIProvider
    private let remote: RemoteFinancialAIProvider?

    public init(
        mode: FinancialAssistingMode,
        mock: MockAIProvider = MockAIProvider(),
        remote: RemoteFinancialAIProvider? = nil
    ) {
        self.mode = mode
        self.mock = mock
        self.remote = remote
    }

    public var name: String {
        switch mode {
        case .mock:
            return mock.name
        case .remoteMonthlySummaryOnly:
            return remote?.name ?? "youshu-gateway-unconfigured"
        }
    }

    public func phraseAnswer(
        request: AssistantRequestDTO,
        facts: AnswerFactPack
    ) async throws -> AssistantAnswerDraft {
        try await mock.phraseAnswer(request: request, facts: facts)
    }

    public func phraseMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> AssistantAnswerDraft {
        switch mode {
        case .mock:
            return try await mock.phraseMonthlySummary(
                request: request,
                facts: facts,
                riskAssessment: riskAssessment
            )
        case .remoteMonthlySummaryOnly:
            guard let remote else {
                throw AIGatewayError.notConfigured
            }
            return try await remote.phraseMonthlySummary(
                request: request,
                facts: facts,
                riskAssessment: riskAssessment
            )
        }
    }

    public func phrasePurchaseScenario(
        request: AssistantRequestDTO,
        scenario: PurchaseScenario
    ) async throws -> AssistantAnswerDraft {
        try await mock.phrasePurchaseScenario(request: request, scenario: scenario)
    }

    public func phraseInsight(
        request: AssistantRequestDTO,
        facts: InsightFactPack
    ) async throws -> AssistantAnswerDraft {
        try await mock.phraseInsight(request: request, facts: facts)
    }
}

extension FinancialAssistingRouter: TransactionExtracting {
    public func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
        try await mock.extractTransactionDraft(fromImageData: data)
    }
}

extension FinancialAssistingRouter: DebtScanning {
    public func scanDebts(from documents: [BillDocument]) async throws -> [DebtCandidate] {
        try await mock.scanDebts(from: documents)
    }
}

extension FinancialAssistingRouter: InsightExplaining {
    public func explain(userId: UUID, titleHint: String) async throws -> FinancialInsight {
        try await mock.explain(userId: userId, titleHint: titleHint)
    }
}
