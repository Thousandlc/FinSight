import Foundation
import YoushuDomain
import YoushuFoundation

/// Exact cryptographic parameters accepted by Backup Format v1.
///
/// A `.finsightbackup` file is untrusted external input, so v1 accepts only these fixed
/// values rather than honouring caller-supplied algorithm or sizing choices.
public enum BackupFormatV1Policy {
    public static let formatVersion = 1
    public static let kdfAlgorithm = "PBKDF2-HMAC-SHA256"
    public static let cipherAlgorithm = "AES-256-GCM"
    public static let keyLengthBits = 256

    public static let saltByteCount = 16
    public static let nonceByteCount = BackupCrypto.nonceByteCount
    public static let authenticationTagByteCount = BackupCrypto.tagByteCount

    /// Fixed PBKDF2-HMAC-SHA256 work factor for Backup Format v1 (600,000 iterations per OWASP).
    public static let kdfIterations = 600_000

    public static let maximumBackupFileByteCount = 64 * 1024 * 1024
    public static let maximumCiphertextByteCount = 48 * 1024 * 1024

    /// Deterministic representation of the security-relevant header, bound into the AEAD as
    /// additional authenticated data so `kdfIterations` cannot be silently downgraded.
    /// Every other field is a fixed literal validated before decryption, so the string stays
    /// stable for the lifetime of format v1.
    public static func additionalAuthenticatedData(kdfIterations: Int) -> Data {
        let header = [
            "finsight.backup.v\(formatVersion)",
            "kdf=\(kdfAlgorithm)",
            "cipher=\(cipherAlgorithm)",
            "keyBits=\(keyLengthBits)",
            "iterations=\(kdfIterations)",
        ].joined(separator: "\n")
        return Data(header.utf8)
    }
}

/// Encrypted portable backup envelope. Carries no plaintext financial data.
public struct FinSightBackupEnvelopeV1: Codable, Sendable, Equatable {
    public static let formatVersion = BackupFormatV1Policy.formatVersion
    public static let suggestedFileExtension = "finsightbackup"

    public static let kdfAlgorithm = BackupFormatV1Policy.kdfAlgorithm
    public static let cipherAlgorithm = BackupFormatV1Policy.cipherAlgorithm

    public var formatVersion: Int
    public var kdfAlgorithm: String
    public var kdfIterations: Int
    public var keyLengthBits: Int
    public var cipherAlgorithm: String
    public var salt: Data
    public var nonce: Data
    public var ciphertext: Data
    public var authenticationTag: Data

    public init(
        formatVersion: Int = FinSightBackupEnvelopeV1.formatVersion,
        kdfAlgorithm: String = FinSightBackupEnvelopeV1.kdfAlgorithm,
        kdfIterations: Int,
        keyLengthBits: Int = BackupFormatV1Policy.keyLengthBits,
        cipherAlgorithm: String = FinSightBackupEnvelopeV1.cipherAlgorithm,
        salt: Data,
        nonce: Data,
        ciphertext: Data,
        authenticationTag: Data
    ) {
        self.formatVersion = formatVersion
        self.kdfAlgorithm = kdfAlgorithm
        self.kdfIterations = kdfIterations
        self.keyLengthBits = keyLengthBits
        self.cipherAlgorithm = cipherAlgorithm
        self.salt = salt
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.authenticationTag = authenticationTag
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case kdfAlgorithm
        case kdfIterations
        case keyLengthBits
        case cipherAlgorithm
        case salt
        case nonce
        case ciphertext
        case authenticationTag
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        kdfAlgorithm = try container.decode(String.self, forKey: .kdfAlgorithm)
        kdfIterations = try container.decode(Int.self, forKey: .kdfIterations)
        keyLengthBits = try container.decode(Int.self, forKey: .keyLengthBits)
        cipherAlgorithm = try container.decode(String.self, forKey: .cipherAlgorithm)
        salt = try container.decodeStableData(forKey: .salt)
        nonce = try container.decodeStableData(forKey: .nonce)
        ciphertext = try container.decodeStableData(forKey: .ciphertext)
        authenticationTag = try container.decodeStableData(forKey: .authenticationTag)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(kdfAlgorithm, forKey: .kdfAlgorithm)
        try container.encode(kdfIterations, forKey: .kdfIterations)
        try container.encode(keyLengthBits, forKey: .keyLengthBits)
        try container.encode(cipherAlgorithm, forKey: .cipherAlgorithm)
        try container.encodeStableData(salt, forKey: .salt)
        try container.encodeStableData(nonce, forKey: .nonce)
        try container.encodeStableData(ciphertext, forKey: .ciphertext)
        try container.encodeStableData(authenticationTag, forKey: .authenticationTag)
    }
}

private enum StableDataCoding {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func decode(_ value: String) throws -> Data {
        guard let data = Data(base64Encoded: value) else {
            throw BackupError.malformedEnvelope("invalid base64 field")
        }
        return data
    }
}

private extension KeyedDecodingContainer {
    func decodeStableData(forKey key: Key) throws -> Data {
        let encoded = try decode(String.self, forKey: key)
        return try StableDataCoding.decode(encoded)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeStableData(_ data: Data, forKey key: Key) throws {
        try encode(StableDataCoding.encode(data), forKey: key)
    }
}
