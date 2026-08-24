import Foundation
import YoushuFoundation

/// Algorithm identifier for confirmed-import source fingerprints (ADR-036).
public enum ImportSourceFingerprintAlgorithm: String, Sendable, Equatable, Codable {
    case sha256V1 = "sha256-v1"
}

/// Full-file SHA-256 identity of one imported input byte sequence.
///
/// Not interchangeable with `MediaArtifact.id`, `sourceImageId`, or recognition audit ids.
public struct ImportSourceFingerprint: Equatable, Hashable, Sendable, Codable {
    public static let algorithm = ImportSourceFingerprintAlgorithm.sha256V1
    public static let digestHexLength = 64

    public var algorithm: ImportSourceFingerprintAlgorithm
    public var digestHex: String

    /// Computes SHA-256 over the entire `data` buffer.
    public static func sha256(of data: Data) -> ImportSourceFingerprint {
        ImportSourceFingerprint(
            algorithm: .sha256V1,
            digestHex: DeterministicSHA256.digestHex(data)
        )
    }

    public init(algorithm: ImportSourceFingerprintAlgorithm, digestHex: String) {
        self.algorithm = algorithm
        self.digestHex = Self.normalizeDigestHex(digestHex)
    }

    /// Validates persisted or external digest representation.
    public static func validated(
        algorithm: ImportSourceFingerprintAlgorithm = .sha256V1,
        digestHex: String
    ) throws -> ImportSourceFingerprint {
        let normalized = normalizeDigestHex(digestHex)
        guard algorithm == .sha256V1 else {
            throw DomainError.validationFailed("Unsupported import source fingerprint algorithm")
        }
        guard normalized.count == digestHexLength,
              normalized.allSatisfy(\.isHexDigit) else {
            throw DomainError.validationFailed("Invalid import source fingerprint digest")
        }
        return ImportSourceFingerprint(algorithm: algorithm, digestHex: normalized)
    }

    public var digestBytes: [UInt8] {
        stride(from: 0, to: digestHex.count, by: 2).map { offset in
            let start = digestHex.index(digestHex.startIndex, offsetBy: offset)
            let end = digestHex.index(after: start)
            return UInt8(digestHex[start ... end], radix: 16) ?? 0
        }
    }

    private static func normalizeDigestHex(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension ImportSourceFingerprint {
    static func normalizedDigestHex(_ value: String) -> String {
        normalizeDigestHex(value)
    }
}

/// Canonicalization contract for operation/batch fingerprints (ADR-036).
///
/// Distinct from `ImportSourceFingerprintAlgorithm`, which identifies the digest primitive only.
public enum ImportOperationFingerprintCanonicalizationScheme: String, Sendable, Equatable, Codable {
    case canonicalV1Sha256 = "canonical-v1-sha256"
}

/// Batch / operation identity derived from capability + source fingerprint multiset (ADR-036).
public struct ImportOperationFingerprint: Equatable, Hashable, Sendable, Codable {
    public static let canonicalVersion: UInt8 = 1
    public static let defaultCanonicalizationScheme = ImportOperationFingerprintCanonicalizationScheme.canonicalV1Sha256

    public var algorithm: ImportSourceFingerprintAlgorithm
    public var canonicalizationScheme: ImportOperationFingerprintCanonicalizationScheme
    public var digestHex: String

    public init(
        algorithm: ImportSourceFingerprintAlgorithm,
        canonicalizationScheme: ImportOperationFingerprintCanonicalizationScheme,
        digestHex: String
    ) {
        self.algorithm = algorithm
        self.canonicalizationScheme = canonicalizationScheme
        self.digestHex = ImportSourceFingerprint.normalizedDigestHex(digestHex)
    }

    public static func validated(
        algorithm: ImportSourceFingerprintAlgorithm = .sha256V1,
        canonicalizationScheme: ImportOperationFingerprintCanonicalizationScheme = defaultCanonicalizationScheme,
        digestHex: String
    ) throws -> ImportOperationFingerprint {
        _ = try ImportSourceFingerprint.validated(algorithm: algorithm, digestHex: digestHex)
        guard canonicalizationScheme == .canonicalV1Sha256 else {
            throw DomainError.validationFailed("Unsupported import operation fingerprint canonicalization scheme")
        }
        return ImportOperationFingerprint(
            algorithm: algorithm,
            canonicalizationScheme: canonicalizationScheme,
            digestHex: digestHex
        )
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case canonicalizationScheme
        case digestHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let algorithm = try container.decode(ImportSourceFingerprintAlgorithm.self, forKey: .algorithm)
        let scheme = try container.decodeIfPresent(
            ImportOperationFingerprintCanonicalizationScheme.self,
            forKey: .canonicalizationScheme
        ) ?? Self.defaultCanonicalizationScheme
        let digestHex = try container.decode(String.self, forKey: .digestHex)
        self = try Self.validated(algorithm: algorithm, canonicalizationScheme: scheme, digestHex: digestHex)
    }
}
