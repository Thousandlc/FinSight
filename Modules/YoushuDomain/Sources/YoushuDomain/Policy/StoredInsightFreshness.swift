import Foundation
import YoushuFoundation

/// Domain-owned freshness fingerprint algorithm version.
/// Not JSON Store schema, Gateway response schema, or Bailian model schema.
public enum StoredInsightFreshnessSchemaVersion {
    public static let v1 = "v1"
    public static let current = v1
}

/// Canonical deterministic inputs for monthly `.summary` freshness identity.
public struct MonthlySummaryFreshnessInput: Equatable, Sendable {
    public var factEntries: [String: String]
    public var amountEntries: [String: String]
    public var policyVersion: String
    public var overallLevel: FinancialRiskLevel
    public var debtDataState: DebtDataState
    public var completenessEntries: [String: String]
    public var unknownReasonCodes: [FinancialRiskReasonCode]
    public var signalEntries: [String]

    public init(
        factEntries: [String: String],
        amountEntries: [String: String],
        policyVersion: String,
        overallLevel: FinancialRiskLevel,
        debtDataState: DebtDataState,
        completenessEntries: [String: String],
        unknownReasonCodes: [FinancialRiskReasonCode],
        signalEntries: [String]
    ) {
        self.factEntries = factEntries
        self.amountEntries = amountEntries
        self.policyVersion = policyVersion
        self.overallLevel = overallLevel
        self.debtDataState = debtDataState
        self.completenessEntries = completenessEntries
        self.unknownReasonCodes = unknownReasonCodes
        self.signalEntries = signalEntries
    }
}

/// Opaque persisted freshness provenance for monthly `.summary` cache (ADR-032 Scheme A).
public struct FinancialInsightFreshnessMetadata: Equatable, Sendable, Codable, Hashable {
    public var schemaVersion: String
    public var policyVersion: String
    public var digest: String

    public init(schemaVersion: String, policyVersion: String, digest: String) {
        self.schemaVersion = schemaVersion
        self.policyVersion = policyVersion
        self.digest = digest
    }

    /// Stable comparison identity for later read-side freshness checks.
    public var identity: String {
        "\(schemaVersion)|\(policyVersion)|\(digest)"
    }
}

/// In-memory freshness identity for monthly summary cache.
/// Canonical fact token remains transient; only `metadata` is storage-safe.
public struct StoredInsightFreshnessFingerprint: Equatable, Sendable {
    public var metadata: FinancialInsightFreshnessMetadata

    /// Transient canonical representation. Must not be persisted.
    internal var canonicalToken: String

    public var schemaVersion: String { metadata.schemaVersion }
    public var policyVersion: String { metadata.policyVersion }

    public init(metadata: FinancialInsightFreshnessMetadata, canonicalToken: String) {
        self.metadata = metadata
        self.canonicalToken = canonicalToken
    }
}

public enum MonthlySummaryFreshnessBuilder {
    public static func makeInput(
        facts: MonthlySummaryFacts,
        assessment: FinancialRiskAssessment
    ) -> MonthlySummaryFreshnessInput {
        MonthlySummaryFreshnessInput(
            factEntries: canonicalFactEntries(from: facts),
            amountEntries: canonicalAmountEntries(from: facts),
            policyVersion: assessment.policyVersion,
            overallLevel: assessment.overallLevel,
            debtDataState: assessment.debtDataState,
            completenessEntries: canonicalCompletenessEntries(from: assessment.dataCompleteness),
            unknownReasonCodes: assessment.dataCompleteness.requiredUnknownReasonCodes.sorted {
                $0.rawValue < $1.rawValue
            },
            signalEntries: canonicalSignalEntries(from: assessment.signals)
        )
    }

    public static func fingerprint(
        from facts: MonthlySummaryFacts,
        assessment: FinancialRiskAssessment
    ) -> StoredInsightFreshnessFingerprint {
        fingerprint(input: makeInput(facts: facts, assessment: assessment))
    }

    public static func fingerprint(
        input: MonthlySummaryFreshnessInput
    ) -> StoredInsightFreshnessFingerprint {
        let token = canonicalToken(from: input)
        return StoredInsightFreshnessFingerprint(
            metadata: persistenceMetadata(canonicalToken: token, policyVersion: input.policyVersion),
            canonicalToken: token
        )
    }

    /// Storage-safe provenance for validated monthly-summary persistence.
    public static func persistenceMetadata(
        from facts: MonthlySummaryFacts,
        assessment: FinancialRiskAssessment
    ) -> FinancialInsightFreshnessMetadata {
        persistenceMetadata(input: makeInput(facts: facts, assessment: assessment))
    }

    public static func persistenceMetadata(
        input: MonthlySummaryFreshnessInput
    ) -> FinancialInsightFreshnessMetadata {
        persistenceMetadata(
            canonicalToken: canonicalToken(from: input),
            policyVersion: input.policyVersion
        )
    }

    private static func persistenceMetadata(
        canonicalToken: String,
        policyVersion: String
    ) -> FinancialInsightFreshnessMetadata {
        FinancialInsightFreshnessMetadata(
            schemaVersion: StoredInsightFreshnessSchemaVersion.current,
            policyVersion: policyVersion,
            digest: StoredInsightFreshnessDigest.hex(canonicalToken: canonicalToken)
        )
    }
}

enum StoredInsightFreshnessDigest {
    static func hex(canonicalToken: String) -> String {
        DeterministicSHA256.digestHex(canonicalToken)
    }
}

/// Canonical monthly-summary facts + assessment used for freshness comparison and generation.
public struct MonthlySummaryFreshnessContext: Equatable, Sendable {
    public var facts: MonthlySummaryFacts
    public var assessment: FinancialRiskAssessment

    public init(facts: MonthlySummaryFacts, assessment: FinancialRiskAssessment) {
        self.facts = facts
        self.assessment = assessment
    }
}

/// Read-side freshness comparison for persisted Home `.summary` cache (ADR-032 Scheme A).
public enum StoredInsightFreshnessEvaluator {
    public static func isCurrent(
        stored: FinancialInsightFreshnessMetadata?,
        current: FinancialInsightFreshnessMetadata
    ) -> Bool {
        guard let stored else { return false }
        guard stored.schemaVersion == StoredInsightFreshnessSchemaVersion.current else { return false }
        return stored == current
    }
}

extension MonthlySummaryFreshnessBuilder {
    public static func buildContext(
        source: FinancialContextBuilder.Source,
        context: FinancialContext,
        debtInventoryEstablishment: DebtInventoryEstablishmentState,
        debtImportInProgress: Bool,
        safeBalance: Money
    ) -> MonthlySummaryFreshnessContext {
        let enrichedBase = MonthlySummaryFactsEnricher.enrich(
            FinancialContextBuilder.monthlySummaryFacts(from: context),
            context: context,
            safeBalance: safeBalance
        )
        let assembly = FinancialRiskAssessmentService.assemblyContext(
            source: source,
            context: context,
            enrichedFacts: enrichedBase,
            safeBalance: safeBalance,
            debtInventoryLoadSucceeded: true,
            debtInventoryEstablishment: debtInventoryEstablishment,
            debtImportInProgress: debtImportInProgress,
            evaluatedAt: source.asOf
        )
        let assessment = FinancialRiskAssessmentService.assess(assembly)
        let facts = MonthlySummaryFactsEnricher.enrichDebtPressureProvenance(
            enrichedBase,
            debtPressureLevel: assembly.debtPressureLevel,
            debtDataState: assessment.debtDataState
        )
        return MonthlySummaryFreshnessContext(facts: facts, assessment: assessment)
    }
}

// MARK: - Canonical encoding

private enum StoredInsightFreshnessCanonicalEncoding {
    static func normalizedAmount(_ value: Decimal) -> String {
        var v = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &v, 2, .plain)
        return "\(rounded)"
    }

    static func normalizedPercent(_ value: Decimal) -> String {
        normalizedAmount(value)
    }

    static func moneyToken(_ money: Money) -> String {
        "\(money.currencyCode):\(normalizedAmount(money.amount))"
    }

    static func sortedDictionaryLines(prefix: String, entries: [String: String]) -> [String] {
        entries.keys.sorted().map { key in
            "\(prefix).\(key)=\(entries[key] ?? "")"
        }
    }
}

private func canonicalFactEntries(from facts: MonthlySummaryFacts) -> [String: String] {
    var entries: [String: String] = [
        "primaryPressure": facts.primaryPressure,
    ]
    if let pct = facts.debtPaymentToIncomePercent {
        entries["debtPaymentToIncomePercent"] = StoredInsightFreshnessCanonicalEncoding.normalizedPercent(pct)
    }
    if let explanation = facts.cashFlowRiskExplanation {
        entries["cashFlowRiskExplanation"] = explanation
    }
    if let level = facts.debtPressureLevel {
        entries["debtPressureLevel"] = level.rawValue
    }
    return entries
}

private func canonicalAmountEntries(from facts: MonthlySummaryFacts) -> [String: String] {
    var entries: [String: String] = [
        "availableCash": StoredInsightFreshnessCanonicalEncoding.moneyToken(facts.availableCash),
        "monthlyIncome": StoredInsightFreshnessCanonicalEncoding.moneyToken(facts.monthlyIncome),
        "monthlyExpense": StoredInsightFreshnessCanonicalEncoding.moneyToken(facts.monthlyExpense),
        "monthlyDebtPayment": StoredInsightFreshnessCanonicalEncoding.moneyToken(facts.monthlyDebtPayment),
        "estimatedMonthEndBalance": StoredInsightFreshnessCanonicalEncoding.moneyToken(facts.estimatedMonthEndBalance),
    ]
    if let safeBalance = facts.safeBalance {
        entries["safeBalance"] = StoredInsightFreshnessCanonicalEncoding.moneyToken(safeBalance)
    }
    if let minimumBalance = facts.minimumBalance {
        entries["minimumBalance"] = StoredInsightFreshnessCanonicalEncoding.moneyToken(minimumBalance)
    }
    return entries
}

private func canonicalCompletenessEntries(from completeness: FinancialDataCompleteness) -> [String: String] {
    [
        "debt": completeness.debt.rawValue,
        "cashFlowProjection": completeness.cashFlowProjection.rawValue,
        "income": completeness.income.rawValue,
        "expense": completeness.expense.rawValue,
    ]
}

private func canonicalSignalEntries(from signals: [FinancialRiskSignal]) -> [String] {
    signals.map { signal in
        let sources = signal.sourceFactKeys.sorted().joined(separator: ",")
        let actions = signal.recommendedActionDestinations
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return "\(signal.kind.rawValue)|\(signal.level.rawValue)|\(signal.reasonCode.rawValue)|\(sources)|\(actions)"
    }
    .sorted()
}

private func canonicalToken(from input: MonthlySummaryFreshnessInput) -> String {
    var lines: [String] = []
    lines.append(contentsOf: StoredInsightFreshnessCanonicalEncoding.sortedDictionaryLines(
        prefix: "amount",
        entries: input.amountEntries
    ))
    lines.append(contentsOf: StoredInsightFreshnessCanonicalEncoding.sortedDictionaryLines(
        prefix: "fact",
        entries: input.factEntries
    ))
    lines.append("assessment.debtDataState=\(input.debtDataState.rawValue)")
    lines.append("assessment.overallLevel=\(input.overallLevel.rawValue)")
    lines.append(contentsOf: StoredInsightFreshnessCanonicalEncoding.sortedDictionaryLines(
        prefix: "completeness",
        entries: input.completenessEntries
    ))
    let unknowns = input.unknownReasonCodes.map(\.rawValue).joined(separator: ",")
    lines.append("assessment.unknownReasonCodes=\(unknowns)")
    for (index, signal) in input.signalEntries.enumerated() {
        lines.append("assessment.signal[\(index)]=\(signal)")
    }
    return lines.joined(separator: "\n")
}
