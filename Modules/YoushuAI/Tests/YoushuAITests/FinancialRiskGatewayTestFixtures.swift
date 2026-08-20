import Foundation
import YoushuDomain
import YoushuFoundation

enum FinancialRiskGatewayTestFixtures {
    static func safeKnownNoDebt() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .safe,
            signals: [],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known
            ),
            debtDataState: .knownNoDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
        )
    }
}
