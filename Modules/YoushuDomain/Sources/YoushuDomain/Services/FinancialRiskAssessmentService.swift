import Foundation

import YoushuFoundation



/// Thin production assembly boundary: map deterministic outputs → policy input → assessment.

public enum FinancialRiskAssessmentService {

    public static func assemblyContext(

        source: FinancialContextBuilder.Source,

        context: FinancialContext,

        enrichedFacts: MonthlySummaryFacts,

        safeBalance: Money,

        debtInventoryLoadSucceeded: Bool,

        debtInventoryEstablishment: DebtInventoryEstablishmentState,

        debtImportInProgress: Bool = false,

        evaluatedAt: Date

    ) -> FinancialRiskPolicyAssemblyContext {

        let pressureScore = DebtCenterCalculator.debtPressureScore(

            debts: source.debts,

            monthlyRepayment: context.estimatedMonthlyRepayment

        )

        let pressureLevel = DebtCenterCalculator.debtPressureLevel(score: pressureScore)

        return FinancialRiskPolicyAssemblyContext(

            context: context,

            enrichedFacts: enrichedFacts,

            safeBalance: safeBalance,

            debts: source.debts,

            debtInventoryLoadSucceeded: debtInventoryLoadSucceeded,

            debtInventoryEstablishment: debtInventoryEstablishment,

            debtImportInProgress: debtImportInProgress,

            debtPressureLevel: pressureLevel,

            evaluatedAt: evaluatedAt

        )

    }



    public static func assess(_ assembly: FinancialRiskPolicyAssemblyContext) -> FinancialRiskAssessment {

        let input = FinancialRiskPolicyInputBuilder.build(assembly)

        return FinancialRiskPolicyEngine.evaluate(input)

    }

}


