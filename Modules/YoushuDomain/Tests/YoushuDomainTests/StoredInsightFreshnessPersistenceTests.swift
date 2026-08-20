import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Stored insight freshness persistence (ADR-032 Step 2)")
struct StoredInsightFreshnessPersistenceTests {
    @Test("FinancialInsight summary can carry freshness metadata")
    func summaryWithFreshnessMetadata() {
        let metadata = FinancialInsightFreshnessMetadata(
            schemaVersion: StoredInsightFreshnessSchemaVersion.current,
            policyVersion: FinancialRiskPolicyVersion.current,
            digest: String(repeating: "a", count: 64)
        )
        let insight = FinancialInsight(
            userId: UUID(),
            type: .summary,
            title: "摘要",
            body: "正文",
            freshnessMetadata: metadata
        )
        #expect(insight.freshnessMetadata == metadata)
    }

    @Test("FinancialInsight without freshness metadata remains valid")
    func legacyInsightWithoutFreshnessMetadata() {
        let insight = FinancialInsight(
            userId: UUID(),
            type: .summary,
            title: "legacy",
            body: "legacy body"
        )
        #expect(insight.freshnessMetadata == nil)
    }

    @Test("legacy stored insight JSON without freshness metadata decodes successfully")
    func legacyInsightJSONDecodes() throws {
        let json = """
        {
          "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
          "userId": "11111111-1111-1111-1111-111111111111",
          "type": "summary",
          "title": "legacy summary",
          "body": "legacy body",
          "sourceTransactionIds": [],
          "sourceDebtIds": [],
          "sourceAccountIds": [],
          "modelName": "mock",
          "generatedAt": "2026-01-01T00:00:00Z",
          "createdAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let insight = try decoder.decode(FinancialInsight.self, from: Data(json.utf8))
        #expect(insight.title == "legacy summary")
        #expect(insight.freshnessMetadata == nil)
    }

    @Test("summary with freshness metadata round-trips through JSON store persistence")
    func freshnessMetadataRoundTripThroughStore() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-freshness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("store.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let userId = UUID()
        let metadata = FinancialInsightFreshnessMetadata(
            schemaVersion: StoredInsightFreshnessSchemaVersion.current,
            policyVersion: FinancialRiskPolicyVersion.current,
            digest: DeterministicSHA256.digestHex("freshness-round-trip-token")
        )
        let insight = FinancialInsight(
            userId: userId,
            type: .summary,
            title: "fresh summary",
            body: "fresh body",
            modelName: "mock",
            freshnessMetadata: metadata
        )

        let container = RepositoryContainer.fileBacked(url: fileURL)
        try await container.users.upsert(User(id: userId, displayName: "Freshness"))
        try await container.insights.upsert(insight)
        try await container.store.persist()

        let reloadedStore = try await YoushuStore.load(from: fileURL)
        let reloaded = RepositoryContainer(store: reloadedStore)
        let loaded = try await reloaded.insights.fetchAll(userId: userId)
        #expect(loaded.count == 1)
        #expect(loaded[0].freshnessMetadata == metadata)
        #expect(await reloaded.store.currentSnapshot().schemaVersion == 4)
    }

    @Test("legacy snapshot without freshness metadata still loads after reload")
    func legacySnapshotLoads() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-legacy-insight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("store.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let userId = UUID()
        let legacyJSON = """
        {
          "schemaVersion": 4,
          "users": [{
            "id": "\(userId.uuidString)",
            "displayName": "Legacy",
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
            "debtInventoryEstablishment": "unestablished"
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
          "insights": [{
            "id": "22222222-2222-2222-2222-222222222222",
            "userId": "\(userId.uuidString)",
            "type": "summary",
            "title": "legacy",
            "body": "legacy body",
            "sourceTransactionIds": [],
            "sourceDebtIds": [],
            "sourceAccountIds": [],
            "modelName": "mock",
            "generatedAt": "2026-01-01T00:00:00Z",
            "createdAt": "2026-01-01T00:00:00Z"
          }],
          "pendingDebtLinks": [],
          "suspectedDebts": [],
          "aiDataConsents": [],
          "aiRecognitionRecords": [],
          "mediaArtifacts": []
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let store = try await YoushuStore.load(from: fileURL)
        let container = RepositoryContainer(store: store)
        let insights = try await container.insights.fetchAll(userId: userId)
        #expect(insights.count == 1)
        #expect(insights[0].freshnessMetadata == nil)
        #expect(await store.currentSnapshot().schemaVersion == 4)
    }
}
