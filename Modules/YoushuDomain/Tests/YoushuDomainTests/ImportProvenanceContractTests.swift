import Foundation
import Testing
import YoushuFoundation
import YoushuDomain

@Suite("Import provenance contract")
struct ImportProvenanceContractTests {
    private func fingerprint(_ label: String) -> ImportSourceFingerprint {
        ImportSourceFingerprint.sha256(of: Data(label.utf8))
    }

    @Test("same Data yields same source fingerprint")
    func sameDataSameFingerprint() {
        let data = Data("screenshot-bytes".utf8)
        #expect(ImportSourceFingerprint.sha256(of: data) == ImportSourceFingerprint.sha256(of: data))
    }

    @Test("difference in first bytes yields different source fingerprint")
    func firstByteDifference() {
        let a = ImportSourceFingerprint.sha256(of: Data([0x01, 0x02]))
        let b = ImportSourceFingerprint.sha256(of: Data([0x02, 0x02]))
        #expect(a != b)
    }

    @Test("difference only after byte 4096 yields different source fingerprint")
    func post4096Difference() {
        let first = Data(repeating: 0xAA, count: 5000)
        var second = Data(repeating: 0xAA, count: 5000)
        second[4096] = 0xAB
        #expect(ImportSourceFingerprint.sha256(of: first) != ImportSourceFingerprint.sha256(of: second))
    }

    @Test("abc matches published SHA-256 vector")
    func abcVector() {
        #expect(
            ImportSourceFingerprint.sha256(of: Data("abc".utf8)).digestHex
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("invalid persisted digest is rejected")
    func invalidDigestRejected() {
        #expect(throws: DomainError.self) {
            try ImportSourceFingerprint.validated(digestHex: "not-a-valid-digest")
        }
    }

    @Test("operation fingerprint is order-insensitive")
    func orderInsensitive() {
        let a = fingerprint("doc-a")
        let b = fingerprint("doc-b")
        let forward = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: [a, b]
        )
        let reversed = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: [b, a]
        )
        #expect(forward == reversed)
    }

    @Test("operation fingerprint is multiplicity-sensitive")
    func multiplicitySensitive() {
        let a = fingerprint("doc-a")
        let b = fingerprint("doc-b")
        let once = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: [a, b]
        )
        let twice = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: [a, a, b]
        )
        #expect(once != twice)
    }

    @Test("operation fingerprint is capability-sensitive")
    func capabilitySensitive() {
        let a = fingerprint("shared-input")
        let tx = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .transactionScreenshot,
            sourceFingerprints: [a]
        )
        let debt = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: [a]
        )
        #expect(tx != debt)
    }

    @Test("empty source fingerprints cannot build provenance")
    func emptySourceRejected() {
        let userId = UUID()
        #expect(throws: DomainError.self) {
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .debtScan,
                sourceFingerprints: [],
                confirmedEntityReferences: [.debt(UUID())]
            )
        }
    }

    @Test("empty confirmed entity references cannot build provenance")
    func emptyEntitiesRejected() {
        let userId = UUID()
        #expect(throws: DomainError.self) {
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .transactionScreenshot,
                sourceFingerprints: [fingerprint("one")],
                confirmedEntityReferences: []
            )
        }
    }

    @Test("transaction screenshot requires exactly one source fingerprint")
    func transactionSourceCount() {
        let userId = UUID()
        #expect(throws: DomainError.self) {
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .transactionScreenshot,
                sourceFingerprints: [fingerprint("a"), fingerprint("b")],
                confirmedEntityReferences: [.transaction(UUID())]
            )
        }
    }

    @Test("capability and entity reference types must match")
    func capabilityEntityMismatch() {
        let userId = UUID()
        #expect(throws: DomainError.self) {
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .transactionScreenshot,
                sourceFingerprints: [fingerprint("tx")],
                confirmedEntityReferences: [.debt(UUID())]
            )
        }
        #expect(throws: DomainError.self) {
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .debtScan,
                sourceFingerprints: [fingerprint("debt")],
                confirmedEntityReferences: [.transaction(UUID())]
            )
        }
    }

    @Test("adding the same confirmed entity is idempotent")
    func entityAppendIdempotent() throws {
        let debtId = UUID()
        let provenance = try ConfirmedImportProvenance(
            userId: UUID(),
            capability: .debtScan,
            sourceFingerprints: [fingerprint("bill")],
            confirmedEntityReferences: [.debt(debtId)]
        )
        let again = try provenance.addingConfirmedEntity(.debt(debtId))
        #expect(again.confirmedEntityReferences == [.debt(debtId)])
    }

    @Test("partial debt confirmation can extend confirmed entity refs")
    func partialDebtAppend() throws {
        let first = UUID()
        let second = UUID()
        let provenance = try ConfirmedImportProvenance(
            userId: UUID(),
            capability: .debtScan,
            sourceFingerprints: [fingerprint("batch")],
            confirmedEntityReferences: [.debt(first)]
        )
        let extended = try provenance.addingConfirmedEntity(.debt(second))
        #expect(extended.confirmedEntityReferences == [.debt(first), .debt(second)])
    }

    @Test("removing confirmed entity relations")
    func removeEntityRelations() throws {
        let a = UUID()
        let b = UUID()
        let provenance = try ConfirmedImportProvenance(
            userId: UUID(),
            capability: .debtScan,
            sourceFingerprints: [fingerprint("batch")],
            confirmedEntityReferences: [.debt(a), .debt(b)]
        )
        let onlyB = provenance.removingConfirmedEntity(.debt(a))
        #expect(onlyB?.confirmedEntityReferences == [.debt(b)])
        #expect(provenance.removingConfirmedEntity(.debt(b))?.confirmedEntityReferences == [.debt(a)])
        #expect(onlyB?.removingConfirmedEntity(.debt(b)) == nil)
    }

    @Test("canonical bytes and operation fingerprint are deterministic")
    func determinism() {
        let a = fingerprint("alpha")
        let b = fingerprint("beta")
        let inputs = [b, a, a]
        let firstBytes = ImportFingerprintCanonicalizer.canonicalBytes(
            capability: .debtScan,
            sourceFingerprints: inputs
        )
        let secondBytes = ImportFingerprintCanonicalizer.canonicalBytes(
            capability: .debtScan,
            sourceFingerprints: [a, b, a]
        )
        let firstOp = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: inputs
        )
        let secondOp = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .debtScan,
            sourceFingerprints: [a, b, a]
        )
        #expect(firstBytes == secondBytes)
        #expect(firstOp == secondOp)
    }

    @Test("provenance stores derived operation fingerprint")
    func provenanceCarriesOperationFingerprint() throws {
        let source = fingerprint("tx-image")
        let provenance = try ConfirmedImportProvenance(
            userId: UUID(),
            capability: .transactionScreenshot,
            sourceFingerprints: [source],
            confirmedEntityReferences: [.transaction(UUID())]
        )
        let expected = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: .transactionScreenshot,
            sourceFingerprints: [source]
        )
        #expect(provenance.operationFingerprint == expected)
        #expect(provenance.operationFingerprint.canonicalizationScheme == .canonicalV1Sha256)
    }
}
