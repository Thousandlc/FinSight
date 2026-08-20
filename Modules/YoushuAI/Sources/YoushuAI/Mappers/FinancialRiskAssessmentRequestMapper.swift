import Foundation
import YoushuDomain

/// Maps Domain risk assessment to network request DTO without recomputing policy.
public enum FinancialRiskAssessmentRequestMapper {
    public static func toDTO(_ assessment: FinancialRiskAssessment) -> GatewayFinancialRiskAssessmentDTO {
        GatewayFinancialRiskAssessmentDTO(
            overallLevel: assessment.overallLevel.rawValue,
            policyVersion: assessment.policyVersion,
            debtDataState: assessment.debtDataState.rawValue,
            signals: assessment.signals.map(signalDTO),
            dataCompleteness: completenessDTO(assessment.dataCompleteness)
        )
    }

    private static func signalDTO(_ signal: FinancialRiskSignal) -> GatewayFinancialRiskSignalDTO {
        GatewayFinancialRiskSignalDTO(
            kind: signal.kind.rawValue,
            level: signal.level.rawValue,
            reasonCode: signal.reasonCode.rawValue,
            sourceFactKeys: signal.sourceFactKeys,
            recommendedActionDestinations: signal.recommendedActionDestinations.map(\.rawValue)
        )
    }

    private static func completenessDTO(_ completeness: FinancialDataCompleteness) -> GatewayFinancialDataCompletenessDTO {
        GatewayFinancialDataCompletenessDTO(
            debt: completeness.debt.rawValue,
            cashFlowProjection: completeness.cashFlowProjection.rawValue,
            income: completeness.income.rawValue,
            expense: completeness.expense.rawValue,
            requiredUnknownReasonCodes: completeness.requiredUnknownReasonCodes.map(\.rawValue)
        )
    }
}
