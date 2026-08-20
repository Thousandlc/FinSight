import Foundation

/// Network transport DTOs for deterministic financial risk assessment (Domain != Network).
public struct GatewayFinancialRiskSignalDTO: Codable, Equatable, Sendable {
    public var kind: String
    public var level: String
    public var reasonCode: String
    public var sourceFactKeys: [String]
    public var recommendedActionDestinations: [String]

    public init(
        kind: String,
        level: String,
        reasonCode: String,
        sourceFactKeys: [String],
        recommendedActionDestinations: [String]
    ) {
        self.kind = kind
        self.level = level
        self.reasonCode = reasonCode
        self.sourceFactKeys = sourceFactKeys
        self.recommendedActionDestinations = recommendedActionDestinations
    }
}

public struct GatewayFinancialDataCompletenessDTO: Codable, Equatable, Sendable {
    public var debt: String
    public var cashFlowProjection: String
    public var income: String
    public var expense: String
    public var requiredUnknownReasonCodes: [String]

    public init(
        debt: String,
        cashFlowProjection: String,
        income: String,
        expense: String,
        requiredUnknownReasonCodes: [String]
    ) {
        self.debt = debt
        self.cashFlowProjection = cashFlowProjection
        self.income = income
        self.expense = expense
        self.requiredUnknownReasonCodes = requiredUnknownReasonCodes
    }
}

public struct GatewayFinancialRiskAssessmentDTO: Codable, Equatable, Sendable {
    public var overallLevel: String
    public var policyVersion: String
    public var debtDataState: String
    public var signals: [GatewayFinancialRiskSignalDTO]
    public var dataCompleteness: GatewayFinancialDataCompletenessDTO

    public init(
        overallLevel: String,
        policyVersion: String,
        debtDataState: String,
        signals: [GatewayFinancialRiskSignalDTO],
        dataCompleteness: GatewayFinancialDataCompletenessDTO
    ) {
        self.overallLevel = overallLevel
        self.policyVersion = policyVersion
        self.debtDataState = debtDataState
        self.signals = signals
        self.dataCompleteness = dataCompleteness
    }
}
