import Foundation

/// Transient ADR-036 import identity for one transaction-screenshot flow.
///
/// Not persisted as a financial fact; carried through duplicate check → recognition → confirmation.
public struct TransactionScreenshotImportIdentity: Sendable, Equatable, Hashable {
    public let sourceFingerprint: ImportSourceFingerprint
    public let operationFingerprint: ImportOperationFingerprint

    public init(
        sourceFingerprint: ImportSourceFingerprint,
        operationFingerprint: ImportOperationFingerprint
    ) {
        self.sourceFingerprint = sourceFingerprint
        self.operationFingerprint = operationFingerprint
    }

    /// Derives full-file SHA-256 source identity and canonical operation fingerprint locally.
    public static func from(imageData: Data) -> TransactionScreenshotImportIdentity {
        let sourceFingerprint = ImportSourceFingerprint.sha256(of: imageData)
        let operationFingerprint = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .transactionScreenshot,
            sourceFingerprints: [sourceFingerprint]
        )
        return TransactionScreenshotImportIdentity(
            sourceFingerprint: sourceFingerprint,
            operationFingerprint: operationFingerprint
        )
    }
}
