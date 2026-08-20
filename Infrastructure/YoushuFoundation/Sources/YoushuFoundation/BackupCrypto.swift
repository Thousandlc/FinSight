import Crypto
import Foundation
import _CryptoExtras

/// Cryptographic failures for portable backup encryption.
/// Cases never carry passphrase material, derived keys, or plaintext content.
public enum BackupCryptoError: Error, Equatable, Sendable {
    case invalidSaltLength
    case invalidNonceLength
    case invalidTagLength
    case invalidIterationCount
    case keyDerivationFailed
    case authenticationFailed
    case sealFailed
}

/// Opaque backup encryption key.
///
/// Wrapping the library key type keeps callers off a direct crypto-library dependency and
/// keeps key bytes out of `Data` values that could be logged or serialized.
/// `SymmetricKey` is an immutable value type but is not annotated `Sendable` by swift-crypto,
/// so the conformance is asserted here rather than inferred.
public struct BackupEncryptionKey: @unchecked Sendable {
    fileprivate let symmetricKey: SymmetricKey

    fileprivate init(_ symmetricKey: SymmetricKey) {
        self.symmetricKey = symmetricKey
    }
}

/// Backup encryption primitives.
///
/// Primitives are provided by swift-crypto. Crypto common APIs may defer to CryptoKit on Apple;
/// CryptoExtras / `_CryptoExtras` (including PBKDF2) uses the swift-crypto BoringSSL-backed
/// implementation. This type intentionally contains no hand-written cipher, hash, MAC, or KDF
/// arithmetic.
public enum BackupCrypto {
    public static let keyByteCount = 32
    public static let nonceByteCount = 12
    public static let tagByteCount = 16

    /// Cryptographically secure random bytes sourced from the crypto library.
    public static func randomBytes(count: Int) -> Data {
        precondition(count > 0)
        return SymmetricKey(size: SymmetricKeySize(bitCount: count * 8))
            .withUnsafeBytes { Data($0) }
    }

    /// PBKDF2-HMAC-SHA256 passphrase-based key derivation.
    public static func deriveKey(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) throws -> BackupEncryptionKey {
        guard iterations > 0 else { throw BackupCryptoError.invalidIterationCount }
        guard !salt.isEmpty else { throw BackupCryptoError.invalidSaltLength }

        do {
            let key = try KDF.Insecure.PBKDF2.deriveKey(
                from: Data(passphrase.utf8),
                salt: salt,
                using: .sha256,
                outputByteCount: keyByteCount,
                rounds: iterations
            )
            return BackupEncryptionKey(key)
        } catch {
            throw BackupCryptoError.keyDerivationFailed
        }
    }

    /// AES-256-GCM authenticated encryption.
    public static func seal(
        plaintext: Data,
        key: BackupEncryptionKey,
        nonce: Data,
        additionalAuthenticatedData: Data
    ) throws -> (ciphertext: Data, tag: Data) {
        guard nonce.count == nonceByteCount else { throw BackupCryptoError.invalidNonceLength }

        do {
            let sealedBox = try AES.GCM.seal(
                plaintext,
                using: key.symmetricKey,
                nonce: AES.GCM.Nonce(data: nonce),
                authenticating: additionalAuthenticatedData
            )
            return (sealedBox.ciphertext, sealedBox.tag)
        } catch {
            throw BackupCryptoError.sealFailed
        }
    }

    /// AES-256-GCM authenticated decryption. Fails closed on any tag/AAD mismatch.
    public static func open(
        ciphertext: Data,
        tag: Data,
        key: BackupEncryptionKey,
        nonce: Data,
        additionalAuthenticatedData: Data
    ) throws -> Data {
        guard nonce.count == nonceByteCount else { throw BackupCryptoError.invalidNonceLength }
        guard tag.count == tagByteCount else { throw BackupCryptoError.invalidTagLength }

        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(
                sealedBox,
                using: key.symmetricKey,
                authenticating: additionalAuthenticatedData
            )
        } catch {
            throw BackupCryptoError.authenticationFailed
        }
    }
}

#if DEBUG
/// Verification-only surface used to run published known-answer vectors against the same
/// primitives production uses. Excluded from release builds: standard vectors specify iteration
/// counts outside Backup Format v1's fixed 600,000 work factor, and exporting key bytes must
/// not be reachable from shipping code.
public enum BackupCryptoVerification {
    public static func key(rawKey: Data) -> BackupEncryptionKey {
        BackupEncryptionKey(SymmetricKey(data: rawKey))
    }

    public static func keyBytes(_ key: BackupEncryptionKey) -> Data {
        key.symmetricKey.withUnsafeBytes { Data($0) }
    }

    public static func deriveKeyIgnoringWorkFactorFloor(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) throws -> BackupEncryptionKey {
        let key = try KDF.Insecure.PBKDF2.deriveKey(
            from: Data(passphrase.utf8),
            salt: salt,
            using: .sha256,
            outputByteCount: BackupCrypto.keyByteCount,
            unsafeUncheckedRounds: iterations
        )
        return BackupEncryptionKey(key)
    }
}
#endif
