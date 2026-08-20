import Foundation
import YoushuDomain

public struct GatewayMoneyDTO: Codable, Equatable, Sendable {
    public var amount: String
    public var currencyCode: String

    public init(amount: String, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }
}

public struct GatewayMonthlySummaryFactsDTO: Codable, Equatable, Sendable {
    public var availableCash: GatewayMoneyDTO
    public var monthlyIncome: GatewayMoneyDTO
    public var monthlyExpense: GatewayMoneyDTO
    public var monthlyDebtPayment: GatewayMoneyDTO
    public var debtPaymentToIncomePercent: String?
    public var primaryPressure: String
    public var estimatedMonthEndBalance: GatewayMoneyDTO
    public var cashFlowRiskExplanation: String?
    public var safeBalance: GatewayMoneyDTO?
    public var minimumBalance: GatewayMoneyDTO?
    public var debtPressureLevel: String?
    public var sourceLabels: [String]

    public init(
        availableCash: GatewayMoneyDTO,
        monthlyIncome: GatewayMoneyDTO,
        monthlyExpense: GatewayMoneyDTO,
        monthlyDebtPayment: GatewayMoneyDTO,
        debtPaymentToIncomePercent: String? = nil,
        primaryPressure: String,
        estimatedMonthEndBalance: GatewayMoneyDTO,
        cashFlowRiskExplanation: String? = nil,
        safeBalance: GatewayMoneyDTO? = nil,
        minimumBalance: GatewayMoneyDTO? = nil,
        debtPressureLevel: String? = nil,
        sourceLabels: [String]
    ) {
        self.availableCash = availableCash
        self.monthlyIncome = monthlyIncome
        self.monthlyExpense = monthlyExpense
        self.monthlyDebtPayment = monthlyDebtPayment
        self.debtPaymentToIncomePercent = debtPaymentToIncomePercent
        self.primaryPressure = primaryPressure
        self.estimatedMonthEndBalance = estimatedMonthEndBalance
        self.cashFlowRiskExplanation = cashFlowRiskExplanation
        self.safeBalance = safeBalance
        self.minimumBalance = minimumBalance
        self.debtPressureLevel = debtPressureLevel
        self.sourceLabels = sourceLabels
    }
}

public struct GatewayAssistantAnswerDraftDTO: Codable, Equatable, Sendable {
    public var title: String
    public var body: String
    public var answer: String
    public var citedFactKeys: [String]
    public var disclaimer: String?
    public var unknowns: [String]
    public var confidence: Double
    public var keyFacts: [AssistantKeyFact]
    public var warnings: [AssistantWarning]
    public var actions: [AssistantAction]
    public var references: [AssistantReference]

    public init(
        title: String,
        body: String,
        answer: String,
        citedFactKeys: [String] = [],
        disclaimer: String? = nil,
        unknowns: [String] = [],
        confidence: Double = 0.8,
        keyFacts: [AssistantKeyFact] = [],
        warnings: [AssistantWarning] = [],
        actions: [AssistantAction] = [],
        references: [AssistantReference] = []
    ) {
        self.title = title
        self.body = body
        self.answer = answer
        self.citedFactKeys = citedFactKeys
        self.disclaimer = disclaimer
        self.unknowns = unknowns
        self.confidence = confidence
        self.keyFacts = keyFacts
        self.warnings = warnings
        self.actions = actions
        self.references = references
    }
}

public struct GatewayRequestEnvelope: Codable, Sendable {
    public var schemaVersion: String
    public var requestId: String
    public var operation: GatewayOperation
    public var assistantRequest: AssistantRequestDTO
    public var monthlySummaryFacts: GatewayMonthlySummaryFactsDTO?
    public var financialRiskAssessment: GatewayFinancialRiskAssessmentDTO?

    public init(
        schemaVersion: String,
        requestId: String,
        operation: GatewayOperation,
        assistantRequest: AssistantRequestDTO,
        monthlySummaryFacts: GatewayMonthlySummaryFactsDTO? = nil,
        financialRiskAssessment: GatewayFinancialRiskAssessmentDTO? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.operation = operation
        self.assistantRequest = assistantRequest
        self.monthlySummaryFacts = monthlySummaryFacts
        self.financialRiskAssessment = financialRiskAssessment
    }
}

public struct GatewayErrorBodyDTO: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var retryAfterSeconds: Int?
}

public struct GatewaySuccessResponseEnvelope: Codable, Sendable {
    public var schemaVersion: String
    public var requestId: String
    public var modelAlias: String
    public var draft: GatewayAssistantAnswerDraftDTO
}

public struct GatewayErrorResponseEnvelope: Codable, Sendable {
    public var schemaVersion: String
    public var requestId: String
    public var error: GatewayErrorBodyDTO
}
