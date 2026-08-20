import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

struct RiskProvenanceCase: Sendable {
    let reasonCode: FinancialRiskReasonCode
    let assessment: FinancialRiskAssessment
    let facts: MonthlySummaryFacts
    let expectedPrimarySource: String
}

private func allRiskProvenanceCases() -> [RiskProvenanceCase] {
    [
        RiskProvenanceCase(
            reasonCode: .negativeProjectedBalance,
            assessment: FinancialRiskTestFixtures.riskNegativeProjectedBalance(),
            facts: FinancialRiskTestFixtures.factsForNegativeProjectedBalance(),
            expectedPrimarySource: "minimumBalance"
        ),
        RiskProvenanceCase(
            reasonCode: .cashFlowBelowSafeBalance,
            assessment: FinancialRiskTestFixtures.warningCashFlowBelowSafe(),
            facts: FinancialRiskTestFixtures.factsForNegativeProjectedBalance(),
            expectedPrimarySource: "minimumBalance"
        ),
        RiskProvenanceCase(
            reasonCode: .monthEndBelowSafeBalance,
            assessment: FinancialRiskPolicyProvenanceEmissionFixtures.monthEndBelowSafeFallbackAssessment(),
            facts: FinancialRiskPolicyProvenanceEmissionFixtures.monthEndBelowSafeFallbackFacts(),
            expectedPrimarySource: "estimatedMonthEndBalance"
        ),
        RiskProvenanceCase(
            reasonCode: .highDebtPressureScore,
            assessment: FinancialRiskTestFixtures.warningDebtPressureHigh(),
            facts: FinancialRiskTestFixtures.factsForDebtPressureHigh(),
            expectedPrimarySource: "debtPressureLevel"
        ),
        RiskProvenanceCase(
            reasonCode: .criticalDebtPressure,
            assessment: FinancialRiskTestFixtures.riskDebtPressureCritical(),
            facts: MonthlySummaryFacts(
                availableCash: Money(amount: 1_000, currencyCode: "CNY"),
                monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
                monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
                monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
                debtPaymentToIncomePercent: nil,
                primaryPressure: "债务还款",
                estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
                debtPressureLevel: .critical,
                sourceLabels: ["Account", "Debt"]
            ),
            expectedPrimarySource: "debtPressureLevel"
        ),
        RiskProvenanceCase(
            reasonCode: .highDebtPaymentToIncome,
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI(),
            facts: FinancialRiskTestFixtures.factsForDTIWarning(),
            expectedPrimarySource: "debtPaymentToIncomePercent"
        ),
        RiskProvenanceCase(
            reasonCode: .zeroIncomeWithExpenses,
            assessment: FinancialRiskTestFixtures.warningZeroIncomeWithExpenses(),
            facts: FinancialRiskTestFixtures.factsForZeroIncomeWithExpenses(),
            expectedPrimarySource: "monthlyIncome"
        ),
    ]
}

@Suite("Financial risk fact provenance")
struct FinancialRiskProvenanceTests {
    private func aiDraft() -> AssistantAnswerDraft {
        AssistantAnswerDraft(
            title: "本月财务摘要",
            body: "摘要正文。",
            answer: "摘要正文。"
        )
    }

    private func registeredKeys(for facts: MonthlySummaryFacts) -> Set<String> {
        let pack = AssistantAnswerValidator.factPack(from: facts)
        return Set(pack.facts.keys).union(pack.amounts.keys)
    }

    @Test("v1 emitted catalog has seven reason codes")
    func v1CatalogCount() {
        #expect(FinancialRiskPolicySpecification.v1EmittedSignalReasonCodes.count == 7)
    }

    @Test("v1 provenance matrix closes all emitted signals", arguments: allRiskProvenanceCases())
    func provenanceMatrix(provenanceCase: RiskProvenanceCase) throws {
        let signal = try #require(
            provenanceCase.assessment.signals.first {
                $0.reasonCode == provenanceCase.reasonCode
            }
        )
        #expect(!signal.sourceFactKeys.isEmpty)

        let keys = registeredKeys(for: provenanceCase.facts)
        for sourceKey in signal.sourceFactKeys {
            #expect(keys.contains(sourceKey), "Missing registered key \(sourceKey) for \(provenanceCase.reasonCode.rawValue)")
        }

        let projected = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft(),
            assessment: provenanceCase.assessment
        )
        let warning = try #require(projected.warnings.first)
        #expect(warning.source == provenanceCase.expectedPrimarySource)
        #expect(keys.contains(warning.source))

        _ = try AssistantAnswerValidator.validateSummary(draft: projected, facts: provenanceCase.facts)
    }

    @Test("debtPressureLevel uses machine-readable raw value in fact pack")
    func debtPressureLevelFactValue() {
        let facts = FinancialRiskTestFixtures.factsForDebtPressureHigh()
        let pack = AssistantAnswerValidator.factPack(from: facts)
        #expect(pack.facts["debtPressureLevel"] == "high")
        #expect(!pack.facts["debtPressureLevel"]!.contains("偏高"))
    }

    @Test("debtPressureLevel omitted from fact pack when not present on facts")
    func debtPressureLevelAbsentWhenNil() {
        let facts = FinancialRiskTestFixtures.factsForDTIWarning()
        let pack = AssistantAnswerValidator.factPack(from: facts)
        #expect(pack.facts["debtPressureLevel"] == nil)
    }

    @Test("enrichDebtPressureProvenance uses assembly level without recomputation")
    func enrichUsesAssemblyLevel() {
        let base = FinancialRiskTestFixtures.factsForDTIWarning()
        let enriched = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            base,
            debtPressureLevel: .high,
            debtDataState: .knownDebt
        )
        #expect(enriched.debtPressureLevel == .high)
    }

    @Test("knownNoDebt omits debtPressureLevel from facts even when assembly has level")
    func knownNoDebtOmitsDebtPressureFact() {
        let base = FinancialRiskTestFixtures.factsForDebtPressureHigh()
        let enriched = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            base,
            debtPressureLevel: .critical,
            debtDataState: .knownNoDebt
        )
        #expect(enriched.debtPressureLevel == nil)
        #expect(AssistantAnswerValidator.factPack(from: enriched).facts["debtPressureLevel"] == nil)
    }

    @Test("C03 DTI warning validates with debtPaymentToIncomePercent source")
    func c03DTIRegression() throws {
        let projected = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft(),
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI()
        )
        let validated = try AssistantAnswerValidator.validateSummary(
            draft: projected,
            facts: FinancialRiskTestFixtures.factsForDTIWarning()
        )
        #expect(validated.warnings.first?.source == "debtPaymentToIncomePercent")
    }

    @Test("debt pressure high validates end-to-end")
    func debtPressureHighRegression() throws {
        let projected = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft(),
            assessment: FinancialRiskTestFixtures.warningDebtPressureHigh()
        )
        let validated = try AssistantAnswerValidator.validateSummary(
            draft: projected,
            facts: FinancialRiskTestFixtures.factsForDebtPressureHigh()
        )
        #expect(validated.warnings.first?.severity == .warning)
        #expect(validated.warnings.first?.source == "debtPressureLevel")
    }

    @Test("debt pressure critical validates end-to-end")
    func debtPressureCriticalRegression() throws {
        let facts = MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "债务还款",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            debtPressureLevel: .critical,
            sourceLabels: ["Debt"]
        )
        let projected = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft(),
            assessment: FinancialRiskTestFixtures.riskDebtPressureCritical()
        )
        let validated = try AssistantAnswerValidator.validateSummary(draft: projected, facts: facts)
        #expect(validated.warnings.first?.severity == .risk)
        #expect(validated.warnings.first?.source == "debtPressureLevel")
    }

    @Test("cashFlowBelowSafeBalance keeps multi-source provenance with minimumBalance primary")
    func belowSafePrimarySource() {
        let signal = FinancialRiskTestFixtures.warningCashFlowBelowSafe().signals[0]
        #expect(signal.sourceFactKeys == ["minimumBalance", "safeBalance"])
        #expect(signal.primarySourceFactKey == "minimumBalance")
    }

    @Test("debtPressureLevel fact pack contains no PII")
    func piiAudit() {
        let pack = AssistantAnswerValidator.factPack(from: FinancialRiskTestFixtures.factsForDebtPressureHigh())
        guard let value = pack.facts["debtPressureLevel"] else {
            Issue.record("Expected debtPressureLevel fact")
            return
        }
        #expect(["low", "medium", "high", "critical"].contains(value))
        #expect(!value.contains("-"))
    }
}
