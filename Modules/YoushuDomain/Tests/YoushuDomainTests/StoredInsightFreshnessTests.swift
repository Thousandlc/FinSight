import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Stored insight freshness (ADR-032 Scheme A)")
struct StoredInsightFreshnessTests {
    private func baselineFacts(sourceLabels: [String] = ["Account"]) -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: 25,
            primaryPressure: "债务还款",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            sourceLabels: sourceLabels
        )
    }

    @Test("identical facts and policy version produce identical fingerprint")
    func identicalInputsMatch() {
        let facts = baselineFacts()
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let first = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: assessment)
        let second = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: assessment)
        #expect(first == second)
        #expect(first.metadata.identity == second.metadata.identity)
    }

    @Test("source label order does not affect freshness identity")
    func sourceLabelOrderIgnored() {
        let ordered = baselineFacts(sourceLabels: ["Account", "Debt", "CashFlow"])
        let reversed = baselineFacts(sourceLabels: ["CashFlow", "Debt", "Account"])
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let first = MonthlySummaryFreshnessBuilder.fingerprint(from: ordered, assessment: assessment)
        let second = MonthlySummaryFreshnessBuilder.fingerprint(from: reversed, assessment: assessment)
        #expect(first == second)
    }

    @Test("material monthly income change produces different fingerprint")
    func materialFactChangeDiffers() {
        let base = baselineFacts()
        var changed = baselineFacts()
        changed.monthlyIncome = Money(amount: 6_000, currencyCode: "CNY")
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let baseFingerprint = MonthlySummaryFreshnessBuilder.fingerprint(from: base, assessment: assessment)
        let changedFingerprint = MonthlySummaryFreshnessBuilder.fingerprint(from: changed, assessment: assessment)
        #expect(baseFingerprint != changedFingerprint)
    }

    @Test("policy version change produces different fingerprint")
    func policyVersionChangeDiffers() {
        let facts = baselineFacts()
        let current = FinancialRiskTestFixtures.warningKnownDebtDTI()
        var legacy = current
        legacy.policyVersion = "v0-legacy-test"
        let currentFingerprint = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: current)
        let legacyFingerprint = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: legacy)
        #expect(currentFingerprint != legacyFingerprint)
        #expect(currentFingerprint.policyVersion == FinancialRiskPolicyVersion.current)
        #expect(legacyFingerprint.policyVersion == "v0-legacy-test")
    }

    @Test("evaluatedAt does not affect freshness identity")
    func evaluatedAtIgnored() {
        let facts = baselineFacts()
        var earlier = FinancialRiskTestFixtures.warningKnownDebtDTI()
        var later = earlier
        earlier.evaluatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        later.evaluatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let first = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: earlier)
        let second = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: later)
        #expect(first == second)
    }

    @Test("signal source key order does not affect freshness identity")
    func signalSourceOrderIgnored() {
        let facts = baselineFacts()
        var assessmentA = FinancialRiskTestFixtures.warningKnownDebtDTI()
        assessmentA.signals = [
            FinancialRiskSignal(
                kind: .cashFlow,
                level: .warning,
                reasonCode: .cashFlowBelowSafeBalance,
                sourceFactKeys: ["minimumBalance", "safeBalance"],
                recommendedActionDestinations: [.cashFlow, .accounts]
            ),
        ]
        var assessmentB = assessmentA
        assessmentB.signals = [
            FinancialRiskSignal(
                kind: .cashFlow,
                level: .warning,
                reasonCode: .cashFlowBelowSafeBalance,
                sourceFactKeys: ["safeBalance", "minimumBalance"],
                recommendedActionDestinations: [.accounts, .cashFlow]
            ),
        ]
        let first = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: assessmentA)
        let second = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: assessmentB)
        #expect(first == second)
    }

    @Test("builder is deterministic across repeated calls")
    func repeatedBuilderDeterministic() {
        let facts = FinancialRiskTestFixtures.factsForNegativeProjectedBalance()
        let assessment = FinancialRiskTestFixtures.riskNegativeProjectedBalance()
        let fingerprints = (0..<5).map { _ in
            MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: assessment).metadata.digest
        }
        #expect(Set(fingerprints).count == 1)
    }

    @Test("canonical input round-trips through fingerprint builder")
    func inputRoundTripStable() {
        let facts = FinancialRiskTestFixtures.factsForDebtPressureHigh()
        let assessment = FinancialRiskTestFixtures.riskDebtPressureCritical()
        let input = MonthlySummaryFreshnessBuilder.makeInput(facts: facts, assessment: assessment)
        let direct = MonthlySummaryFreshnessBuilder.fingerprint(from: facts, assessment: assessment)
        let fromInput = MonthlySummaryFreshnessBuilder.fingerprint(input: input)
        #expect(direct == fromInput)
        #expect(direct.schemaVersion == StoredInsightFreshnessSchemaVersion.current)
    }

    @Test("same canonical input produces same storage-safe digest repeatedly")
    func persistenceDigestDeterministic() {
        let facts = baselineFacts()
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let digests = (0..<5).map { _ in
            MonthlySummaryFreshnessBuilder.persistenceMetadata(from: facts, assessment: assessment).digest
        }
        #expect(Set(digests).count == 1)
        #expect(digests[0].count == 64)
    }

    @Test("material fact change produces different storage digest")
    func persistenceDigestChangesOnMaterialFact() {
        let base = baselineFacts()
        var changed = baselineFacts()
        changed.monthlyIncome = Money(amount: 6_000, currencyCode: "CNY")
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let baseDigest = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: base, assessment: assessment).digest
        let changedDigest = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: changed, assessment: assessment).digest
        #expect(baseDigest != changedDigest)
    }

    @Test("policy version change produces different stored freshness identity")
    func persistenceIdentityChangesOnPolicyVersion() {
        let facts = baselineFacts()
        let current = FinancialRiskTestFixtures.warningKnownDebtDTI()
        var legacy = current
        legacy.policyVersion = "v0-legacy-test"
        let currentIdentity = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: facts, assessment: current).identity
        let legacyIdentity = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: facts, assessment: legacy).identity
        #expect(currentIdentity != legacyIdentity)
    }

    @Test("persisted digest does not contain raw canonical financial facts")
    func persistenceDigestIsOpaque() {
        let facts = baselineFacts()
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let metadata = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: facts, assessment: assessment)

        #expect(!metadata.digest.contains("amount.monthlyIncome"))
        #expect(!metadata.digest.contains("CNY:5000"))
        #expect(!metadata.digest.contains("assessment.overallLevel"))
        #expect(!metadata.identity.contains("amount.monthlyIncome"))
    }

    @Test("freshness evaluator accepts matching metadata")
    func evaluatorMatchingMetadataIsCurrent() {
        let metadata = MonthlySummaryFreshnessBuilder.persistenceMetadata(
            from: baselineFacts(),
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI()
        )
        #expect(StoredInsightFreshnessEvaluator.isCurrent(stored: metadata, current: metadata))
    }

    @Test("freshness evaluator rejects digest mismatch")
    func evaluatorDigestMismatchNotCurrent() {
        let facts = baselineFacts()
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let current = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: facts, assessment: assessment)
        var stale = current
        stale.digest = String(repeating: "0", count: 64)
        #expect(!StoredInsightFreshnessEvaluator.isCurrent(stored: stale, current: current))
    }

    @Test("freshness evaluator rejects policy version mismatch")
    func evaluatorPolicyMismatchNotCurrent() {
        let facts = baselineFacts()
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let current = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: facts, assessment: assessment)
        var stale = current
        stale.policyVersion = "v0-legacy-test"
        #expect(!StoredInsightFreshnessEvaluator.isCurrent(stored: stale, current: current))
    }

    @Test("freshness evaluator rejects nil stored metadata")
    func evaluatorNilStoredNotCurrent() {
        let current = MonthlySummaryFreshnessBuilder.persistenceMetadata(
            from: baselineFacts(),
            assessment: FinancialRiskTestFixtures.warningKnownDebtDTI()
        )
        #expect(!StoredInsightFreshnessEvaluator.isCurrent(stored: nil, current: current))
    }

    @Test("freshness evaluator rejects unsupported schema version")
    func evaluatorUnsupportedSchemaNotCurrent() {
        let facts = baselineFacts()
        let assessment = FinancialRiskTestFixtures.warningKnownDebtDTI()
        let current = MonthlySummaryFreshnessBuilder.persistenceMetadata(from: facts, assessment: assessment)
        var unsupported = current
        unsupported.schemaVersion = "v0-unsupported"
        #expect(!StoredInsightFreshnessEvaluator.isCurrent(stored: unsupported, current: current))
    }
}
