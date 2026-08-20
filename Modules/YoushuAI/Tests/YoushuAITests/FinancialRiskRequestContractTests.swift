import Foundation
import Testing
import YoushuAI
import YoushuDomain
import YoushuFoundation

@Suite("Financial risk request contract")
struct FinancialRiskRequestContractTests {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadGoldenDTO(_ filename: String) throws -> GatewayFinancialRiskAssessmentDTO {
        let url = repoRoot()
            .appendingPathComponent("TestFixtures/FinancialRiskGateway/\(filename)")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GatewayFinancialRiskAssessmentDTO.self, from: data)
    }

    @Test("mapper emits explicit debtDataState and omits evaluatedAt")
    func mapperFields() {
        let dto = FinancialRiskAssessmentRequestMapper.toDTO(FinancialRiskGatewayTestFixtures.safeKnownNoDebt())
        #expect(dto.debtDataState == "knownNoDebt")
        #expect(dto.overallLevel == "safe")
        #expect(dto.policyVersion == "v1")
        let json = try? JSONEncoder().encode(dto)
        #expect(json != nil)
        let text = String(data: json ?? Data(), encoding: .utf8) ?? ""
        #expect(!text.contains("evaluatedAt"))
        #expect(!text.contains("id"))
    }

    @Test("golden safe knownNoDebt matches cross-language fixture")
    func goldenSafeKnownNoDebt() throws {
        let mapped = FinancialRiskAssessmentRequestMapper.toDTO(FinancialRiskGatewayTestFixtures.safeKnownNoDebt())
        let golden = try loadGoldenDTO("golden_safe_known_no_debt.json")
        #expect(mapped == golden)
    }

    @Test("golden warning knownDebt matches cross-language fixture")
    func goldenWarningKnownDebt() throws {
        let mapped = FinancialRiskAssessmentRequestMapper.toDTO(
            FinancialRiskAssessment(
                overallLevel: .warning,
                signals: [
                    FinancialRiskSignal(
                        kind: .debt,
                        level: .warning,
                        reasonCode: .highDebtPaymentToIncome,
                        sourceFactKeys: ["debtPaymentToIncomePercent"],
                        recommendedActionDestinations: [.debt, .cashFlow]
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
                evaluatedAt: FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
            )
        )
        let golden = try loadGoldenDTO("golden_warning_known_debt.json")
        #expect(mapped == golden)
    }

    @Test("golden missing debt matches cross-language fixture")
    func goldenMissingDebt() throws {
        let mapped = FinancialRiskAssessmentRequestMapper.toDTO(
            FinancialRiskAssessment(
                overallLevel: .safe,
                signals: [],
                dataCompleteness: FinancialDataCompleteness(
                    debt: .missing,
                    cashFlowProjection: .known,
                    income: .known,
                    expense: .known,
                    requiredUnknownReasonCodes: [.debtDataMissing]
                ),
                debtDataState: .missing,
                policyVersion: FinancialRiskPolicyVersion.current,
                evaluatedAt: FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
            )
        )
        let golden = try loadGoldenDTO("golden_missing_debt.json")
        #expect(mapped == golden)
    }

    @Test("monthly summary envelope requires financialRiskAssessment field")
    func envelopeIncludesRiskAssessment() throws {
        let context = FinancialContext(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            hasAccounts: true,
            currencyCode: "CNY"
        )
        let envelope = GatewayRequestEnvelope(
            schemaVersion: "v1",
            requestId: "req-test",
            operation: .monthlySummary,
            assistantRequest: FinancialAssistantContextMapper.makeRequest(
                question: "",
                intent: .unknown,
                context: context,
                safeBalance: Money(amount: 2_000, currencyCode: "CNY")
            ),
            monthlySummaryFacts: GatewayMonthlySummaryFactsMapper.toDTO(
                MonthlySummaryFacts(
                    availableCash: Money(amount: 1_000, currencyCode: "CNY"),
                    monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
                    monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
                    monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
                    debtPaymentToIncomePercent: nil,
                    primaryPressure: "债务还款",
                    estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
                    sourceLabels: ["Account"]
                )
            ),
            financialRiskAssessment: FinancialRiskAssessmentRequestMapper.toDTO(
                FinancialRiskGatewayTestFixtures.safeKnownNoDebt()
            )
        )
        let data = try JSONEncoder().encode(envelope)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("financialRiskAssessment"))
        #expect(text.contains("debtDataState"))
        #expect(text.contains("knownNoDebt"))
    }

    @Test("risk DTO serialization excludes PII and identifiers")
    func piiAudit() throws {
        let dto = FinancialRiskAssessmentRequestMapper.toDTO(
            FinancialRiskAssessment(
                overallLevel: .warning,
                signals: [
                    FinancialRiskSignal(
                        kind: .debt,
                        level: .warning,
                        reasonCode: .highDebtPaymentToIncome,
                        sourceFactKeys: ["debtPaymentToIncomePercent"],
                        recommendedActionDestinations: [.debt, .cashFlow]
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
                evaluatedAt: FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
            )
        )
        let text = String(data: try JSONEncoder().encode(dto), encoding: .utf8) ?? ""
        for forbidden in ["userId", "accountId", "debtId", "transactionId", "merchant", "uuid", "UUID"] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden))
        }
    }
}
