import Foundation

/// Single source of truth for active financial risk policy version.
public enum FinancialRiskPolicyVersion {
    public static let v1 = "v1"

    /// Version used by `FinancialRiskPolicyEngine` v1 (P0-4.5.3+).
    public static let current = v1
}
