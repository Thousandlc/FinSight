import Foundation
import Testing
import YoushuAI
import YoushuDomain

@Suite("Financial risk evaluation v2 golden generator")
struct FinancialRiskEvaluationGoldenGeneratorTests {
    @Test("all 29 eval cases have policy inputs")
    func allCasesSupported() throws {
        for caseID in FinancialRiskEvaluationGoldenSupport.allCaseIDs {
            _ = try FinancialRiskEvaluationGoldenSupport.mappedAssessment(for: caseID)
        }
    }

    @Test("generate 29 golden fixture JSON files when YOUSHU_GENERATE_EVAL_GOLDENS=1")
    func generateGoldenFixtures() throws {
        guard ProcessInfo.processInfo.environment["YOUSHU_GENERATE_EVAL_GOLDENS"] == "1" else {
            return
        }
        let root = FinancialRiskEvaluationGoldenSupport.repoRoot()
        let dir = root.appendingPathComponent("TestFixtures/FinancialRiskEvaluationV2")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for caseID in FinancialRiskEvaluationGoldenSupport.allCaseIDs {
            let fixture = try FinancialRiskEvaluationGoldenSupport.makeGoldenFixture(for: caseID)
            let data = try encoder.encode(fixture)
            let path = dir.appendingPathComponent("\(caseID).json")
            try data.write(to: path, options: .atomic)
        }
    }
}

@Suite("Financial risk evaluation v2 full golden parity")
struct FinancialRiskEvaluationFullGoldenParityTests {
    @Test("29/29 golden parity", arguments: FinancialRiskEvaluationGoldenSupport.allCaseIDs)
    func fullGoldenParity(caseID: String) throws {
        let golden = try FinancialRiskEvaluationGoldenSupport.loadGolden(caseID)
        let mapped = try FinancialRiskEvaluationGoldenSupport.mappedAssessment(for: caseID)
        #expect(mapped == golden.financialRiskAssessment)
        #expect(golden.assessmentTruthSource == "swift-policy-golden")
    }

    @Test("C04 emits highDebtPressureScore from production policy")
    func c04DebtPressureHigh() throws {
        let assessment = try FinancialRiskEvaluationGoldenSupport.productionAssessment(for: "C04_multiple_debts")
        #expect(assessment.signals.map(\.reasonCode).contains(.highDebtPressureScore))
    }

    @Test("C06 emits criticalDebtPressure from production policy")
    func c06DebtPressureCritical() throws {
        let assessment = try FinancialRiskEvaluationGoldenSupport.productionAssessment(for: "C06_debt_but_adequate_cashflow")
        #expect(assessment.signals.map(\.reasonCode).contains(.criticalDebtPressure))
    }
}
