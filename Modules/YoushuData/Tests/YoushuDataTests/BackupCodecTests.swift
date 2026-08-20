import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Backup codec v1")
struct BackupCodecTests {
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let txId = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!

    private func samplePayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion,
                sourceAppVersion: "codec-test"
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: Self.userId,
                        displayName: "Codec",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .partial,
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ],
                accounts: [
                    Account(id: Self.accountId, userId: Self.userId, name: "Cash", type: .cash),
                ],
                transactions: [
                    Transaction(
                        id: Self.txId,
                        userId: Self.userId,
                        accountId: Self.accountId,
                        amount: Money(amount: 88, currencyCode: "CNY"),
                        merchant: "Shop",
                        category: "Life",
                        transactionType: .expense
                    ),
                ]
            )
        )
    }

    private func makeEnvelopeData(
        formatVersion: Int = BackupFormatV1Policy.formatVersion,
        kdfAlgorithm: String = BackupFormatV1Policy.kdfAlgorithm,
        kdfIterations: Int = BackupFormatV1Policy.kdfIterations,
        keyLengthBits: Int = BackupFormatV1Policy.keyLengthBits,
        cipherAlgorithm: String = BackupFormatV1Policy.cipherAlgorithm,
        saltByteCount: Int = BackupFormatV1Policy.saltByteCount,
        nonceByteCount: Int = BackupFormatV1Policy.nonceByteCount,
        tagByteCount: Int = BackupFormatV1Policy.authenticationTagByteCount
    ) throws -> Data {
        let envelope = FinSightBackupEnvelopeV1(
            formatVersion: formatVersion,
            kdfAlgorithm: kdfAlgorithm,
            kdfIterations: kdfIterations,
            keyLengthBits: keyLengthBits,
            cipherAlgorithm: cipherAlgorithm,
            salt: Data(repeating: 1, count: saltByteCount),
            nonce: Data(repeating: 2, count: nonceByteCount),
            ciphertext: Data(repeating: 3, count: 32),
            authenticationTag: Data(repeating: 4, count: tagByteCount)
        )
        return try JSONEncoder().encode(envelope)
    }

    @Test("encrypt decrypt round trip preserves financial facts and relationship ids")
    func encryptDecryptRoundTrip() throws {
        let payload = samplePayload()
        let backupData = try BackupCodec.encode(
            payload: payload,
            passphrase: "test-passphrase"
        )
        let decoded = try BackupCodec.decode(backupData: backupData, passphrase: "test-passphrase")

        #expect(decoded.metadata.sourceAppVersion == payload.metadata.sourceAppVersion)
        #expect(decoded.metadata.createdAt == payload.metadata.createdAt)
        #expect(decoded.financialData.users.first?.id == Self.userId)
        #expect(decoded.financialData.accounts.first?.userId == Self.userId)
        #expect(decoded.financialData.transactions.count == 1)
        #expect(decoded.financialData.transactions.first?.id == Self.txId)
        #expect(decoded.financialData.transactions.first?.accountId == Self.accountId)
        #expect(decoded.financialData.transactions.first?.amount.amount == 88)

        let envelope = try JSONDecoder().decode(FinSightBackupEnvelopeV1.self, from: backupData)
        #expect(envelope.kdfIterations == BackupFormatV1Policy.kdfIterations)
    }

    @Test("each backup uses fresh salt and nonce")
    func freshSaltAndNoncePerBackup() throws {
        let first = try BackupCodec.encode(
            payload: samplePayload(),
            passphrase: "test-passphrase"
        )
        let second = try BackupCodec.encode(
            payload: samplePayload(),
            passphrase: "test-passphrase"
        )
        #expect(first != second)
    }

    @Test("wrong passphrase fails authentication")
    func wrongPassphraseFails() throws {
        let backupData = try BackupCodec.encode(
            payload: samplePayload(),
            passphrase: "correct-passphrase"
        )
        #expect(throws: BackupError.authenticationFailure) {
            _ = try BackupCodec.decode(backupData: backupData, passphrase: "wrong-passphrase")
        }
    }

    @Test("modified ciphertext fails authentication")
    func modifiedCiphertextFails() throws {
        let backupData = try BackupCodec.encode(
            payload: samplePayload(),
            passphrase: "secure-passphrase"
        )
        var envelope = try JSONDecoder().decode(FinSightBackupEnvelopeV1.self, from: backupData)
        envelope.ciphertext[envelope.ciphertext.startIndex] ^= 0xFF
        let tampered = try JSONEncoder().encode(envelope)

        #expect(throws: BackupError.authenticationFailure) {
            _ = try BackupCodec.decode(backupData: tampered, passphrase: "secure-passphrase")
        }
    }

    @Test("tampered kdf iteration header is rejected before kdf execution")
    func tamperedIterationHeaderRejected() throws {
        let backupData = try BackupCodec.encode(
            payload: samplePayload(),
            passphrase: "secure-passphrase"
        )
        var envelope = try JSONDecoder().decode(FinSightBackupEnvelopeV1.self, from: backupData)
        envelope.kdfIterations = BackupFormatV1Policy.kdfIterations - 1
        let tampered = try JSONEncoder().encode(envelope)

        #expect(throws: BackupError.invalidCryptoParameter(field: "kdfIterations")) {
            _ = try BackupCodec.decode(backupData: tampered, passphrase: "secure-passphrase")
        }
    }

    @Test("empty and malformed input fail safely")
    func malformedInputFails() {
        #expect(throws: BackupError.malformedEnvelope("empty backup data")) {
            _ = try BackupCodec.decode(backupData: Data(), passphrase: "pass")
        }
        #expect(throws: BackupError.malformedEnvelope("invalid envelope json")) {
            _ = try BackupCodec.decode(backupData: Data("{".utf8), passphrase: "pass")
        }
        #expect(throws: BackupError.malformedEnvelope("invalid base64 field")) {
            let json = """
            {"formatVersion":1,"kdfAlgorithm":"PBKDF2-HMAC-SHA256","kdfIterations":600000,\
            "keyLengthBits":256,"cipherAlgorithm":"AES-256-GCM","salt":"not base64!!",\
            "nonce":"AAAA","ciphertext":"AAAA","authenticationTag":"AAAA"}
            """
            _ = try BackupCodec.decode(backupData: Data(json.utf8), passphrase: "pass")
        }
    }

    @Test("oversized backup file is rejected before parsing")
    func oversizedFileRejected() {
        let limit = BackupFormatV1Policy.maximumBackupFileByteCount
        let oversized = Data(repeating: 0x7B, count: limit + 1)
        #expect(throws: BackupError.backupTooLarge(byteCount: limit + 1, limit: limit)) {
            _ = try BackupCodec.decode(backupData: oversized, passphrase: "pass")
        }
    }

    @Test("unsupported envelope format version is rejected")
    func unsupportedFormatFails() throws {
        let data = try makeEnvelopeData(formatVersion: 99)
        #expect(throws: BackupError.unsupportedFormat(found: 99, supported: 1)) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test("unsupported kdf algorithm is rejected")
    func unsupportedKdfAlgorithmFails() throws {
        let data = try makeEnvelopeData(kdfAlgorithm: "PBKDF2-HMAC-SHA1")
        #expect(throws: BackupError.unsupportedAlgorithm(field: "kdfAlgorithm")) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test("unsupported cipher algorithm is rejected")
    func unsupportedCipherAlgorithmFails() throws {
        let data = try makeEnvelopeData(cipherAlgorithm: "AES-128-CBC")
        #expect(throws: BackupError.unsupportedAlgorithm(field: "cipherAlgorithm")) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test("unsupported key length is rejected")
    func unsupportedKeyLengthFails() throws {
        let data = try makeEnvelopeData(keyLengthBits: 128)
        #expect(throws: BackupError.invalidCryptoParameter(field: "keyLengthBits")) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test("exactly 600000 kdf iterations passes envelope validation")
    func exactIterationsAccepted() throws {
        let data = try makeEnvelopeData(kdfIterations: BackupFormatV1Policy.kdfIterations)
        do {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        } catch BackupError.invalidCryptoParameter(field: "kdfIterations") {
            Issue.record("600000 iterations must not be rejected as invalid")
        } catch {
            // Dummy ciphertext fails authentication after validation; that is expected.
        }
    }

    @Test(
        "non-v1 kdf iteration counts are rejected before running the kdf",
        arguments: [
            0,
            -1,
            599_999,
            600_001,
            210_000,
            Int.max,
        ]
    )
    func nonV1IterationsRejected(iterations: Int) throws {
        let data = try makeEnvelopeData(kdfIterations: iterations)
        #expect(throws: BackupError.invalidCryptoParameter(field: "kdfIterations")) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test(
        "non-v1 kdf iteration counts are rejected when encoding",
        arguments: [0, -1, 599_999, 600_001, 210_000, 1, Int.max]
    )
    func nonV1IterationsRejectedOnEncode(iterations: Int) {
        #expect(throws: BackupError.invalidCryptoParameter(field: "kdfIterations")) {
            _ = try BackupCodec.encode(
                payload: samplePayload(),
                passphrase: "pass",
                configuration: BackupCodecConfiguration(kdfIterations: iterations)
            )
        }
    }

    @Test("invalid salt length is rejected", arguments: [1, 8, 15, 17, 64])
    func invalidSaltLengthRejected(saltByteCount: Int) throws {
        let data = try makeEnvelopeData(saltByteCount: saltByteCount)
        #expect(throws: BackupError.invalidCryptoParameter(field: "salt")) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test("invalid nonce length is rejected", arguments: [1, 8, 11, 13, 16])
    func invalidNonceLengthRejected(nonceByteCount: Int) throws {
        let data = try makeEnvelopeData(nonceByteCount: nonceByteCount)
        #expect(throws: BackupError.invalidCryptoParameter(field: "nonce")) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test("invalid authentication tag length is rejected", arguments: [1, 8, 15, 17, 32])
    func invalidTagLengthRejected(tagByteCount: Int) throws {
        let data = try makeEnvelopeData(tagByteCount: tagByteCount)
        #expect(throws: BackupError.invalidCryptoParameter(field: "authenticationTag")) {
            _ = try BackupCodec.decode(backupData: data, passphrase: "pass")
        }
    }

    @Test("passphrase and financial plaintext do not appear in serialized output")
    func passphraseNotInOutput() throws {
        let backupData = try BackupCodec.encode(
            payload: samplePayload(),
            passphrase: "super-secret-passphrase"
        )
        let serialized = String(decoding: backupData, as: UTF8.self)
        #expect(!serialized.contains("super-secret-passphrase"))
        #expect(!serialized.contains("Codec"))
        #expect(!serialized.contains("Shop"))
        #expect(!serialized.contains(Self.userId.uuidString))
    }
}
