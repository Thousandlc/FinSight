import Foundation

/// Transient ADR-036 import identity for one debt-scan batch flow.
///
/// Preserves document multiplicity; canonicalization order-insensitivity applies only to operation fingerprint.
public struct DebtScanImportIdentity: Sendable, Equatable, Hashable {
    public let sourceFingerprints: [ImportSourceFingerprint]
    public let operationFingerprint: ImportOperationFingerprint

    public init(
        sourceFingerprints: [ImportSourceFingerprint],
        operationFingerprint: ImportOperationFingerprint
    ) {
        self.sourceFingerprints = sourceFingerprints
        self.operationFingerprint = operationFingerprint
    }

    /// Derives per-document full-file SHA-256 identities and canonical batch operation fingerprint.
    public static func from(documents: [BillDocument]) -> DebtScanImportIdentity {
        let sourceFingerprints = documents.map { ImportSourceFingerprint.sha256(of: $0.data) }
        let operationFingerprint = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: sourceFingerprints
        )
        return DebtScanImportIdentity(
            sourceFingerprints: sourceFingerprints,
            operationFingerprint: operationFingerprint
        )
    }
}
