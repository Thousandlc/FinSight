import Foundation

import YoushuFoundation



/// Production assembly bundle for risk policy evaluation. Facts must already be computed upstream.

public struct FinancialRiskPolicyAssemblyContext: Equatable, Sendable {

    public var context: FinancialContext

    public var enrichedFacts: MonthlySummaryFacts

    public var safeBalance: Money

    public var debts: [Debt]

    /// True when `DebtRepository.fetchAll` succeeded for the current user in this assembly path.

    public var debtInventoryLoadSucceeded: Bool

    public var debtInventoryEstablishment: DebtInventoryEstablishmentState

    public var debtImportInProgress: Bool

    public var debtPressureLevel: DebtPressureLevel

    public var evaluatedAt: Date



    public init(

        context: FinancialContext,

        enrichedFacts: MonthlySummaryFacts,

        safeBalance: Money,

        debts: [Debt],

        debtInventoryLoadSucceeded: Bool,

        debtInventoryEstablishment: DebtInventoryEstablishmentState,

        debtImportInProgress: Bool = false,

        debtPressureLevel: DebtPressureLevel,

        evaluatedAt: Date

    ) {

        self.context = context

        self.enrichedFacts = enrichedFacts

        self.safeBalance = safeBalance

        self.debts = debts

        self.debtInventoryLoadSucceeded = debtInventoryLoadSucceeded

        self.debtInventoryEstablishment = debtInventoryEstablishment

        self.debtImportInProgress = debtImportInProgress

        self.debtPressureLevel = debtPressureLevel

        self.evaluatedAt = evaluatedAt

    }

}



/// Result of monthly summary production assembly including deterministic risk assessment (not sent to AI in P0-4.5.4A).

public struct MonthlySummaryRiskAssemblyResult: Equatable, Sendable {

    public var insight: FinancialInsight

    public var riskAssessment: FinancialRiskAssessment



    public init(insight: FinancialInsight, riskAssessment: FinancialRiskAssessment) {

        self.insight = insight

        self.riskAssessment = riskAssessment

    }

}


