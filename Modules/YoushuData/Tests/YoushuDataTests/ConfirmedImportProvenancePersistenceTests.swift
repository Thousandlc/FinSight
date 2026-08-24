import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Confirmed import provenance persistence")
struct ConfirmedImportProvenancePersistenceTests {
    private func source(_ label: String) -> ImportSourceFingerprint {
        ImportSourceFingerprint.sha256(of: Data(label.utf8))
    }

    private func makeProvenance(
        userId: UUID,
        capability: ConfirmedImportCapability,
        sourceLabel: String,
        entity: ConfirmedImportEntityReference,
        confirmedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> ConfirmedImportProvenance {
        try ConfirmedImportProvenance(
            userId: userId,
            capability: capability,
            sourceFingerprints: [source(sourceLabel)],
            confirmedEntityReferences: [entity],
            confirmedAt: confirmedAt
        )
    }

    @Test("v4 snapshot loads with empty provenance and migrates to v5")
    func v4Migration() async throws {
        let legacyJSON = """
        {
          "schemaVersion": 4,
          "users": [{
            "id": "00000000-0000-0000-0000-000000000101",
            "displayName": "Legacy",
            "preferredCurrency": "CNY",
            "debtInventoryEstablishment": "unestablished",
            "debtImportInProgress": false,
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
          }],
          "accounts": [],
          "transactions": [],
          "assets": [],
          "debts": [],
          "debtEvents": [],
          "repaymentPlans": [],
          "budgets": [],
          "goals": [],
          "subscriptions": [],
          "insights": [],
          "pendingDebtLinks": [],
          "suspectedDebts": [],
          "aiDataConsents": [],
          "aiRecognitionRecords": [],
          "mediaArtifacts": []
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("legacy-v4.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(legacyJSON.utf8).write(to: url)

        let store = YoushuStore(fileURL: url)
        try await store.reloadFromDisk()
        let snapshot = await store.currentSnapshot()
        #expect(snapshot.schemaVersion == YoushuSnapshot.currentSchemaVersion)
        #expect(snapshot.confirmedImportProvenances.isEmpty)
        #expect(snapshot.users.count == 1)
        #expect(snapshot.users[0].displayName == "Legacy")
    }

    @Test("v5 provenance round trip preserves durable fingerprint versioning")
    func v5RoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("provenance-v5.json")
        let store = YoushuStore(fileURL: url)
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Owner"))

        let txId = UUID()
        let provenance = try makeProvenance(
            userId: userId,
            capability: .transactionScreenshot,
            sourceLabel: "tx-image",
            entity: .transaction(txId)
        )
        _ = try await container.confirmedImportProvenances.upsert(provenance)
        try await store.persist()

        let reloadedStore = YoushuStore(fileURL: url)
        try await reloadedStore.reloadFromDisk()
        let reloaded = RepositoryContainer(store: reloadedStore)
        let records = try await reloaded.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(records.count == 1)
        let stored = try #require(records.first)
        #expect(stored.operationFingerprint.canonicalizationScheme == .canonicalV1Sha256)
        #expect(stored.operationFingerprint.algorithm == .sha256V1)
        #expect(stored.sourceFingerprints == provenance.sourceFingerprints)
        #expect(stored.operationFingerprint == provenance.operationFingerprint)
        #expect(stored.confirmedEntityReferences == [.transaction(txId)])
    }

    @Test("repository lookup is scoped by user capability and operation fingerprint")
    func repositoryLookup() async throws {
        let container = RepositoryContainer.inMemory()
        let userA = UUID()
        let userB = UUID()
        try await container.users.upsert(User(id: userA, displayName: "A"))
        try await container.users.upsert(User(id: userB, displayName: "B"))

        let sharedSource = source("shared-bytes")
        let txA = UUID()
        let txB = UUID()
        let provenanceA = try ConfirmedImportProvenance(
            userId: userA,
            capability: .transactionScreenshot,
            sourceFingerprints: [sharedSource],
            confirmedEntityReferences: [.transaction(txA)]
        )
        let provenanceB = try ConfirmedImportProvenance(
            userId: userB,
            capability: .transactionScreenshot,
            sourceFingerprints: [sharedSource],
            confirmedEntityReferences: [.transaction(txB)]
        )
        _ = try await container.confirmedImportProvenances.upsert(provenanceA)
        _ = try await container.confirmedImportProvenances.upsert(provenanceB)

        let foundA = try await container.confirmedImportProvenances.find(
            userId: userA,
            capability: .transactionScreenshot,
            operationFingerprint: provenanceA.operationFingerprint
        )
        #expect(foundA?.userId == userA)
        #expect(foundA?.confirmedEntityReferences == [.transaction(txA)])

        let foundB = try await container.confirmedImportProvenances.find(
            userId: userB,
            capability: .transactionScreenshot,
            operationFingerprint: provenanceB.operationFingerprint
        )
        #expect(foundB?.userId == userB)
        #expect(foundB?.confirmedEntityReferences == [.transaction(txB)])
        #expect(provenanceA.operationFingerprint == provenanceB.operationFingerprint)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userA).count == 1)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userB).count == 1)
    }

    @Test("logical upsert merges entity refs for same operation fingerprint")
    func logicalUpsertMerge() async throws {
        let container = RepositoryContainer.inMemory()
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Owner"))
        let sourceFingerprint = source("same-input")
        let t1 = UUID()
        let t2 = UUID()
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try ConfirmedImportProvenance(
            userId: userId,
            capability: .debtScan,
            sourceFingerprints: [sourceFingerprint],
            confirmedEntityReferences: [.debt(t1)],
            confirmedAt: early
        )
        _ = try await container.confirmedImportProvenances.upsert(first)

        let second = try ConfirmedImportProvenance(
            userId: userId,
            capability: .debtScan,
            sourceFingerprints: [sourceFingerprint],
            confirmedEntityReferences: [.debt(t2)],
            confirmedAt: later
        )
        let merged = try await container.confirmedImportProvenances.upsert(second)

        let all = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(all.count == 1)
        #expect(merged.confirmedEntityReferences == [.debt(t1), .debt(t2)])
        #expect(merged.confirmedAt == early)
    }

    @Test("duplicate entity append is idempotent")
    func duplicateEntityAppend() async throws {
        let container = RepositoryContainer.inMemory()
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Owner"))
        let debtId = UUID()
        let first = try makeProvenance(
            userId: userId,
            capability: .debtScan,
            sourceLabel: "bill",
            entity: .debt(debtId)
        )
        _ = try await container.confirmedImportProvenances.upsert(first)
        let again = try makeProvenance(
            userId: userId,
            capability: .debtScan,
            sourceLabel: "bill",
            entity: .debt(debtId)
        )
        let merged = try await container.confirmedImportProvenances.upsert(again)
        #expect(merged.confirmedEntityReferences == [.debt(debtId)])
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).count == 1)
    }

    @Test("same source bytes remain isolated across capabilities")
    func capabilityIsolation() async throws {
        let container = RepositoryContainer.inMemory()
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Owner"))
        let shared = source("shared-input")
        let tx = UUID()
        let debt = UUID()

        let txProvenance = try ConfirmedImportProvenance(
            userId: userId,
            capability: .transactionScreenshot,
            sourceFingerprints: [shared],
            confirmedEntityReferences: [.transaction(tx)]
        )
        let debtProvenance = try ConfirmedImportProvenance(
            userId: userId,
            capability: .debtScan,
            sourceFingerprints: [shared],
            confirmedEntityReferences: [.debt(debt)]
        )
        _ = try await container.confirmedImportProvenances.upsert(txProvenance)
        _ = try await container.confirmedImportProvenances.upsert(debtProvenance)

        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).count == 2)
        #expect(txProvenance.operationFingerprint != debtProvenance.operationFingerprint)
    }

    @Test("duplicate logical rows collapse on upsert")
    func duplicateLogicalRowsCollapse() async throws {
        let userId = UUID()
        let sourceFingerprint = source("shared")
        let d1 = UUID()
        let d2 = UUID()
        let first = try ConfirmedImportProvenance(
            id: UUID(),
            userId: userId,
            capability: .debtScan,
            sourceFingerprints: [sourceFingerprint],
            confirmedEntityReferences: [.debt(d1)]
        )
        let duplicate = try ConfirmedImportProvenance(
            id: UUID(),
            userId: userId,
            capability: .debtScan,
            sourceFingerprints: [sourceFingerprint],
            confirmedEntityReferences: [.debt(d2)]
        )
        var snapshot = YoushuSnapshot.empty
        snapshot.users = [User(id: userId, displayName: "Owner")]
        snapshot.confirmedImportProvenances = [first, duplicate]
        let store = YoushuStore(snapshot: snapshot)
        let repo = RepositoryContainer(store: store)

        _ = try await repo.confirmedImportProvenances.upsert(duplicate)
        let all = try await repo.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(all.count == 1)
        #expect(all[0].confirmedEntityReferences == [.debt(d1), .debt(d2)])
    }

    @Test("transaction delete releases provenance relation and removes empty provenance")
    func transactionDeleteLifecycle() async throws {
        let container = RepositoryContainer.inMemory()
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Owner"))
        let account = Account(userId: userId, name: "Cash", type: .cash)
        try await container.accounts.upsert(account)

        let t1 = UUID()
        let t2 = UUID()
        let tx1 = Transaction(
            id: t1,
            userId: userId,
            accountId: account.id,
            amount: Money(amount: 10, currencyCode: "CNY"),
            merchant: "A",
            transactionType: .expense
        )
        let tx2 = Transaction(
            id: t2,
            userId: userId,
            accountId: account.id,
            amount: Money(amount: 20, currencyCode: "CNY"),
            merchant: "B",
            transactionType: .expense
        )
        try await container.transactions.upsert(tx1)
        try await container.transactions.upsert(tx2)

        _ = try await container.confirmedImportProvenances.upsert(
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .transactionScreenshot,
                sourceFingerprints: [source("batch")],
                confirmedEntityReferences: [.transaction(t1), .transaction(t2)]
            )
        )

        try await container.transactions.delete(id: t1)
        var remaining = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(remaining.count == 1)
        #expect(remaining[0].confirmedEntityReferences == [.transaction(t2)])

        try await container.transactions.delete(id: t2)
        remaining = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(remaining.isEmpty)
    }

    @Test("debt delete releases provenance relation and removes empty provenance")
    func debtDeleteLifecycle() async throws {
        let container = RepositoryContainer.inMemory()
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Owner"))
        let d1 = UUID()
        let d2 = UUID()
        try await container.debts.upsert(Debt(id: d1, userId: userId, lender: "A"))
        try await container.debts.upsert(Debt(id: d2, userId: userId, lender: "B"))

        _ = try await container.confirmedImportProvenances.upsert(
            try ConfirmedImportProvenance(
                userId: userId,
                capability: .debtScan,
                sourceFingerprints: [source("scan")],
                confirmedEntityReferences: [.debt(d1), .debt(d2)]
            )
        )

        try await container.debts.delete(id: d1)
        var remaining = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(remaining.count == 1)
        #expect(remaining[0].confirmedEntityReferences == [.debt(d2)])

        try await container.debts.delete(id: d2)
        remaining = try await container.confirmedImportProvenances.fetchAll(userId: userId)
        #expect(remaining.isEmpty)
    }

    @Test("user delete cascade removes provenance for that user only")
    func userDeleteCascade() async throws {
        let container = RepositoryContainer.inMemory()
        let userA = UUID()
        let userB = UUID()
        try await container.users.upsert(User(id: userA, displayName: "A"))
        try await container.users.upsert(User(id: userB, displayName: "B"))

        _ = try await container.confirmedImportProvenances.upsert(
            try makeProvenance(
                userId: userA,
                capability: .debtScan,
                sourceLabel: "a",
                entity: .debt(UUID())
            )
        )
        _ = try await container.confirmedImportProvenances.upsert(
            try makeProvenance(
                userId: userB,
                capability: .debtScan,
                sourceLabel: "b",
                entity: .debt(UUID())
            )
        )

        try await container.users.delete(id: userA)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userA).isEmpty)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userB).count == 1)
    }

    @Test("malformed persisted provenance fails decode")
    func malformedPersistedRecordRejected() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000901",
          "userId": "00000000-0000-0000-0000-000000000101",
          "capability": "transactionScreenshot",
          "sourceFingerprints": [{
            "algorithm": "sha256-v1",
            "digestHex": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
          }],
          "operationFingerprint": {
            "algorithm": "sha256-v1",
            "canonicalizationScheme": "canonical-v1-sha256",
            "digestHex": "0000000000000000000000000000000000000000000000000000000000000000"
          },
          "confirmedEntityReferences": [{ "debt": "00000000-0000-0000-0000-000000000902" }],
          "confirmedAt": "2024-01-01T00:00:00Z"
        }
        """
        let data = Data(json.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ConfirmedImportProvenance.self, from: data)
        }
    }
}
