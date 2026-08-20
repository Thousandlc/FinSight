import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Monthly summary policy projection")
struct MonthlySummaryPolicyProjectionTests {
    private func aiDraftWithFakeSafety(
        warnings: [AssistantWarning] = [],
        actions: [AssistantAction] = []
    ) -> AssistantAnswerDraft {
        AssistantAnswerDraft(
            title: "本月财务摘要",
            body: "AI 生成的摘要正文。",
            answer: "AI 生成的摘要正文。",
            warnings: warnings,
            actions: actions,
            references: [AssistantReference(key: "availableCash")]
        )
    }

    private func fakeDebtWarning() -> AssistantWarning {
        AssistantWarning(
            title: "AI 债务警告",
            message: "AI 认为债务过高。",
            severity: .risk,
            source: "debtPaymentToIncomePercent"
        )
    }

    private func fakeCashFlowAction() -> AssistantAction {
        AssistantAction(title: "AI 建议查看现金流", destination: .cashFlow)
    }

    private func fakeDebtAction() -> AssistantAction {
        AssistantAction(title: "AI 建议查看债务", destination: .debt)
    }

    @Test("A01 safe assessment discards AI warnings and actions")
    func safeOverridesAI() {
        let aiDraft = aiDraftWithFakeSafety(
            warnings: [fakeDebtWarning()],
            actions: [fakeCashFlowAction(), fakeDebtAction()]
        )
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft,
            assessment: FinancialRiskTestFixtures.safeKnownNoDebt()
        )
        #expect(final.warnings.isEmpty)
        #expect(final.actions.isEmpty)
        #expect(final.title == aiDraft.title)
    }

    @Test("F06 safe assessment discards AI actions")
    func safeDiscardsActions() {
        let aiDraft = aiDraftWithFakeSafety(actions: [fakeCashFlowAction()])
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft,
            assessment: FinancialRiskTestFixtures.safeKnownNoDebt()
        )
        #expect(final.actions.isEmpty)
    }

    @Test("C03 assessment injects deterministic warning when AI omits warnings")
    func warningInjectedFromAssessment() {
        let aiDraft = aiDraftWithFakeSafety()
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft,
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI()
        )
        #expect(final.warnings.count == 1)
        #expect(final.warnings.first?.severity == .warning)
        #expect(final.warnings.first?.source == "debtPaymentToIncomePercent")
        #expect(final.warnings.first?.title == "债务压力偏高")
    }

    @Test("C05 debt warning maps severity source and actions")
    func debtWarningMapping() {
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraftWithFakeSafety(),
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI()
        )
        #expect(final.warnings.first?.severity == .warning)
        #expect(final.warnings.first?.source == "debtPaymentToIncomePercent")
        #expect(final.actions.map(\.destination) == [.cashFlow, .debt])
    }

    @Test("C01 knownNoDebt assessment suppresses AI debt-pressure warning")
    func knownNoDebtSuppressesDebtWarning() {
        let aiDraft = aiDraftWithFakeSafety(warnings: [fakeDebtWarning()], actions: [fakeDebtAction()])
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft,
            assessment: FinancialRiskTestFixtures.safeKnownNoDebt()
        )
        #expect(final.warnings.isEmpty)
        #expect(final.actions.isEmpty)
    }

    @Test("D02 zeroIncomeWithExpenses warning and actions")
    func zeroIncomeWithExpenses() {
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraftWithFakeSafety(warnings: [fakeDebtWarning()]),
            assessment: FinancialRiskTestFixtures.warningZeroIncomeWithExpenses()
        )
        #expect(final.warnings.count == 1)
        #expect(final.warnings.first?.severity == .warning)
        #expect(final.warnings.first?.source == "monthlyIncome")
        #expect(final.warnings.first?.title == "收支异常")
        #expect(final.actions.map(\.destination) == [.cashFlow, .transactions])
    }

    @Test("E05 missing debt has no debt warning or action")
    func missingDebtInventory() {
        let aiDraft = aiDraftWithFakeSafety(
            warnings: [fakeDebtWarning()],
            actions: [fakeDebtAction(), fakeCashFlowAction()]
        )
        let assessment = FinancialRiskTestFixtures.missingDebtInventory()
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(to: aiDraft, assessment: assessment)
        #expect(final.warnings.isEmpty)
        #expect(final.actions.isEmpty)
        #expect(assessment.dataCompleteness.requiredUnknownReasonCodes.contains(.debtDataMissing))
    }

    @Test("B04 negativeProjectedBalance maps risk severity and cashFlow action")
    func negativeProjectedBalanceRisk() {
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraftWithFakeSafety(),
            assessment: FinancialRiskTestFixtures.riskNegativeProjectedBalance()
        )
        #expect(final.warnings.count == 1)
        #expect(final.warnings.first?.severity == .risk)
        #expect(final.warnings.first?.source == "minimumBalance")
        #expect(final.actions.map(\.destination) == [.cashFlow])
    }

    @Test("risk assessment preserves risk severity over AI downgrade attempt")
    func riskNotDowngradedByAI() {
        let aiDraft = aiDraftWithFakeSafety(
            warnings: [
                AssistantWarning(
                    title: "AI 弱警告",
                    message: "AI 试图降级。",
                    severity: .warning,
                    source: "minimumBalance"
                ),
            ]
        )
        let final = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft,
            assessment: FinancialRiskTestFixtures.riskNegativeProjectedBalance()
        )
        #expect(final.warnings.first?.severity == .risk)
    }

    @Test("ordering is stable for warnings and actions")
    func stableOrdering() {
        let assessment = FinancialRiskAssessment(
            overallLevel: .warning,
            signals: [
                FinancialRiskSignal(
                    kind: .debt,
                    level: .warning,
                    reasonCode: .highDebtPaymentToIncome,
                    sourceFactKeys: ["debtPaymentToIncomePercent"],
                    recommendedActionDestinations: [.debt, .cashFlow]
                ),
                FinancialRiskSignal(
                    kind: .incomeExpense,
                    level: .warning,
                    reasonCode: .zeroIncomeWithExpenses,
                    sourceFactKeys: ["monthlyIncome", "monthlyExpense"],
                    recommendedActionDestinations: [.transactions, .cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: FinancialRiskTestFixtures.evaluatedAt
        )
        let first = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraftWithFakeSafety(),
            assessment: assessment
        )
        let second = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraftWithFakeSafety(warnings: [fakeDebtWarning()]),
            assessment: assessment
        )
        #expect(first.warnings.map(\.source) == second.warnings.map(\.source))
        #expect(first.actions.map(\.destination) == second.actions.map(\.destination))
        #expect(first.actions.map(\.destination) == [.cashFlow, .debt, .transactions])
    }

    @Test("metamorphic: different AI drafts yield same policy warnings and actions")
    func metamorphicAIDraftIndependence() {
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let draftA = aiDraftWithFakeSafety(
            warnings: [fakeDebtWarning()],
            actions: [fakeDebtAction()]
        )
        let draftB = aiDraftWithFakeSafety(
            warnings: [],
            actions: [fakeCashFlowAction()]
        )
        let finalA = MonthlySummaryPolicyProjection.applyPolicyOwnership(to: draftA, assessment: assessment)
        let finalB = MonthlySummaryPolicyProjection.applyPolicyOwnership(to: draftB, assessment: assessment)
        #expect(finalA.warnings == finalB.warnings)
        #expect(finalA.actions == finalB.actions)
    }

    @Test("policy warning source passes monthly summary validator")
    func sourceValidation() throws {
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
        let aiDraft = AssistantAnswerDraft(
            title: "本月财务摘要",
            body: "摘要正文。",
            answer: "摘要正文。"
        )
        let policyDraft = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft,
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI()
        )
        let validated = try AssistantAnswerValidator.validateSummary(draft: policyDraft, facts: facts)
        #expect(validated.warnings.count == 1)
        #expect(validated.actions.count == 2)
    }

    @Test("v1 emitted reason codes are derived from signal-emitting rules")
    func v1EmittedReasonCodesCatalog() {
        let emitted = FinancialRiskPolicySpecification.v1EmittedSignalReasonCodes
        let expected: Set<FinancialRiskReasonCode> = [
            .negativeProjectedBalance,
            .cashFlowBelowSafeBalance,
            .monthEndBelowSafeBalance,
            .highDebtPressureScore,
            .criticalDebtPressure,
            .highDebtPaymentToIncome,
            .zeroIncomeWithExpenses,
        ]
        #expect(emitted == expected)
        #expect(!emitted.contains(.criticalDebtPaymentToIncome))
        #expect(!emitted.contains(.healthyCashBuffer))
        for rule in FinancialRiskPolicySpecification.signalEmittingRules {
            #expect(emitted.contains(rule.reasonCode))
        }
    }
}
