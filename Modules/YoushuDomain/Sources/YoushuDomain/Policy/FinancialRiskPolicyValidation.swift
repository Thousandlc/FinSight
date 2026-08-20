import Foundation

/// Validates v1 policy specification integrity (catalog-only — no rule evaluation).
public enum FinancialRiskPolicyValidation {
    public enum ValidationError: Error, Equatable, Sendable {
        case duplicateRuleID(String)
        case duplicateReasonCodeMapping(ruleIDs: [String], reasonCode: FinancialRiskReasonCode)
        case missingTestVector(String)
        case unexpectedTestVectorCount(expected: Int, actual: Int)
        case policyVersionMismatch(spec: String, versionConstant: String)
    }

    public static func validateSpecification() throws {
        try validateUniqueRuleIDs(FinancialRiskPolicySpecification.allRules)
        try validateSignalReasonCodeUniqueness(FinancialRiskPolicySpecification.signalEmittingRules)
        try validatePolicyVersion()
        try validateTestVectors()
    }

    public static func validateUniqueRuleIDs(_ rules: [FinancialRiskPolicyRule]) throws {
        var seen = Set<String>()
        for rule in rules {
            if seen.contains(rule.id) {
                throw ValidationError.duplicateRuleID(rule.id)
            }
            seen.insert(rule.id)
        }
    }

    public static func validateSignalReasonCodeUniqueness(_ rules: [FinancialRiskPolicyRule]) throws {
        var byReason: [FinancialRiskReasonCode: [String]] = [:]
        for rule in rules {
            byReason[rule.reasonCode, default: []].append(rule.id)
        }
        for (reason, ids) in byReason where ids.count > 1 {
            let uniqueIDs = Array(Set(ids)).sorted()
            if uniqueIDs.count > 1 &&
                !allowsSharedReasonCode(reason, ruleIDs: uniqueIDs) {
                throw ValidationError.duplicateReasonCodeMapping(ruleIDs: uniqueIDs, reasonCode: reason)
            }
        }
    }

    public static func validatePolicyVersion() throws {
        guard FinancialRiskPolicySpecification.policyVersion == FinancialRiskPolicyVersion.current else {
            throw ValidationError.policyVersionMismatch(
                spec: FinancialRiskPolicySpecification.policyVersion,
                versionConstant: FinancialRiskPolicyVersion.current
            )
        }
    }

    public static func validateTestVectors() throws {
        let ids = Set(FinancialRiskPolicyTestVectors.catalog.map(\.id))
        for required in FinancialRiskPolicyTestVectors.requiredVectorIDs where !ids.contains(required) {
            throw ValidationError.missingTestVector(required)
        }
        let expected = FinancialRiskPolicyTestVectors.requiredVectorIDs.count
        if FinancialRiskPolicyTestVectors.catalog.count != expected {
            throw ValidationError.unexpectedTestVectorCount(
                expected: expected,
                actual: FinancialRiskPolicyTestVectors.catalog.count
            )
        }
    }

    /// CF-3a and CF-1 share negativeProjectedBalance by design; CF-3b uses monthEndBelowSafeBalance.
    private static func allowsSharedReasonCode(
        _ reason: FinancialRiskReasonCode,
        ruleIDs: [String]
    ) -> Bool {
        switch reason {
        case .negativeProjectedBalance:
            return Set(ruleIDs).isSubset(of: ["CF-1", "CF-3a"])
        default:
            return false
        }
    }
}
