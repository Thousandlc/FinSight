import Foundation

/// v1 product threshold registry. Risk Policy consumes values — does not redefine safeBalance numeric default.
public enum FinancialRiskPolicyThresholdRegistry {
    public enum Owner: String, Sendable, Equatable {
        case cashFlowInputConfiguration
        case productV1Confirmed
        case existingDomainEngine
        case notDefinedInV1
    }

    public struct Entry: Sendable, Equatable {
        public var name: String
        public var owner: Owner
        public var numericValueDescription: String?
        public var statusNote: String

        public init(name: String, owner: Owner, numericValueDescription: String? = nil, statusNote: String) {
            self.name = name
            self.owner = owner
            self.numericValueDescription = numericValueDescription
            self.statusNote = statusNote
        }
    }

    /// FinSight v1 product threshold — not a regulatory/industry standard.
    public static let dtiWarningThresholdPercent: Decimal = 20

    public static let entries: [Entry] = [
        Entry(
            name: "safeBalance",
            owner: .cashFlowInputConfiguration,
            numericValueDescription: nil,
            statusNote: "Consumed as deterministic input; Risk Policy does not define numeric value. Configuration debt tracked separately."
        ),
        Entry(
            name: "dtiWarning",
            owner: .productV1Confirmed,
            numericValueDescription: ">= 20%",
            statusNote: "Product v1 confirmed. Aligns with FinancialContextBuilder.primaryPressure and Mock provider."
        ),
        Entry(
            name: "dtiRisk",
            owner: .notDefinedInV1,
            numericValueDescription: nil,
            statusNote: "Not defined in v1. DTI alone must not produce risk."
        ),
        Entry(
            name: "debtPressureHigh",
            owner: .existingDomainEngine,
            numericValueDescription: "DebtPressureLevel.high",
            statusNote: "Maps to warning via DebtCenterCalculator.debtPressureLevel."
        ),
        Entry(
            name: "debtPressureCritical",
            owner: .existingDomainEngine,
            numericValueDescription: "DebtPressureLevel.critical",
            statusNote: "Maps to risk via DebtCenterCalculator.debtPressureLevel."
        ),
        Entry(
            name: "negativeProjectedBalance",
            owner: .productV1Confirmed,
            numericValueDescription: "< 0",
            statusNote: "minimumBalance or month-end fallback estimatedMonthEndBalance."
        ),
    ]

    public static func isDTIWarningEligible(percent: Decimal, monthlyIncomeKnown: Bool) -> Bool {
        monthlyIncomeKnown && percent >= dtiWarningThresholdPercent
    }

    public static func isDTIWarningEligible(percent: Decimal) -> Bool {
        percent >= dtiWarningThresholdPercent
    }
}
