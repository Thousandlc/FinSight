import Foundation

/// Deterministic expected outcomes for v1 policy (specification fixtures — not engine output).
public struct FinancialRiskPolicyTestVector: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var scenarioNotes: [String]
    public var debtDataState: DebtDataState
    public var expectedOverallLevel: FinancialRiskLevel
    public var expectedSignalReasonCodes: [FinancialRiskReasonCode]
    public var expectedSuppressedReasonCodes: [FinancialRiskReasonCode]
    public var expectedCompletenessDebt: FieldAvailability
    public var expectedRequiredUnknowns: [FinancialRiskReasonCode]
    public var evalCaseMapping: String?

    public init(
        id: String,
        title: String,
        scenarioNotes: [String],
        debtDataState: DebtDataState,
        expectedOverallLevel: FinancialRiskLevel,
        expectedSignalReasonCodes: [FinancialRiskReasonCode],
        expectedSuppressedReasonCodes: [FinancialRiskReasonCode] = [],
        expectedCompletenessDebt: FieldAvailability = .known,
        expectedRequiredUnknowns: [FinancialRiskReasonCode] = [],
        evalCaseMapping: String? = nil
    ) {
        self.id = id
        self.title = title
        self.scenarioNotes = scenarioNotes
        self.debtDataState = debtDataState
        self.expectedOverallLevel = expectedOverallLevel
        self.expectedSignalReasonCodes = expectedSignalReasonCodes
        self.expectedSuppressedReasonCodes = expectedSuppressedReasonCodes
        self.expectedCompletenessDebt = expectedCompletenessDebt
        self.expectedRequiredUnknowns = expectedRequiredUnknowns
        self.evalCaseMapping = evalCaseMapping
    }
}

public enum FinancialRiskPolicyTestVectors {
    public static let catalog: [FinancialRiskPolicyTestVector] = [
        FinancialRiskPolicyTestVector(
            id: "V1",
            title: "healthy complete",
            scenarioNotes: ["All core facts known", "No warning/risk conditions"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .safe,
            expectedSignalReasonCodes: [],
            evalCaseMapping: "A01/F06"
        ),
        FinancialRiskPolicyTestVector(
            id: "V2",
            title: "min below safe but positive",
            scenarioNotes: ["minimumBalance >= 0", "minimumBalance < safeBalance"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .warning,
            expectedSignalReasonCodes: [.cashFlowBelowSafeBalance],
            evalCaseMapping: "B01"
        ),
        FinancialRiskPolicyTestVector(
            id: "V3",
            title: "min negative",
            scenarioNotes: ["minimumBalance < 0"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .risk,
            expectedSignalReasonCodes: [.negativeProjectedBalance],
            evalCaseMapping: "B04"
        ),
        FinancialRiskPolicyTestVector(
            id: "V4",
            title: "min negative also below safe",
            scenarioNotes: ["CF-1 only; CF-2 deduped"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .risk,
            expectedSignalReasonCodes: [.negativeProjectedBalance],
            evalCaseMapping: "B04 dedup"
        ),
        FinancialRiskPolicyTestVector(
            id: "V5",
            title: "debt high",
            scenarioNotes: ["DebtPressureLevel.high from existing engine"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .warning,
            expectedSignalReasonCodes: [.highDebtPressureScore],
            evalCaseMapping: "C03/C05 supporting"
        ),
        FinancialRiskPolicyTestVector(
            id: "V6",
            title: "debt critical",
            scenarioNotes: ["DebtPressureLevel.critical"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .risk,
            expectedSignalReasonCodes: [.criticalDebtPressure]
        ),
        FinancialRiskPolicyTestVector(
            id: "V7",
            title: "DTI 19.9%",
            scenarioNotes: ["monthlyIncome > 0", "DTI below product threshold"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .safe,
            expectedSignalReasonCodes: []
        ),
        FinancialRiskPolicyTestVector(
            id: "V8",
            title: "DTI 20%",
            scenarioNotes: ["Product v1 threshold boundary inclusive"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .warning,
            expectedSignalReasonCodes: [.highDebtPaymentToIncome],
            evalCaseMapping: "C03/C05"
        ),
        FinancialRiskPolicyTestVector(
            id: "V9",
            title: "DTI 55% without critical debt level",
            scenarioNotes: ["DTI warning only", "No v1 DTI risk threshold"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .warning,
            expectedSignalReasonCodes: [.highDebtPaymentToIncome]
        ),
        FinancialRiskPolicyTestVector(
            id: "V10",
            title: "zero income + expense",
            scenarioNotes: ["income known zero", "expense known > 0"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .warning,
            expectedSignalReasonCodes: [.zeroIncomeWithExpenses],
            evalCaseMapping: "D02"
        ),
        FinancialRiskPolicyTestVector(
            id: "V11",
            title: "zero income + zero expense",
            scenarioNotes: ["No IE-1 trigger"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .safe,
            expectedSignalReasonCodes: []
        ),
        FinancialRiskPolicyTestVector(
            id: "V12",
            title: "knownNoDebt",
            scenarioNotes: [
                "No debt pressure signals",
                "monthlyDebtPayment=0 allowed as neutral fact",
            ],
            debtDataState: .knownNoDebt,
            expectedOverallLevel: .safe,
            expectedSignalReasonCodes: [],
            expectedSuppressedReasonCodes: [
                .highDebtPaymentToIncome,
                .highDebtPressureScore,
                .criticalDebtPressure,
            ],
            evalCaseMapping: "C01 guard"
        ),
        FinancialRiskPolicyTestVector(
            id: "V13",
            title: "partial debt + calculable DTI >= 20",
            scenarioNotes: ["DebtDataState.partial", "DTI computable from known payment + income"],
            debtDataState: .partial,
            expectedOverallLevel: .warning,
            expectedSignalReasonCodes: [.highDebtPaymentToIncome],
            expectedCompletenessDebt: .partial
        ),
        FinancialRiskPolicyTestVector(
            id: "V14",
            title: "missing debt",
            scenarioNotes: ["No debt risk signals", "required unknown debtDataMissing"],
            debtDataState: .missing,
            expectedOverallLevel: .safe,
            expectedSignalReasonCodes: [],
            expectedCompletenessDebt: .missing,
            expectedRequiredUnknowns: [.debtDataMissing],
            evalCaseMapping: "E05"
        ),
        FinancialRiskPolicyTestVector(
            id: "V15",
            title: "safe cash + missing debt",
            scenarioNotes: ["overall safe", "debt completeness missing"],
            debtDataState: .missing,
            expectedOverallLevel: .safe,
            expectedSignalReasonCodes: [],
            expectedCompletenessDebt: .missing,
            expectedRequiredUnknowns: [.debtDataMissing]
        ),
        FinancialRiskPolicyTestVector(
            id: "V16",
            title: "critical debt + safe cash flow",
            scenarioNotes: ["Cash healthy does not cancel critical debt pressure"],
            debtDataState: .knownDebt,
            expectedOverallLevel: .risk,
            expectedSignalReasonCodes: [.criticalDebtPressure]
        ),
    ]

    public static let requiredVectorIDs: Set<String> = [
        "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10",
        "V11", "V12", "V13", "V14", "V15", "V16",
    ]
}
