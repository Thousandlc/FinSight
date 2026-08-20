import Foundation

import YoushuFoundation



/// Maps existing production deterministic outputs to `FinancialRiskPolicyInput` without recomputing financial facts.

public enum FinancialRiskPolicyInputBuilder {

    public static func build(_ assembly: FinancialRiskPolicyAssemblyContext) -> FinancialRiskPolicyInput {

        let loadState: DebtInventoryLoadState = assembly.debtInventoryLoadSucceeded ? .loaded : .failed

        let debtDataState = DebtDataStateBuilder.build(

            DebtDataStateBuilder.SemanticInput(

                debts: assembly.debts,

                totalOutstanding: DebtBalanceCalculator.totalOutstanding(debts: assembly.debts),

                repositoryLoadState: loadState,

                inventoryEstablishment: assembly.debtInventoryEstablishment,

                importInProgress: assembly.debtImportInProgress,

                monthlyDebtPayment: assembly.enrichedFacts.monthlyDebtPayment

            )

        )

        let dataCompleteness = FinancialDataCompletenessBuilder.build(assembly, debtDataState: debtDataState)



        return FinancialRiskPolicyInput(

            minimumBalance: minimumBalanceField(assembly),

            safeBalance: safeBalanceField(assembly),

            estimatedMonthEndBalance: .known(assembly.enrichedFacts.estimatedMonthEndBalance),

            monthlyIncome: .known(assembly.enrichedFacts.monthlyIncome),

            monthlyExpense: .known(assembly.enrichedFacts.monthlyExpense),

            debtPaymentToIncomePercent: dtiField(assembly),

            debtPressureLevel: debtPressureLevelField(assembly, debtDataState: debtDataState),

            debtDataState: debtDataState,

            dataCompleteness: dataCompleteness,

            evaluatedAt: assembly.evaluatedAt

        )

    }



    // MARK: - Money / decimal fields



    private static func minimumBalanceField(_ assembly: FinancialRiskPolicyAssemblyContext) -> PolicyMoneyField {

        let currency = assembly.context.currencyCode

        if let enriched = assembly.enrichedFacts.minimumBalance {

            return .known(enriched)

        }

        if let slice = assembly.context.cashFlow30 {

            return .known(slice.minimumBalance)

        }

        return .missing(currencyCode: currency)

    }



    private static func safeBalanceField(_ assembly: FinancialRiskPolicyAssemblyContext) -> PolicyMoneyField {

        let currency = assembly.context.currencyCode

        if let enriched = assembly.enrichedFacts.safeBalance {

            return .known(enriched)

        }

        return .known(Money(amount: assembly.safeBalance.amount, currencyCode: currency))

    }



    private static func dtiField(_ assembly: FinancialRiskPolicyAssemblyContext) -> PolicyDecimalField {

        if let percent = assembly.context.debtPaymentToIncomePercent {

            return .known(percent)

        }

        return .missing

    }



    private static func debtPressureLevelField(

        _ assembly: FinancialRiskPolicyAssemblyContext,

        debtDataState: DebtDataState

    ) -> DebtPressureLevel? {

        guard debtDataState == .knownDebt else { return nil }

        return assembly.debtPressureLevel

    }

}


