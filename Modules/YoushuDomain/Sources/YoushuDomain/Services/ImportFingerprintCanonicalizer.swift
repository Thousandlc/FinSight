import Foundation
import YoushuFoundation

/// Deterministic batch/operation fingerprint canonicalization (ADR-036 v1).
public enum ImportFingerprintCanonicalizer {
    private static let magic = Data("FIPC".utf8)

    /// Canonical v1 byte layout:
    /// ```text
    /// magic "FIPC" (4)
    /// version UInt8 (1)
    /// capability UTF-8 with UInt16 BE length prefix
    /// sourceCount UInt32 BE
    /// repeated for each source fingerprint sorted by digestHex ascending:
    ///   digestRaw 32 bytes (SHA-256)
    /// ```
    /// `operationFingerprint = SHA-256(canonicalBytes)` as lowercase hex.
    public static func operationFingerprint(
        capability: ConfirmedImportCapability,
        sourceFingerprints: [ImportSourceFingerprint]
    ) -> ImportOperationFingerprint {
        let digestHex = DeterministicSHA256.digestHex(
            canonicalBytes(capability: capability, sourceFingerprints: sourceFingerprints)
        )
        return ImportOperationFingerprint(
            algorithm: .sha256V1,
            canonicalizationScheme: .canonicalV1Sha256,
            digestHex: digestHex
        )
    }

    public static func canonicalBytes(
        capability: ConfirmedImportCapability,
        sourceFingerprints: [ImportSourceFingerprint]
    ) -> Data {
        precondition(!sourceFingerprints.isEmpty, "canonicalBytes requires non-empty source fingerprints")
        var bytes = Data()
        bytes.append(magic)
        bytes.append(ImportOperationFingerprint.canonicalVersion)
        appendLengthPrefixedUTF8(capability.rawValue, to: &bytes)
        appendUInt32(UInt32(sourceFingerprints.count), to: &bytes)

        let sorted = sourceFingerprints.sorted { $0.digestHex < $1.digestHex }
        for fingerprint in sorted {
            bytes.append(contentsOf: fingerprint.digestBytes)
        }
        return bytes
    }

    private static func appendLengthPrefixedUTF8(_ string: String, to data: inout Data) {
        let payload = Data(string.utf8)
        precondition(payload.count <= Int(UInt16.max))
        var length = UInt16(payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(payload)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
}
