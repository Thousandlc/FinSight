import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Financial risk explanation alignment")
struct FinancialRiskExplanationAlignmentTests {
    @Test("A01 safe empty explanations pass")
    func safeEmpty() throws {
        let facts = FinancialRiskTestFixtures.factsForDTIWarning()
        try AssistantExplanationAlignmentValidator.validate(
            riskExplanations: [],
            unknownExplanations: [],
            assessment: FinancialRiskTestFixtures.safeKnownNoDebt(),
            facts: facts
        )
    }

    @Test("extra risk explanation fails")
    func extraRiskFails() {
        let facts = FinancialRiskTestFixtures.factsForDTIWarning()
        #expect(throws: AssistantExplanationAlignmentError.self) {
            try AssistantExplanationAlignmentValidator.validate(
                riskExplanations: [
                    AssistantRiskExplanation(
                        reasonCode: .highDebtPaymentToIncome,
                        text: "extra",
                        citedFactKeys: ["debtPaymentToIncomePercent"]
                    ),
                ],
                unknownExplanations: [],
                assessment: FinancialRiskTestFixtures.safeKnownNoDebt(),
                facts: facts
            )
        }
    }

    @Test("C03 DTI warning exact explanation passes")
    func dtiPass() throws {
        let facts = FinancialRiskTestFixtures.factsForDTIWarning()
        try AssistantExplanationAlignmentValidator.validate(
            riskExplanations: [
                AssistantRiskExplanation(
                    reasonCode: .highDebtPaymentToIncome,
                    text: "债务还款占收入比例需要关注。",
                    citedFactKeys: ["debtPaymentToIncomePercent"]
                ),
            ],
            unknownExplanations: [],
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI(),
            facts: facts
        )
    }

    @Test("E05 missing debt unknown coverage passes")
    func missingDebtUnknown() throws {
        let facts = FinancialRiskTestFixtures.factsForMissingDebt()
        try AssistantExplanationAlignmentValidator.validate(
            riskExplanations: [],
            unknownExplanations: [
                AssistantUnknownExplanation(
                    reasonCode: .debtDataMissing,
                    text: "债务数据不足。"
                ),
            ],
            assessment: FinancialRiskTestFixtures.missingDebtInventory(),
            facts: facts
        )
    }

    @Test("safe plus missing requires unknown not risk")
    func safePlusMissing() throws {
        let facts = FinancialRiskTestFixtures.factsForMissingDebt()
        try AssistantExplanationAlignmentValidator.validate(
            riskExplanations: [],
            unknownExplanations: [
                AssistantUnknownExplanation(
                    reasonCode: .debtDataMissing,
                    text: "债务数据不足，结论仅基于已知范围。"
                ),
            ],
            assessment: FinancialRiskTestFixtures.missingDebtInventory(),
            facts: facts
        )
    }

    @Test("DTI reference absent fails")
    func dtiReferenceAbsent() {
        let facts = FinancialRiskTestFixtures.factsForMissingDebt()
        let draft = AssistantAnswerDraft(
            title: "摘要",
            body: "正文",
            answer: "正文",
            references: [AssistantReference(key: "debtPaymentToIncomePercent")]
        )
        #expect(throws: AssistantValidationError.self) {
            _ = try AssistantAnswerValidator.validateSummary(draft: draft, facts: facts)
        }
    }

    @Test("DTI reference present passes")
    func dtiReferencePresent() throws {
        let facts = FinancialRiskTestFixtures.factsForDTIWarning()
        let draft = AssistantAnswerDraft(
            title: "摘要",
            body: "正文",
            answer: "正文",
            references: [AssistantReference(key: "debtPaymentToIncomePercent")]
        )
        _ = try AssistantAnswerValidator.validateSummary(draft: draft, facts: facts)
    }

    @Test("navigation reference cashFlow30 passes without fact")
    func navigationReference() throws {
        let facts = FinancialRiskTestFixtures.factsForMissingDebt()
        let draft = AssistantAnswerDraft(
            title: "摘要",
            body: "正文",
            answer: "正文",
            references: [AssistantReference(key: "cashFlow30")]
        )
        _ = try AssistantAnswerValidator.validateSummary(draft: draft, facts: facts)
    }
}
