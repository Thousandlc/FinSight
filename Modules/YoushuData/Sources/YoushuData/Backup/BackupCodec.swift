import Foundation
import YoushuDomain
import YoushuFoundation

public struct BackupCodecConfiguration: Sendable, Equatable {
    public var kdfIterations: Int

    public init(kdfIterations: Int = BackupFormatV1Policy.kdfIterations) {
        self.kdfIterations = kdfIterations
    }

    public static let production = BackupCodecConfiguration()
}

/// Encodes and decodes encrypted portable backup files.
///
/// Cryptography is delegated entirely to `BackupCrypto` (swift-crypto). This type owns
/// format framing and untrusted-input validation only.
public enum BackupCodec {
    public static func encode(
        payload: BackupPayloadV1,
        passphrase: String,
        configuration: BackupCodecConfiguration = .production
    ) throws -> Data {
        try BackupPassphrasePolicy.validate(passphrase)
        try validateIterations(configuration.kdfIterations)

        let payloadData = try encodePayload(payload)
        let salt = BackupCrypto.randomBytes(count: BackupFormatV1Policy.saltByteCount)
        let nonce = BackupCrypto.randomBytes(count: BackupFormatV1Policy.nonceByteCount)
        let key = try deriveKey(
            passphrase: passphrase,
            salt: salt,
            iterations: configuration.kdfIterations
        )

        let sealed: (ciphertext: Data, tag: Data)
        do {
            sealed = try BackupCrypto.seal(
                plaintext: payloadData,
                key: key,
                nonce: nonce,
                additionalAuthenticatedData: BackupFormatV1Policy.additionalAuthenticatedData(
                    kdfIterations: configuration.kdfIterations
                )
            )
        } catch {
            throw BackupError.malformedEnvelope("encryption failed")
        }

        let envelope = FinSightBackupEnvelopeV1(
            kdfIterations: configuration.kdfIterations,
            salt: salt,
            nonce: nonce,
            ciphertext: sealed.ciphertext,
            authenticationTag: sealed.tag
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func decode(
        backupData: Data,
        passphrase: String
    ) throws -> BackupPayloadV1 {
        try BackupPassphrasePolicy.validate(passphrase)
        try validateFileSize(backupData)
        let envelope = try decodeEnvelope(from: backupData)
        try validateEnvelope(envelope)

        let key = try deriveKey(
            passphrase: passphrase,
            salt: envelope.salt,
            iterations: envelope.kdfIterations
        )

        let plaintext: Data
        do {
            plaintext = try BackupCrypto.open(
                ciphertext: envelope.ciphertext,
                tag: envelope.authenticationTag,
                key: key,
                nonce: envelope.nonce,
                additionalAuthenticatedData: BackupFormatV1Policy.additionalAuthenticatedData(
                    kdfIterations: envelope.kdfIterations
                )
            )
        } catch {
            throw BackupError.authenticationFailure
        }

        return try decodePayload(plaintext)
    }

    private static func deriveKey(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) throws -> BackupEncryptionKey {
        do {
            return try BackupCrypto.deriveKey(
                passphrase: passphrase,
                salt: salt,
                iterations: iterations
            )
        } catch {
            throw BackupError.invalidCryptoParameter(field: "kdf")
        }
    }

    private static func validateFileSize(_ backupData: Data) throws {
        guard !backupData.isEmpty else {
            throw BackupError.malformedEnvelope("empty backup data")
        }
        guard backupData.count <= BackupFormatV1Policy.maximumBackupFileByteCount else {
            throw BackupError.backupTooLarge(
                byteCount: backupData.count,
                limit: BackupFormatV1Policy.maximumBackupFileByteCount
            )
        }
    }

    private static func decodeEnvelope(from backupData: Data) throws -> FinSightBackupEnvelopeV1 {
        do {
            return try JSONDecoder().decode(FinSightBackupEnvelopeV1.self, from: backupData)
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.malformedEnvelope("invalid envelope json")
        }
    }

    /// Validates every attacker-controlled parameter before any expensive or unsafe work.
    /// Iteration count is checked here so a hostile file cannot request unapproved PBKDF2 work.
    private static func validateEnvelope(_ envelope: FinSightBackupEnvelopeV1) throws {
        guard envelope.formatVersion == BackupFormatV1Policy.formatVersion else {
            throw BackupError.unsupportedFormat(
                found: envelope.formatVersion,
                supported: BackupFormatV1Policy.formatVersion
            )
        }
        guard envelope.kdfAlgorithm == BackupFormatV1Policy.kdfAlgorithm else {
            throw BackupError.unsupportedAlgorithm(field: "kdfAlgorithm")
        }
        guard envelope.cipherAlgorithm == BackupFormatV1Policy.cipherAlgorithm else {
            throw BackupError.unsupportedAlgorithm(field: "cipherAlgorithm")
        }
        guard envelope.keyLengthBits == BackupFormatV1Policy.keyLengthBits else {
            throw BackupError.invalidCryptoParameter(field: "keyLengthBits")
        }
        try validateIterations(envelope.kdfIterations)
        guard envelope.salt.count == BackupFormatV1Policy.saltByteCount else {
            throw BackupError.invalidCryptoParameter(field: "salt")
        }
        guard envelope.nonce.count == BackupFormatV1Policy.nonceByteCount else {
            throw BackupError.invalidCryptoParameter(field: "nonce")
        }
        guard envelope.authenticationTag.count == BackupFormatV1Policy.authenticationTagByteCount else {
            throw BackupError.invalidCryptoParameter(field: "authenticationTag")
        }
        guard envelope.ciphertext.count <= BackupFormatV1Policy.maximumCiphertextByteCount else {
            throw BackupError.backupTooLarge(
                byteCount: envelope.ciphertext.count,
                limit: BackupFormatV1Policy.maximumCiphertextByteCount
            )
        }
    }

    private static func validateIterations(_ iterations: Int) throws {
        guard iterations == BackupFormatV1Policy.kdfIterations else {
            throw BackupError.invalidCryptoParameter(field: "kdfIterations")
        }
    }

    private static func encodePayload(_ payload: BackupPayloadV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private static func decodePayload(_ data: Data) throws -> BackupPayloadV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let payload = try decoder.decode(BackupPayloadV1.self, from: data)
            guard payload.metadata.formatVersion == BackupPayloadV1.formatVersion else {
                throw BackupError.unsupportedFormat(
                    found: payload.metadata.formatVersion,
                    supported: BackupPayloadV1.formatVersion
                )
            }
            return payload
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.payloadDecodeFailure("invalid backup payload")
        }
    }
}
