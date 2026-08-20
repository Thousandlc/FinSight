import Foundation
import Testing
import YoushuDomain

@Suite("Financial risk known zero guard v1 boundary")
struct FinancialRiskKnownZeroGuardV1Tests {
    @Test("knownNoDebt does not suppress neutral debt-kind signal by kind alone")
    func neutralDebtKindAllowed() {
        // Future v1 may introduce non-pressure debt informational signals.
        // Guard must only suppress debt-pressure reason codes.
        let futureNeutral = FinancialRiskSignal(
            kind: .debt,
            level: .safe,
            reasonCode: .budgetNotApplicable,
            sourceFactKeys: ["primaryPressure"]
        )
        #expect(FinancialRiskKnownZeroGuard.allowsSignal(futureNeutral, debtState: .knownNoDebt))
    }

    @Test("knownNoDebt suppresses highDebtPressureScore by reason code")
    func suppressesHighDebtPressureScore() {
        let signal = FinancialRiskSignal(
            kind: .debt,
            level: .warning,
            reasonCode: .highDebtPressureScore,
            sourceFactKeys: ["debtPressureLevel"]
        )
        #expect(!FinancialRiskKnownZeroGuard.allowsSignal(signal, debtState: .knownNoDebt))
    }

    @Test("knownNoDebt suppresses criticalDebtPressure by reason code")
    func suppressesCriticalDebtPressure() {
        let signal = FinancialRiskSignal(
            kind: .debt,
            level: .risk,
            reasonCode: .criticalDebtPressure,
            sourceFactKeys: ["debtPressureLevel"]
        )
        #expect(!FinancialRiskKnownZeroGuard.allowsSignal(signal, debtState: .knownNoDebt))
    }

    @Test("suppressed reason codes are explicit set")
    func suppressedSetIncludesCriticalDebtPressure() {
        #expect(FinancialRiskKnownZeroGuard.suppressedReasonCodes.contains(.criticalDebtPressure))
        #expect(FinancialRiskKnownZeroGuard.suppressedReasonCodes.contains(.highDebtPaymentToIncome))
    }
}

@Suite("Financial risk policy threshold registry")
struct FinancialRiskPolicyThresholdRegistryTests {
    @Test("DTI warning threshold is single source at 20 percent")
    func dtiThresholdSingleSource() {
        #expect(FinancialRiskPolicyThresholdRegistry.dtiWarningThresholdPercent == 20)
        let entry = FinancialRiskPolicyThresholdRegistry.entries.first { $0.name == "dtiWarning" }
        #expect(entry?.owner == .productV1Confirmed)
    }

    @Test("DTI boundary 19.9 does not qualify")
    func dti199NoWarning() {
        #expect(!FinancialRiskPolicyThresholdRegistry.isDTIWarningEligible(percent: Decimal(string: "19.9")!))
    }

    @Test("DTI boundary 20 qualifies")
    func dti20Warning() {
        #expect(FinancialRiskPolicyThresholdRegistry.isDTIWarningEligible(percent: 20))
        #expect(FinancialRiskPolicyThresholdRegistry.isDTIWarningEligible(percent: Decimal(string: "20.0")!))
    }

    @Test("DTI risk threshold not defined in v1 registry")
    func dtiRiskNotDefined() {
        let entry = FinancialRiskPolicyThresholdRegistry.entries.first { $0.name == "dtiRisk" }
        #expect(entry?.owner == .notDefinedInV1)
    }

    @Test("safeBalance registry does not define numeric value")
    func safeBalanceNoMagicNumber() {
        let entry = FinancialRiskPolicyThresholdRegistry.entries.first { $0.name == "safeBalance" }
        #expect(entry?.numericValueDescription == nil)
        #expect(entry?.owner == .cashFlowInputConfiguration)
    }
}

@Suite("Financial risk policy specification validation")
struct FinancialRiskPolicySpecificationValidationTests {
    @Test("policy specification validates without duplicate rule IDs")
    func validatesCatalog() throws {
        try FinancialRiskPolicyValidation.validateSpecification()
    }

    @Test("all rule IDs are unique")
    func uniqueRuleIDs() throws {
        try FinancialRiskPolicyValidation.validateUniqueRuleIDs(FinancialRiskPolicySpecification.allRules)
    }

    @Test("policy version single source matches specification")
    func policyVersionSingleSource() throws {
        #expect(FinancialRiskPolicySpecification.policyVersion == FinancialRiskPolicyVersion.v1)
        #expect(FinancialRiskPolicyVersion.current == FinancialRiskPolicyVersion.v1)
        #expect(FinancialRiskAssessmentAssembly.defaultPolicyVersion == FinancialRiskPolicyVersion.v1)
        try FinancialRiskPolicyValidation.validatePolicyVersion()
    }

    @Test("CF-2 outputs warning not risk for below safe balance")
    func cf2IsWarning() {
        let rule = FinancialRiskPolicySpecification.cf2BelowSafeBalance
        #expect(rule.outputLevel == .warning)
        #expect(rule.reasonCode == .cashFlowBelowSafeBalance)
    }

    @Test("CF-1 outputs risk for negative balance")
    func cf1IsRisk() {
        let rule = FinancialRiskPolicySpecification.cf1NegativeProjectedBalance
        #expect(rule.outputLevel == .risk)
    }

    @Test("debt critical maps to criticalDebtPressure risk")
    func debtCriticalMapping() {
        let rule = FinancialRiskPolicySpecification.debtPressureCritical
        #expect(rule.outputLevel == .risk)
        #expect(rule.reasonCode == .criticalDebtPressure)
    }

    @Test("dedup specification includes CF-1 over CF-2 precedence")
    func dedupCFPrecedence() {
        let dedup = FinancialRiskPolicyDedupSpecification.rules.first { $0.id == "DEDUP-1" }
        #expect(dedup?.retainedReasonCode == .negativeProjectedBalance)
        #expect(dedup?.suppressedReasonCodes.contains(.cashFlowBelowSafeBalance) == true)
    }

    @Test("dedup specification suppresses duplicate DTI when debt pressure present")
    func dedupDTIWhenDebtPressure() {
        let dedup = FinancialRiskPolicyDedupSpecification.rules.first { $0.id == "DEDUP-2" }
        #expect(dedup?.suppressedReasonCodes.contains(.highDebtPaymentToIncome) == true)
    }

    @Test("conflict examples cover A through F")
    func conflictExamplesComplete() {
        let ids = Set(FinancialRiskPolicyDedupSpecification.conflictExamples.map(\.id))
        #expect(ids == Set(["A", "B", "C", "D", "E", "F"]))
    }
}

@Suite("Financial risk policy test vectors")
struct FinancialRiskPolicyTestVectorTests {
    @Test("catalog contains V1 through V16")
    func vectorCompleteness() throws {
        try FinancialRiskPolicyValidation.validateTestVectors()
        #expect(FinancialRiskPolicyTestVectors.catalog.count == 16)
    }

    @Test("V7 expects no DTI warning at 19.9 boundary")
    func v7NoDTI() {
        let vector = FinancialRiskPolicyTestVectors.catalog.first { $0.id == "V7" }
        #expect(vector?.expectedOverallLevel == .safe)
        #expect(vector?.expectedSignalReasonCodes.isEmpty == true)
    }

    @Test("V8 expects DTI warning at 20 boundary")
    func v8DTIWarning() {
        let vector = FinancialRiskPolicyTestVectors.catalog.first { $0.id == "V8" }
        #expect(vector?.expectedSignalReasonCodes == [.highDebtPaymentToIncome])
    }

    @Test("V9 DTI 55 remains warning not risk")
    func v9NoDTIRisk() {
        let vector = FinancialRiskPolicyTestVectors.catalog.first { $0.id == "V9" }
        #expect(vector?.expectedOverallLevel == .warning)
        #expect(vector?.expectedSignalReasonCodes == [.highDebtPaymentToIncome])
    }

    @Test("V14 missing debt requires debtDataMissing unknown")
    func v14MissingDebt() {
        let vector = FinancialRiskPolicyTestVectors.catalog.first { $0.id == "V14" }
        #expect(vector?.expectedCompletenessDebt == .missing)
        #expect(vector?.expectedRequiredUnknowns == [.debtDataMissing])
        #expect(vector?.expectedSignalReasonCodes.isEmpty == true)
    }

    @Test("V4 retains only negative projected balance signal")
    func v4DedupExpectation() {
        let vector = FinancialRiskPolicyTestVectors.catalog.first { $0.id == "V4" }
        #expect(vector?.expectedSignalReasonCodes == [.negativeProjectedBalance])
    }

    @Test("evaluation mapping notes present for key cases")
    func evalMappingNotes() {
        let mapped = FinancialRiskPolicyTestVectors.catalog.filter { $0.evalCaseMapping != nil }
        #expect(mapped.count >= 8)
    }
}

@Suite("Financial risk policy semantics")
struct FinancialRiskPolicySemanticsTests {
    @Test("v1 does not require healthyCashBuffer signal for safe")
    func noHealthySignalRequired() {
        let healthyRuleExists = FinancialRiskPolicySpecification.allRules.contains {
            $0.reasonCode == .healthyCashBuffer
        }
        #expect(!healthyRuleExists)
    }

    @Test("missing debt completeness rule emits no risk signals")
    func missingDebtNoRiskSignals() {
        let rule = FinancialRiskPolicySpecification.missingDebtCompleteness
        #expect(rule.outputLevel == .safe)
        #expect(rule.sourceFactKeys.isEmpty)
    }

    @Test("month-end fallback domain facts noted as sufficient")
    func monthEndFallbackDomainFacts() {
        let rule = FinancialRiskPolicySpecification.cf3MonthEndFallbackBelowSafe
        #expect(rule.requiredInputs.contains("estimatedMonthEndBalance"))
        #expect(rule.preconditions.contains(where: { $0.contains("minimumBalance unavailable") }))
    }
}
