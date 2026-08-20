import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Financial risk fact availability")
struct FinancialRiskFactAvailabilityTests {
    private func aiDraft(referenceKey: String? = nil) -> AssistantAnswerDraft {
        AssistantAnswerDraft(
            title: "本月财务摘要",
            body: "摘要正文。",
            answer: "摘要正文。",
            references: referenceKey.map { [AssistantReference(key: $0)] } ?? []
        )
    }

    @Test("knownDebt registers debtPressureLevel from assembly")
    func knownDebtPresent() {
        let enriched = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            FinancialRiskTestFixtures.factsForDTIWarning(),
            debtPressureLevel: .high,
            debtDataState: .knownDebt
        )
        #expect(enriched.debtPressureLevel == .high)
        #expect(AssistantAnswerValidator.factPack(from: enriched).facts["debtPressureLevel"] == "high")
    }

    @Test("partial omits debtPressureLevel even when assembly has high")
    func partialAbsent() {
        let enriched = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            FinancialRiskTestFixtures.factsForDebtPressureHigh(),
            debtPressureLevel: .high,
            debtDataState: .partial
        )
        #expect(enriched.debtPressureLevel == nil)
        #expect(AssistantAnswerValidator.factPack(from: enriched).facts["debtPressureLevel"] == nil)
    }

    @Test("knownNoDebt omits debtPressureLevel even when assembly has high")
    func knownNoDebtAbsent() {
        let enriched = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            FinancialRiskTestFixtures.factsForDebtPressureHigh(),
            debtPressureLevel: .high,
            debtDataState: .knownNoDebt
        )
        #expect(enriched.debtPressureLevel == nil)
    }

    @Test("missing omits debtPressureLevel even when assembly has high")
    func missingAbsent() {
        let enriched = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            FinancialRiskTestFixtures.factsForDebtPressureHigh(),
            debtPressureLevel: .high,
            debtDataState: .missing
        )
        #expect(enriched.debtPressureLevel == nil)
    }

    @Test("partial debt still allows DTI fact and warning provenance")
    func partialDTIRegression() throws {
        let facts = MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: 25,
            primaryPressure: "债务还款",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            sourceLabels: ["Account"]
        )
        let enriched = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            facts,
            debtPressureLevel: .high,
            debtDataState: .partial
        )
        #expect(enriched.debtPaymentToIncomePercent == 25)
        #expect(enriched.debtPressureLevel == nil)

        let projected = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft(),
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI()
        )
        let validated = try AssistantAnswerValidator.validateSummary(draft: projected, facts: enriched)
        #expect(validated.warnings.first?.source == "debtPaymentToIncomePercent")
    }

    @Test("debtPressureLevel reference fails when fact absent")
    func referenceFailsWhenAbsent() {
        let facts = FinancialRiskTestFixtures.factsForDTIWarning()
        let draft = aiDraft(referenceKey: "debtPressureLevel")
        #expect(throws: AssistantValidationError.invalidReference("debtPressureLevel")) {
            _ = try AssistantAnswerValidator.validateSummary(draft: draft, facts: facts)
        }
    }

    @Test("debtPressureLevel reference passes when fact present")
    func referencePassesWhenPresent() throws {
        let facts = FinancialRiskTestFixtures.factsForDebtPressureHigh()
        let draft = aiDraft(referenceKey: "debtPressureLevel")
        _ = try AssistantAnswerValidator.validateSummary(draft: draft, facts: facts)
    }

    @Test("knownDebt debt pressure warning validates end-to-end")
    func knownDebtDebtPressureRegression() throws {
        let projected = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft(),
            assessment: FinancialRiskTestFixtures.warningDebtPressureHigh()
        )
        _ = try AssistantAnswerValidator.validateSummary(
            draft: projected,
            facts: FinancialRiskTestFixtures.factsForDebtPressureHigh()
        )
    }
}
