import Foundation
import Testing
import YoushuFoundation

@Suite("Backup crypto known-answer vectors")
struct BackupCryptoKnownAnswerTests {
    /// McGrew & Viega GCM spec test case 13 (AES-256, empty plaintext).
    /// With empty AAD and empty ciphertext GHASH is zero, so the tag is exactly `E(K, J0)`;
    /// that block was cross-checked against an independent AES-256 implementation.
    @Test("AES-256-GCM matches published vector for empty plaintext")
    func aesGcmEmptyPlaintextVector() throws {
        let key = try makeKey(hex: String(repeating: "00", count: 32))
        let sealed = try BackupCrypto.seal(
            plaintext: Data(),
            key: key,
            nonce: Data(repeating: 0, count: 12),
            additionalAuthenticatedData: Data()
        )
        #expect(sealed.ciphertext.isEmpty)
        #expect(sealed.tag.hexString == "530f8afbc74536b9a963b4f1c4cb738b")
    }

    /// McGrew & Viega GCM spec test case 14 (AES-256, 16 zero bytes of plaintext).
    @Test("AES-256-GCM matches published vector for single-block plaintext")
    func aesGcmSingleBlockVector() throws {
        let key = try makeKey(hex: String(repeating: "00", count: 32))
        let sealed = try BackupCrypto.seal(
            plaintext: Data(repeating: 0, count: 16),
            key: key,
            nonce: Data(repeating: 0, count: 12),
            additionalAuthenticatedData: Data()
        )
        #expect(sealed.ciphertext.hexString == "cea7403d4d606b6e074ec5d3baf39d18")
        #expect(sealed.tag.hexString == "d0d1c8a799996bf0265b98b5d48ab919")
    }

    @Test(
        "PBKDF2-HMAC-SHA256 matches published vectors",
        arguments: [
            (1, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"),
            (2, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"),
            (4096, "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"),
        ]
    )
    func pbkdf2KnownAnswer(iterations: Int, expected: String) throws {
        let key = try BackupCryptoVerification.deriveKeyIgnoringWorkFactorFloor(
            passphrase: "password",
            salt: Data("salt".utf8),
            iterations: iterations
        )
        #expect(exportedKeyHex(key) == expected)
    }

    @Test("production key derivation matches verification path at v1 work factor")
    func productionKeyDerivationMatchesVerificationPath() throws {
        let salt = Data("finsight-salt-16".utf8)
        let production = try BackupCrypto.deriveKey(
            passphrase: "password",
            salt: salt,
            iterations: 600_000
        )
        let reference = try BackupCryptoVerification.deriveKeyIgnoringWorkFactorFloor(
            passphrase: "password",
            salt: salt,
            iterations: 600_000
        )
        #expect(exportedKeyHex(production) == exportedKeyHex(reference))
    }

    @Test("AES-256-GCM round trip returns original plaintext")
    func roundTrip() throws {
        let key = try BackupCrypto.deriveKey(
            passphrase: "correct horse battery staple",
            salt: BackupCrypto.randomBytes(count: 16),
            iterations: 600_000
        )
        let nonce = BackupCrypto.randomBytes(count: BackupCrypto.nonceByteCount)
        let plaintext = Data("FinSight backup crypto".utf8)
        let aad = Data("header".utf8)

        let sealed = try BackupCrypto.seal(
            plaintext: plaintext,
            key: key,
            nonce: nonce,
            additionalAuthenticatedData: aad
        )
        let opened = try BackupCrypto.open(
            ciphertext: sealed.ciphertext,
            tag: sealed.tag,
            key: key,
            nonce: nonce,
            additionalAuthenticatedData: aad
        )
        #expect(opened == plaintext)
    }

    @Test("modified additional authenticated data fails authentication")
    func modifiedAssociatedDataFails() throws {
        let key = try makeKey(hex: String(repeating: "11", count: 32))
        let nonce = Data(repeating: 0x22, count: 12)
        let sealed = try BackupCrypto.seal(
            plaintext: Data("ledger".utf8),
            key: key,
            nonce: nonce,
            additionalAuthenticatedData: Data("iterations=600000".utf8)
        )

        #expect(throws: BackupCryptoError.authenticationFailed) {
            _ = try BackupCrypto.open(
                ciphertext: sealed.ciphertext,
                tag: sealed.tag,
                key: key,
                nonce: nonce,
                additionalAuthenticatedData: Data("iterations=599999".utf8)
            )
        }
    }

    @Test("invalid nonce length is rejected")
    func invalidNonceLength() throws {
        let key = try makeKey(hex: String(repeating: "00", count: 32))
        #expect(throws: BackupCryptoError.invalidNonceLength) {
            _ = try BackupCrypto.seal(
                plaintext: Data(),
                key: key,
                nonce: Data(repeating: 0, count: 8),
                additionalAuthenticatedData: Data()
            )
        }
    }

    @Test("invalid tag length is rejected")
    func invalidTagLength() throws {
        let key = try makeKey(hex: String(repeating: "00", count: 32))
        #expect(throws: BackupCryptoError.invalidTagLength) {
            _ = try BackupCrypto.open(
                ciphertext: Data(),
                tag: Data(repeating: 0, count: 8),
                key: key,
                nonce: Data(repeating: 0, count: 12),
                additionalAuthenticatedData: Data()
            )
        }
    }

    private func makeKey(hex: String) throws -> BackupEncryptionKey {
        BackupCryptoVerification.key(rawKey: Data(hexString: hex))
    }

    private func exportedKeyHex(_ key: BackupEncryptionKey) -> String {
        BackupCryptoVerification.keyBytes(key).hexString
    }
}

private extension Data {
    init(hexString: String) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index ..< next], radix: 16) ?? 0)
            index = next
        }
        self = Data(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
