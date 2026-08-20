import Foundation
import Testing
import YoushuAI
import YoushuDomain

@Suite("Financial risk evaluation v2 golden parity")
struct FinancialRiskEvaluationGoldenParityTests {
    @Test("smoke golden fixtures contain no PII or identifiers")
    func piiAudit() throws {
        for caseID in FinancialRiskEvaluationGoldenSupport.smokeCaseIDs {
            let golden = try FinancialRiskEvaluationGoldenSupport.loadGolden(caseID)
            let text = String(data: try JSONEncoder().encode(golden.financialRiskAssessment), encoding: .utf8) ?? ""
            for forbidden in ["userId", "accountId", "debtId", "transactionId", "merchant", "uuid", "UUID"] {
                #expect(!text.localizedCaseInsensitiveContains(forbidden), "forbidden token in \(caseID)")
            }
        }
    }

    @Test("A01 production policy golden parity", arguments: ["A01_healthy_cashflow"])
    func vectorGoldenParity(caseID: String) throws {
        try assertGoldenParity(caseID: caseID)
    }

    @Test("B04 negative projection golden parity", arguments: ["B04_short_term_negative_balance"])
    func b04GoldenParity(caseID: String) throws {
        try assertGoldenParity(caseID: caseID)
    }

    @Test("C03 DTI warning golden parity uses highDebtPaymentToIncome", arguments: ["C03_high_monthly_payment"])
    func c03GoldenParity(caseID: String) throws {
        let assessment = try FinancialRiskEvaluationGoldenSupport.productionAssessment(for: caseID)
        #expect(assessment.overallLevel == .warning)
        #expect(assessment.signals.map(\.reasonCode).contains(.highDebtPaymentToIncome))
        #expect(!assessment.signals.map(\.reasonCode).contains(.highDebtPressureScore))
        try assertGoldenParity(caseID: caseID)
    }

    @Test("C01 production semantic golden parity", arguments: ["C01_no_debt"])
    func c01ProductionGoldenParity(caseID: String) throws {
        let assessment = try FinancialRiskEvaluationGoldenSupport.productionAssessment(for: caseID)
        #expect(assessment.debtDataState == .knownNoDebt)
        #expect(assessment.signals.filter { $0.kind == .debt }.isEmpty)
        try assertGoldenParity(caseID: caseID)
    }

    @Test("E05 missing debt production golden parity", arguments: ["E05_missing_debt_data"])
    func e05ProductionGoldenParity(caseID: String) throws {
        let assessment = try FinancialRiskEvaluationGoldenSupport.productionAssessment(for: caseID)
        #expect(assessment.debtDataState == .missing)
        #expect(assessment.dataCompleteness.requiredUnknownReasonCodes.contains(.debtDataMissing))
        #expect(assessment.signals.isEmpty)
        try assertGoldenParity(caseID: caseID)
    }

    @Test("E01 partial debt production golden parity", arguments: ["E01_partial_debt_data"])
    func e01ProductionGoldenParity(caseID: String) throws {
        let assessment = try FinancialRiskEvaluationGoldenSupport.productionAssessment(for: caseID)
        #expect(assessment.debtDataState == .partial)
        #expect(assessment.overallLevel == .warning)
        #expect(assessment.signals.map(\.reasonCode).contains(.highDebtPaymentToIncome))
        #expect(!assessment.signals.map(\.reasonCode).contains(.criticalDebtPressure))
        try assertGoldenParity(caseID: caseID)
    }

    @Test("B04 negativeProjectedBalance cites minimumBalance")
    func b04SourceProvenance() throws {
        let assessment = try FinancialRiskEvaluationGoldenSupport.productionAssessment(for: "B04_short_term_negative_balance")
        let signal = try #require(assessment.signals.first { $0.reasonCode == .negativeProjectedBalance })
        #expect(signal.sourceFactKeys == ["minimumBalance"])
    }

    private func assertGoldenParity(caseID: String) throws {
        let golden = try FinancialRiskEvaluationGoldenSupport.loadGolden(caseID)
        let mapped = try FinancialRiskEvaluationGoldenSupport.mappedAssessment(for: caseID)
        #expect(mapped == golden.financialRiskAssessment)
        #expect(golden.assessmentTruthSource == "swift-policy-golden")
    }
}
