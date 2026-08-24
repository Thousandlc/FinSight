import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Recognition metadata acceptance (ADR-036 Step C)")
struct RecognitionMetadataAcceptanceTests {
    private let sampleImage = Data("acceptance-screenshot-bytes".utf8)
    private let billImage = Data("acceptance-debt-bill-bytes".utf8)

    private func makeScreenshotEnv(
        behavior: MockAIProvider.Behavior = .success,
        binaryStore: any MediaBinaryStoring = NoPersistMediaBinaryStore()
    ) async throws -> (
        service: ScreenshotBookkeepingService,
        container: RepositoryContainer,
        userId: UUID,
        account: Account
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash)
        try await container.users.upsert(User(id: userId, displayName: "Acceptance"))
        try await container.accounts.upsert(account)
        let consent = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consent.acceptScreenshotPrivacy(userId: userId)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: binaryStore
        )
        let service = ScreenshotBookkeepingService(
            extractor: MockAIProvider(behavior: behavior),
            transactionService: TransactionService(
                accounts: container.accounts,
                transactions: container.transactions
            ),
            accounts: container.accounts,
            consentService: consent,
            media: media,
            recognitionRecords: container.aiRecognitionRecords
        )
        return (service, container, userId, account)
    }

    private func makeDebtEnv(
        behavior: MockAIProvider.DebtScanBehavior = .successMultiDebt,
        binaryStore: any MediaBinaryStoring = NoPersistMediaBinaryStore()
    ) async throws -> (DebtScannerService, RepositoryContainer, UUID) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Acceptance"))
        let consent = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consent.acceptDebtScanPrivacy(userId: userId)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: binaryStore
        )
        let service = DebtScannerService(
            scanner: MockAIProvider(debtScanBehavior: behavior),
            debtService: DebtService(
                debts: container.debts,
                events: container.debtEvents,
                accounts: container.accounts,
                transactions: container.transactions
            ),
            consentService: consent,
            media: media,
            recognitionRecords: container.aiRecognitionRecords
        )
        return (service, container, userId)
    }

    private func recognize(
        _ service: ScreenshotBookkeepingService,
        imageData: Data,
        userId: UUID
    ) async throws -> PendingScreenshotRecognition {
        let identity = TransactionScreenshotImportIdentity.from(imageData: imageData)
        return try await service.recognize(imageData: imageData, userId: userId, importIdentity: identity)
    }

    private func acceptScreenshot(
        _ service: ScreenshotBookkeepingService,
        imageData: Data,
        userId: UUID
    ) async throws -> ScreenshotRecognitionResult {
        let pending = try await recognize(service, imageData: imageData, userId: userId)
        return try await service.acceptRecognition(pending, userId: userId)
    }

    private func scanDebt(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> PendingDebtScanResult {
        let identity = DebtScanImportIdentity.from(documents: documents)
        return try await service.scan(documents: documents, userId: userId, importIdentity: identity)
    }

    private func acceptDebtScan(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> DebtScanResult {
        let pending = try await scanDebt(service, documents: documents, userId: userId)
        return try await service.acceptScan(pending, userId: userId)
    }

    @Test("transaction recognize alone does not persist metadata")
    func transactionRecognizeNoMetadata() async throws {
        let (service, container, userId, _) = try await makeScreenshotEnv()
        let pending = try await recognize(service, imageData: sampleImage, userId: userId)
        #expect(pending.aiDraft.amount == Decimal(string: "36.50"))
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).isEmpty)
    }

    @Test("transaction acceptance persists media and recognition record")
    func transactionAcceptancePersistsMetadata() async throws {
        let (service, container, userId, _) = try await makeScreenshotEnv()
        let result = try await acceptScreenshot(service, imageData: sampleImage, userId: userId)
        #expect(result.sourceImageId != nil)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).count == 1)
        let records = try await container.aiRecognitionRecords.fetchAll(userId: userId)
        #expect(records.count == 1)
        #expect(records[0].status == .recognized)
        #expect(records[0].id == result.acceptanceToken)
    }

    @Test("transaction provider failure leaves no metadata")
    func transactionProviderFailure() async throws {
        let (service, container, userId, _) = try await makeScreenshotEnv(behavior: .networkError)
        await #expect(throws: AIRecognitionError.self) {
            try await recognize(service, imageData: sampleImage, userId: userId)
        }
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
    }

    @Test("transaction repeated acceptance is idempotent")
    func transactionRepeatedAcceptance() async throws {
        let (service, container, userId, _) = try await makeScreenshotEnv()
        let pending = try await recognize(service, imageData: sampleImage, userId: userId)
        _ = try await service.acceptRecognition(pending, userId: userId)
        _ = try await service.acceptRecognition(pending, userId: userId)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).count == 1)
    }

    @Test("transaction confirm regression after acceptance")
    func transactionConfirmRegression() async throws {
        let (service, container, userId, account) = try await makeScreenshotEnv()
        let result = try await acceptScreenshot(service, imageData: sampleImage, userId: userId)
        let token = UUID()
        _ = try await service.confirm(
            ConfirmScreenshotTransactionInput(
                amount: result.editableDraft.amount!,
                date: result.editableDraft.date ?? Date(),
                merchant: result.editableDraft.merchant,
                category: result.editableDraft.category ?? "交通",
                accountId: account.id,
                formType: .expense,
                recognitionConfidence: result.editableDraft.confidence,
                sourceImageId: result.sourceImageId,
                confirmationToken: token
            ),
            userId: userId
        )
        #expect(try await container.transactions.fetchAll(userId: userId).count == 1)
        let records = try await container.aiRecognitionRecords.fetchAll(userId: userId)
        #expect(records.first?.status == .confirmed)
    }

    @Test("debt scan alone does not persist metadata")
    func debtScanNoMetadata() async throws {
        let (service, container, userId) = try await makeDebtEnv()
        let document = BillDocument(kind: .screenshot, data: billImage, fileName: "bill.png")
        let pending = try await scanDebt(service, documents: [document], userId: userId)
        #expect(!pending.candidates.isEmpty)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
    }

    @Test("debt acceptance persists media and one recognition record")
    func debtAcceptancePersistsMetadata() async throws {
        let (service, container, userId) = try await makeDebtEnv()
        let document = BillDocument(kind: .screenshot, data: billImage, fileName: "bill.png")
        let result = try await acceptDebtScan(service, documents: [document], userId: userId)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).count == 1)
        let records = try await container.aiRecognitionRecords.fetchAll(userId: userId)
        #expect(records.count == 1)
        #expect(records[0].status == .recognized)
        #expect(records[0].id == result.acceptanceToken)
    }

    @Test("debt empty aggregate throws before metadata")
    func debtEmptyAggregateNoMetadata() async throws {
        let (service, container, userId) = try await makeDebtEnv(behavior: .empty)
        let document = BillDocument(kind: .screenshot, data: billImage, fileName: "bill.png")
        await #expect(throws: AIRecognitionError.self) {
            try await scanDebt(service, documents: [document], userId: userId)
        }
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
    }

    @Test("retainOriginalImages false leaves no binary after accepted transaction confirm")
    func retainFalseTransaction() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("acceptance-tx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)
        let (service, container, userId, account) = try await makeScreenshotEnv(binaryStore: binaries)
        let result = try await acceptScreenshot(service, imageData: sampleImage, userId: userId)
        guard let imageId = result.sourceImageId else {
            Issue.record("Expected source image id")
            return
        }
        #expect(try await binaries.load(imageId: imageId, userId: userId) == nil)
        _ = try await service.confirm(
            ConfirmScreenshotTransactionInput(
                amount: 36.50,
                date: Date(),
                merchant: "地铁",
                category: "交通",
                accountId: account.id,
                formType: .expense,
                sourceImageId: imageId,
                confirmationToken: UUID()
            ),
            userId: userId
        )
        #expect(try await binaries.load(imageId: imageId, userId: userId) == nil)
        #expect(try await container.mediaArtifacts.fetch(id: imageId) == nil)
    }

    @Test("retainOriginalImages true keeps binary after accepted transaction")
    func retainTrueTransaction() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("acceptance-tx-retain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)
        let (service, container, userId, _) = try await makeScreenshotEnv(binaryStore: binaries)
        let consent = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consent.setRetainOriginalImages(true, userId: userId)
        let result = try await acceptScreenshot(service, imageData: sampleImage, userId: userId)
        guard let imageId = result.sourceImageId else {
            Issue.record("Expected source image id")
            return
        }
        #expect(try await binaries.load(imageId: imageId, userId: userId) == sampleImage)
    }

    @Test("recognition record write failure rolls back newly registered media")
    func acceptancePersistenceFailureCompensates() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Fail"))
        let consent = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consent.acceptScreenshotPrivacy(userId: userId)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: NoPersistMediaBinaryStore()
        )
        struct FailingRecognitionRepository: AIRecognitionRecordRepository {
            func upsert(_ record: AIRecognitionRecord) async throws {
                throw DataError.persistenceFailed("simulated")
            }
            func fetch(id: UUID) async throws -> AIRecognitionRecord? { nil }
            func fetchAll(userId: UUID) async throws -> [AIRecognitionRecord] { [] }
            func delete(id: UUID) async throws {}
            func deleteAll(userId: UUID) async throws {}
        }
        let service = ScreenshotBookkeepingService(
            extractor: MockAIProvider(),
            transactionService: TransactionService(
                accounts: container.accounts,
                transactions: container.transactions
            ),
            accounts: container.accounts,
            consentService: consent,
            media: media,
            recognitionRecords: FailingRecognitionRepository()
        )
        let pending = try await recognize(service, imageData: sampleImage, userId: userId)
        await #expect(throws: AIRecognitionError.self) {
            try await service.acceptRecognition(pending, userId: userId)
        }
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
    }
}
