import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Financial risk level aggregation")
struct FinancialRiskAggregationTests {
    private func signal(
        kind: FinancialRiskSignalKind = .cashFlow,
        level: FinancialRiskLevel,
        reason: FinancialRiskReasonCode = .cashFlowBelowSafeBalance,
        keys: [String] = ["minimumBalance"]
    ) -> FinancialRiskSignal {
        FinancialRiskSignal(kind: kind, level: level, reasonCode: reason, sourceFactKeys: keys)
    }
    @Test("empty signals aggregate to safe")
    func emptySignals() {
        #expect(FinancialRiskAggregation.aggregateOverallLevel(from: []) == .safe)
    }

    @Test("safe plus warning yields warning")
    func safePlusWarning() {
        let signals = [
            signal(level: .safe, reason: .healthyCashBuffer, keys: ["availableCash"]),
            signal(kind: .debt, level: .warning, reason: .highDebtPaymentToIncome, keys: ["debtPaymentToIncomePercent"]),
        ]
        #expect(FinancialRiskAggregation.aggregateOverallLevel(from: signals) == .warning)
    }

    @Test("warning plus risk yields risk")
    func warningPlusRisk() {
        let signals = [
            signal(kind: .debt, level: .warning, reason: .highDebtPaymentToIncome),
            signal(level: .risk, reason: .cashFlowBelowSafeBalance),
        ]
        #expect(FinancialRiskAggregation.aggregateOverallLevel(from: signals) == .risk)
    }

    @Test("healthy safe signal does not cancel warning")
    func healthyDoesNotCancelWarning() {
        let signals = [
            signal(level: .safe, reason: .healthyCashBuffer, keys: ["minimumBalance", "safeBalance"]),
            signal(kind: .incomeExpense, level: .warning, reason: .zeroIncomeWithExpenses, keys: ["monthlyIncome", "monthlyExpense"]),
        ]
        #expect(FinancialRiskAggregation.aggregateOverallLevel(from: signals) == .warning)
    }

    @Test("healthy safe signal does not cancel risk")
    func healthyDoesNotCancelRisk() {
        let signals = [
            signal(level: .safe, reason: .healthyCashBuffer),
            signal(level: .risk, reason: .negativeProjectedBalance),
        ]
        #expect(FinancialRiskAggregation.aggregateOverallLevel(from: signals) == .risk)
    }

    @Test("data completeness does not participate in aggregation")
    func completenessExcludedFromAggregation() {
        let completeness = FinancialDataCompleteness(
            debt: .missing,
            cashFlowProjection: .known,
            income: .known,
            expense: .known,
            requiredUnknownReasonCodes: [.debtDataMissing]
        )
        let assessment = FinancialRiskAssessmentAssembly.assemble(
            signals: [],
            dataCompleteness: completeness,
            debtState: .missing,
            evaluatedAt: fixedDate
        )
        #expect(assessment.overallLevel == .safe)
        #expect(assessment.dataCompleteness.debt == .missing)
    }

    @Test("knownNoDebt suppresses debt pressure signals during aggregation")
    func knownNoDebtSuppressesDebtPressure() {
        let debtPressure = FinancialRiskSignal(
            kind: .debt,
            level: .warning,
            reasonCode: .highDebtPaymentToIncome,
            sourceFactKeys: ["debtPaymentToIncomePercent"]
        )
        let cashFlowRisk = signal(level: .risk, reason: .cashFlowBelowSafeBalance)
        let level = FinancialRiskAggregation.aggregateOverallLevel(
            signals: [debtPressure, cashFlowRisk],
            debtState: .knownNoDebt
        )
        #expect(level == .risk)
        #expect(FinancialRiskKnownZeroGuard.filterSignals([debtPressure], debtState: .knownNoDebt).isEmpty)
    }

    @Test("evaluatedAt is injected by caller")
    func evaluatedAtDeterministic() {
        let assessment = FinancialRiskAssessmentAssembly.assemble(
            signals: [],
            dataCompleteness: sampleCompleteness(),
            debtState: .knownNoDebt,
            evaluatedAt: fixedDate
        )
        #expect(assessment.evaluatedAt == fixedDate)
    }

    private var fixedDate: Date {
        ISO8601DateFormatter().date(from: "2026-08-16T06:00:00Z")!
    }

    private func sampleCompleteness() -> FinancialDataCompleteness {
        FinancialDataCompleteness(
            debt: .known,
            cashFlowProjection: .known,
            income: .known,
            expense: .known
        )
    }
}

@Suite("Debt data state builder")
struct DebtDataStateBuilderTests {
    private let userId = UUID()

    @Test("complete inventory with no open debt and zero outstanding is knownNoDebt")
    func knownNoDebtFromInventory() {
        let state = DebtDataStateBuilder.build(
            DebtDataStateBuilder.Input(
                debts: [],
                totalOutstanding: .zeroCNY,
                inventoryCoverage: .complete,
                monthlyDebtPayment: .zeroCNY
            )
        )
        #expect(state == .knownNoDebt)
    }

    @Test("monthlyDebtPayment zero alone does not imply knownNoDebt when inventory unavailable")
    func zeroPaymentAloneNotKnownNoDebt() {
        let state = DebtDataStateBuilder.build(
            DebtDataStateBuilder.Input(
                debts: [],
                totalOutstanding: .zeroCNY,
                inventoryCoverage: .unavailable,
                monthlyDebtPayment: Money(amount: 0, currencyCode: "CNY")
            )
        )
        #expect(state == .missing)
    }

    @Test("monthlyDebtPayment zero with unavailable inventory stays missing not knownNoDebt")
    func zeroPaymentWithMissingInventory() {
        let unavailable = DebtDataStateBuilder.build(
            DebtDataStateBuilder.Input(
                debts: [],
                totalOutstanding: .zeroCNY,
                inventoryCoverage: .unavailable,
                monthlyDebtPayment: .zeroCNY
            )
        )
        #expect(unavailable == .missing)
    }

    @Test("repayments without debt inventory is partial not knownNoDebt")
    func repaymentWithoutInventoryIsPartial() {
        let state = DebtDataStateBuilder.build(
            DebtDataStateBuilder.Input(
                debts: [],
                totalOutstanding: .zeroCNY,
                inventoryCoverage: .complete,
                monthlyDebtPayment: Money(amount: 800, currencyCode: "CNY")
            )
        )
        #expect(state == .partial)
    }

    @Test("open debt with outstanding classifies as knownDebt")
    func knownDebt() {
        let debts = [
            Debt(
                userId: userId,
                outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
                installmentAmount: Money(amount: 500, currencyCode: "CNY"),
                paymentFrequency: .monthly,
                status: .active,
                profileCompleteness: 0.9
            ),
        ]
        let state = DebtDataStateBuilder.build(
            debts: debts,
            inventoryCoverage: .complete,
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY")
        )
        #expect(state == .knownDebt)
    }

    @Test("low profile completeness on open debt yields partial")
    func partialProfile() {
        let debts = [
            Debt(
                userId: userId,
                outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
                status: .active,
                profileCompleteness: 0.2
            ),
        ]
        let state = DebtDataStateBuilder.build(
            debts: debts,
            inventoryCoverage: .complete
        )
        #expect(state == .partial)
    }

    @Test("unavailable inventory yields missing")
    func missingInventory() {
        let state = DebtDataStateBuilder.build(
            debts: [],
            inventoryCoverage: .unavailable
        )
        #expect(state == .missing)
    }

    @Test("explicit partial inventory coverage yields partial")
    func partialCoverage() {
        let state = DebtDataStateBuilder.build(
            debts: [],
            inventoryCoverage: .partial
        )
        #expect(state == .partial)
    }

    @Test("known zero debt state is not missing")
    func knownZeroNotMissing() {
        let state = DebtDataStateBuilder.build(
            DebtDataStateBuilder.Input(
                debts: [],
                totalOutstanding: .zeroCNY,
                inventoryCoverage: .complete,
                monthlyDebtPayment: .zeroCNY
            )
        )
        #expect(state == .knownNoDebt)
        #expect(state != DebtDataState.missing)
    }
}

@Suite("Financial risk known zero guard")
struct FinancialRiskKnownZeroGuardTests {
    @Test("knownNoDebt allows neutral cash flow signals")
    func allowsCashFlowSignals() {
        let signal = FinancialRiskSignal(
            kind: .cashFlow,
            level: .risk,
            reasonCode: .cashFlowBelowSafeBalance,
            sourceFactKeys: ["minimumBalance", "safeBalance"]
        )
        #expect(FinancialRiskKnownZeroGuard.allowsSignal(signal, debtState: .knownNoDebt))
    }

    @Test("knownNoDebt blocks debt pressure signals by reason code")
    func blocksDebtPressure() {
        let signal = FinancialRiskSignal(
            kind: .debt,
            level: .warning,
            reasonCode: .highDebtPaymentToIncome,
            sourceFactKeys: ["debtPaymentToIncomePercent"]
        )
        #expect(!FinancialRiskKnownZeroGuard.allowsSignal(signal, debtState: .knownNoDebt))
    }

    @Test("knownNoDebt allows non-pressure debt kind signal")
    func allowsNonPressureDebtKind() {
        let signal = FinancialRiskSignal(
            kind: .debt,
            level: .safe,
            reasonCode: .budgetNotApplicable,
            sourceFactKeys: ["primaryPressure"]
        )
        #expect(FinancialRiskKnownZeroGuard.allowsSignal(signal, debtState: .knownNoDebt))
    }

    @Test("knownNoDebt does not forbid monthlyDebtPayment fact key at guard layer")
    func monthlyDebtPaymentFactAllowed() {
        // Guard operates on signals/claims, not fact key registration.
        let neutralKeyFactKeys = ["monthlyDebtPayment", "monthlyIncome"]
        #expect(neutralKeyFactKeys.contains("monthlyDebtPayment"))
        let blocked = FinancialRiskSignal(
            kind: .debt,
            level: .warning,
            reasonCode: .repaymentConcern,
            sourceFactKeys: neutralKeyFactKeys
        )
        #expect(!FinancialRiskKnownZeroGuard.allowsSignal(blocked, debtState: .knownNoDebt))
    }
}

@Suite("Financial risk assistant mapper boundary")
struct FinancialRiskAssistantMapperTests {
    @Test("maps domain risk level to assistant warning severity")
    func mapsLevels() {
        #expect(FinancialRiskAssistantMapper.mapLevel(.safe) == .safe)
        #expect(FinancialRiskAssistantMapper.mapLevel(.warning) == .warning)
        #expect(FinancialRiskAssistantMapper.mapLevel(.risk) == .risk)
    }

    @Test("maps domain action destinations to assistant destinations")
    func mapsDestinations() {
        #expect(FinancialRiskAssistantMapper.mapActionDestination(.cashFlow) == .cashFlow)
        #expect(FinancialRiskAssistantMapper.mapActionDestination(.debt) == .debt)
    }
}

@Suite("Financial risk domain boundary")
struct FinancialRiskDomainBoundaryTests {
    private static let coreSourceFiles = [
        "FinancialRiskModels.swift",
        "DebtDataStateBuilder.swift",
        "FinancialRiskKnownZeroGuard.swift",
        "FinancialRiskAggregation.swift",
    ]

    private static let forbiddenAssistantTokens = [
        "AssistantWarningSeverity",
        "AssistantActionDestination",
        "AssistantStructuredAnswer",
        "AssistantAnswerDraft",
    ]

    @Test("core risk domain sources do not reference assistant output types")
    func coreSourcesExcludeAssistantContracts() throws {
        let domainRoot = try domainSourcesRoot()
        for fileName in Self.coreSourceFiles {
            let path = domainRoot
                .appendingPathComponent("ReadModels/\(fileName)", isDirectory: false)
            let altPath = domainRoot
                .appendingPathComponent("Services/\(fileName)", isDirectory: false)
            let url = FileManager.default.fileExists(atPath: path.path) ? path : altPath
            let source = try String(contentsOf: url, encoding: .utf8)
            for token in Self.forbiddenAssistantTokens {
                #expect(
                    !source.contains(token),
                    "Core risk file \(fileName) must not depend on \(token)"
                )
            }
        }
    }

    @Test("FinancialRiskLevel is domain-owned and distinct from AssistantWarningSeverity")
    func domainLevelDistinctFromAssistant() {
        let domain: FinancialRiskLevel = .warning
        let assistant: AssistantWarningSeverity = .warning
        #expect(domain.rawValue == assistant.rawValue)
        #expect(type(of: domain) != type(of: assistant))
    }

    @Test("FinancialRiskSignal uses core-owned action destinations")
    func coreOwnedActionDestinations() {
        let signal = FinancialRiskSignal(
            kind: .debt,
            level: .warning,
            reasonCode: .highDebtPaymentToIncome,
            sourceFactKeys: ["debtPaymentToIncomePercent"],
            recommendedActionDestinations: [.debt, .cashFlow]
        )
        #expect(signal.recommendedActionDestinations == [.debt, .cashFlow])
    }

    @Test("FinancialRiskSignalKind excludes dataCompleteness")
    func signalKindExcludesCompleteness() {
        #expect(!FinancialRiskSignalKind.allCases.contains(where: { $0.rawValue == "dataCompleteness" }))
        #expect(FinancialRiskSignalKind.allCases.count == 3)
    }

    @Test("FieldAvailability known represents known zero semantics")
    func knownIncludesKnownZero() {
        let completeness = FinancialDataCompleteness(
            debt: .known,
            cashFlowProjection: .known,
            income: .known,
            expense: .known
        )
        #expect(completeness.debt == .known)
    }

    private func domainSourcesRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent("Sources/YoushuDomain", isDirectory: true)
    }
}
