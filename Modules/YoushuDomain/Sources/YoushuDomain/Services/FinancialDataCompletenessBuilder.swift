import Foundation

/// Single production mapping for `FinancialDataCompleteness`.
public enum FinancialDataCompletenessBuilder {
    public static func build(
        _ assembly: FinancialRiskPolicyAssemblyContext,
        debtDataState: DebtDataState
    ) -> FinancialDataCompleteness {
        FinancialDataCompleteness(
            debt: debtFieldAvailability(debtDataState: debtDataState, assembly: assembly),
            cashFlowProjection: cashFlowProjectionAvailability(assembly),
            income: incomeAvailability(assembly),
            expense: expenseAvailability(assembly),
            requiredUnknownReasonCodes: []
        )
    }

    // MARK: - Field availability

    private static func debtFieldAvailability(
        debtDataState: DebtDataState,
        assembly: FinancialRiskPolicyAssemblyContext
    ) -> FieldAvailability {
        switch debtDataState {
        case .knownNoDebt, .knownDebt:
            return .known
        case .partial:
            return .partial
        case .missing:
            return .missing
        }
    }

    private static func cashFlowProjectionAvailability(
        _ assembly: FinancialRiskPolicyAssemblyContext
    ) -> FieldAvailability {
        guard assembly.context.hasAccounts || assembly.context.hasTransactions else {
            return .missing
        }
        guard assembly.context.cashFlow30 != nil else {
            return .missing
        }
        if assembly.enrichedFacts.cashFlowRiskExplanation == nil,
           assembly.enrichedFacts.minimumBalance == nil,
           assembly.enrichedFacts.safeBalance == nil {
            return .partial
        }
        return .known
    }

    private static func incomeAvailability(_ assembly: FinancialRiskPolicyAssemblyContext) -> FieldAvailability {
        assembly.context.hasTransactions ? .known : .missing
    }

    private static func expenseAvailability(_ assembly: FinancialRiskPolicyAssemblyContext) -> FieldAvailability {
        assembly.context.hasTransactions ? .known : .missing
    }
}
