import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Financial risk policy engine V1-V16 vectors")
struct FinancialRiskPolicyEngineVectorTests {
    @Test("all catalog vectors evaluate against expected outcomes", arguments: FinancialRiskPolicyTestVectors.catalog)
    func vectorExpectations(vector: FinancialRiskPolicyTestVector) throws {
        guard let input = FinancialRiskPolicyVectorInputs.input(for: vector.id) else {
            Issue.record("Missing input fixture for \(vector.id)")
            return
        }
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        let reasonCodes = assessment.signals.map(\.reasonCode)

        #expect(assessment.overallLevel == vector.expectedOverallLevel, "vector \(vector.id) overallLevel")
        #expect(reasonCodes == vector.expectedSignalReasonCodes, "vector \(vector.id) reasonCodes")
        #expect(assessment.dataCompleteness.debt == vector.expectedCompletenessDebt, "vector \(vector.id) debt completeness")

        for required in vector.expectedRequiredUnknowns {
            #expect(
                assessment.dataCompleteness.requiredUnknownReasonCodes.contains(required),
                "vector \(vector.id) missing required unknown \(required.rawValue)"
            )
        }

        for signal in assessment.signals {
            #expect(!vector.expectedSuppressedReasonCodes.contains(signal.reasonCode))
        }
    }

    @Test("vector signal levels match policy specification")
    func vectorSignalLevels() {
        let v3 = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V3")!)
        #expect(v3.signals.first?.level == .risk)

        let v2 = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V2")!)
        #expect(v2.signals.first?.level == .warning)
    }

    @Test("vector recommended actions are deterministic")
    func vectorActions() {
        let v2 = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V2")!)
        #expect(v2.signals.first?.recommendedActionDestinations == [.cashFlow])

        let v10 = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V10")!)
        #expect(v10.signals.first?.recommendedActionDestinations == [.cashFlow, .transactions])
    }
}

@Suite("Financial risk policy engine additional cases")
struct FinancialRiskPolicyEngineAdditionalTests {
    private let fixedDate = FinancialRiskPolicyVectorInputs.fixedEvaluatedAt

    private func money(_ amount: Decimal) -> Money {
        Money(amount: amount, currencyCode: "CNY")
    }

    private func knownCompleteness() -> FinancialDataCompleteness {
        FinancialDataCompleteness(
            debt: .known,
            cashFlowProjection: .known,
            income: .known,
            expense: .known
        )
    }

    @Test("minimum negative with safeBalance nil still risks")
    func negativeWithoutSafeBalance() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .known(money(-100)),
            safeBalance: .missing(),
            estimatedMonthEndBalance: .known(money(500)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtDataState: .knownDebt,
            dataCompleteness: knownCompleteness(),
            evaluatedAt: fixedDate
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.overallLevel == .risk)
        #expect(assessment.signals.map(\.reasonCode) == [.negativeProjectedBalance])
    }

    @Test("minimum positive with safeBalance nil emits no below-safe warning")
    func positiveWithoutSafeBalanceNoWarning() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .known(money(500)),
            safeBalance: .missing(),
            estimatedMonthEndBalance: .known(money(800)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtDataState: .knownDebt,
            dataCompleteness: knownCompleteness(),
            evaluatedAt: fixedDate
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.overallLevel == .safe)
        #expect(assessment.signals.isEmpty)
    }

    @Test("minimum known prevents month-end fallback")
    func minimumKnownSkipsMonthEndFallback() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .known(money(5000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(-100)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtDataState: .knownDebt,
            dataCompleteness: knownCompleteness(),
            evaluatedAt: fixedDate
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.signals.isEmpty)
        #expect(assessment.overallLevel == .safe)
    }

    @Test("month-end below safe fallback when minimum unavailable")
    func monthEndBelowSafeFallbackWhenMinimumUnavailable() {
        let assessment = FinancialRiskPolicyProvenanceEmissionFixtures.monthEndBelowSafeFallbackAssessment()
        #expect(assessment.overallLevel == .warning)
        #expect(assessment.signals.map(\.reasonCode) == [.monthEndBelowSafeBalance])
        let signal = assessment.signals[0]
        #expect(signal.level == .warning)
        #expect(signal.sourceFactKeys == ["estimatedMonthEndBalance", "safeBalance"])
        #expect(signal.recommendedActionDestinations == [.cashFlow])
    }

    @Test("month-end below safe fallback suppressed when minimum negative")
    func monthEndBelowSafeFallbackSuppressedByNegativeProjectedBalance() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .missing(),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(-50)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtDataState: .knownNoDebt,
            dataCompleteness: knownCompleteness(),
            evaluatedAt: fixedDate
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.overallLevel == .risk)
        #expect(assessment.signals.map(\.reasonCode) == [.negativeProjectedBalance])
    }

    @Test("month-end negative fallback when minimum unavailable")
    func monthEndNegativeFallback() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .missing(),
            safeBalance: .missing(),
            estimatedMonthEndBalance: .known(money(-50)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtDataState: .knownDebt,
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .partial,
                income: .known,
                expense: .known
            ),
            evaluatedAt: fixedDate
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.overallLevel == .risk)
        #expect(assessment.signals.map(\.reasonCode) == [.negativeProjectedBalance])
        #expect(assessment.signals.first?.sourceFactKeys == ["estimatedMonthEndBalance"])
    }

    @Test("knownNoDebt with DTI 50 emits no debt signal")
    func knownNoDebtBlocksDTI() {
        let assessment = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V12")!)
        #expect(assessment.signals.isEmpty)
        #expect(assessment.overallLevel == .safe)
    }

    @Test("missing debt with DTI 50 emits no debt signal")
    func missingDebtBlocksDTI() {
        var input = FinancialRiskPolicyVectorInputs.input(for: "V14")!
        input.debtPaymentToIncomePercent = .known(50)
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.signals.isEmpty)
    }

    @Test("partial debt with DTI 20 allows warning")
    func partialDebtAllowsDTI() {
        let assessment = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V13")!)
        #expect(assessment.signals.map(\.reasonCode) == [.highDebtPaymentToIncome])
    }

    @Test("debt pressure high dedups DTI warning")
    func debtHighDedupsDTI() {
        let assessment = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V5")!)
        #expect(assessment.signals.map(\.reasonCode) == [.highDebtPressureScore])
    }

    @Test("debt pressure critical dedups DTI and high debt pressure")
    func debtCriticalDedups() {
        var input = FinancialRiskPolicyVectorInputs.input(for: "V6")!
        input.debtPaymentToIncomePercent = .known(55)
        input.debtPressureLevel = .critical
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.signals.map(\.reasonCode) == [.criticalDebtPressure])
    }

    @Test("zero income and zero expense emits no IE signal")
    func zeroIncomeZeroExpense() {
        let assessment = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V11")!)
        #expect(assessment.signals.isEmpty)
    }

    @Test("safe cash with zero-income warning stays warning overall")
    func zeroIncomeWithBuffer() {
        let assessment = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V10")!)
        #expect(assessment.overallLevel == .warning)
    }

    @Test("critical debt and negative cash retain both risk signals")
    func criticalDebtAndNegativeCash() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .known(money(-200)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(-200)),
            monthlyIncome: .known(money(10000)),
            monthlyExpense: .known(money(5000)),
            debtPressureLevel: .critical,
            debtDataState: .knownDebt,
            dataCompleteness: knownCompleteness(),
            evaluatedAt: fixedDate
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.overallLevel == .risk)
        #expect(Set(assessment.signals.map(\.reasonCode)) == Set([
            .negativeProjectedBalance,
            .criticalDebtPressure,
        ]))
    }

    @Test("dedup is order independent")
    func dedupOrderIndependent() {
        let a = FinancialRiskSignal(
            kind: .debt,
            level: .warning,
            reasonCode: .highDebtPaymentToIncome,
            sourceFactKeys: ["debtPaymentToIncomePercent"]
        )
        let b = FinancialRiskSignal(
            kind: .debt,
            level: .warning,
            reasonCode: .highDebtPressureScore,
            sourceFactKeys: ["debtPressureLevel"]
        )
        let forward = FinancialRiskPolicyDedup.apply([a, b])
        let reverse = FinancialRiskPolicyDedup.apply([b, a])
        #expect(forward.map(\.reasonCode) == reverse.map(\.reasonCode))
        #expect(forward.map(\.reasonCode) == [.highDebtPressureScore])
    }

    @Test("output signal order is deterministic")
    func deterministicOrdering() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .known(money(-200)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(-200)),
            monthlyIncome: .known(money(0)),
            monthlyExpense: .known(money(1000)),
            debtPressureLevel: .critical,
            debtDataState: .knownDebt,
            dataCompleteness: knownCompleteness(),
            evaluatedAt: fixedDate
        )
        let first = FinancialRiskPolicyEngine.evaluate(input)
        let second = FinancialRiskPolicyEngine.evaluate(input)
        #expect(first == second)
        #expect(first.signals.map(\.reasonCode) == second.signals.map(\.reasonCode))
    }

    @Test("same input repeated yields identical assessment")
    func pureFunctionRepeatability() {
        let input = FinancialRiskPolicyVectorInputs.input(for: "V8")!
        #expect(FinancialRiskPolicyEngine.evaluate(input) == FinancialRiskPolicyEngine.evaluate(input))
    }

    @Test("policy version comes from single source")
    func policyVersionSource() {
        let assessment = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V1")!)
        #expect(assessment.policyVersion == FinancialRiskPolicyVersion.current)
    }

    @Test("evaluatedAt comes from input")
    func evaluatedAtFromInput() {
        let assessment = FinancialRiskPolicyEngine.evaluate(FinancialRiskPolicyVectorInputs.input(for: "V1")!)
        #expect(assessment.evaluatedAt == fixedDate)
    }

    @Test("knownNoDebt allows non-pressure debt kind signal after guard")
    func knownNoDebtGuardRegression() {
        let signal = FinancialRiskSignal(
            kind: .debt,
            level: .safe,
            reasonCode: .budgetNotApplicable,
            sourceFactKeys: ["primaryPressure"]
        )
        let filtered = FinancialRiskKnownZeroGuard.filterSignals([signal], debtState: .knownNoDebt)
        #expect(filtered.count == 1)
    }

    @Test("cash flow projection missing emits no CF signals")
    func cashFlowMissingNoSignals() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .missing(),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .missing(),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtDataState: .knownDebt,
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .missing,
                income: .known,
                expense: .known
            ),
            evaluatedAt: fixedDate
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.signals.isEmpty)
        #expect(assessment.dataCompleteness.requiredUnknownReasonCodes.contains(.cashFlowProjectionMissing))
    }
}

@Suite("Financial risk policy engine domain boundary")
struct FinancialRiskPolicyEngineBoundaryTests {
    private static let engineSourceFiles = [
        "FinancialRiskPolicyEngine.swift",
        "FinancialRiskPolicyInput.swift",
        "FinancialRiskPolicyDedup.swift",
        "FinancialRiskPolicyVectorInputs.swift",
    ]

    private static let forbiddenTokens = [
        "AssistantWarningSeverity",
        "AssistantActionDestination",
        "AssistantStructuredAnswer",
        "Repository",
        "Date()",
    ]

    @Test("engine sources do not reference assistant or repository layers")
    func engineSourcesExcludeForbiddenDependencies() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let domainRoot = url.appendingPathComponent("Sources/YoushuDomain")

        for fileName in Self.engineSourceFiles {
            let services = domainRoot.appendingPathComponent("Services/\(fileName)")
            let policy = domainRoot.appendingPathComponent("Policy/\(fileName)")
            let path = FileManager.default.fileExists(atPath: services.path) ? services : policy
            let source = try String(contentsOf: path, encoding: .utf8)
            for token in Self.forbiddenTokens {
                #expect(!source.contains(token), "\(fileName) must not reference \(token)")
            }
        }
    }
}
