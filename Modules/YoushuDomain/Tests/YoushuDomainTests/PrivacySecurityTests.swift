import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation
import YoushuLogging

@Suite("Privacy data deletion")
struct PrivacyDataDeletionTests {
    private func makeEnv() async throws -> (
        privacy: PrivacyDataService,
        media: MediaLifecycleService,
        container: RepositoryContainer,
        userId: UUID,
        account: Account,
        binaries: DirectoryMediaBinaryStore,
        tempRoot: URL
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "PrivacyTester"))
        let account = Account(
            userId: userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 1000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-privacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)
        let media = MediaLifecycleService(artifacts: container.mediaArtifacts, binaries: binaries)
        let txService = TransactionService(accounts: container.accounts, transactions: container.transactions)
        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let privacy = PrivacyDataService(
            users: container.users,
            transactions: container.transactions,
            debts: container.debts,
            debtEvents: container.debtEvents,
            accounts: container.accounts,
            recognitionRecords: container.aiRecognitionRecords,
            consents: container.aiDataConsents,
            media: media,
            transactionManager: txService,
            debtManager: debtService
        )
        return (privacy, media, container, userId, account, binaries, tempRoot)
    }

    @Test("deletes single transaction")
    func deleteTransaction() async throws {
        let env = try await makeEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        let tx = Transaction(
            userId: env.userId,
            accountId: env.account.id,
            amount: Money(amount: 50, currencyCode: "CNY"),
            transactionType: .expense
        )
        try await env.container.transactions.upsert(tx)
        try await env.privacy.deleteTransaction(id: tx.id, userId: env.userId)
        let remaining = try await env.container.transactions.fetchAll(userId: env.userId)
        #expect(remaining.isEmpty)
    }

    @Test("deletes debt")
    func deleteDebt() async throws {
        let env = try await makeEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        let debt = Debt(
            userId: env.userId,
            lender: "测试银行",
            outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
            source: .userInput
        )
        try await env.container.debts.upsert(debt)
        try await env.privacy.deleteDebt(id: debt.id, userId: env.userId)
        let remaining = try await env.container.debts.fetchAll(userId: env.userId)
        #expect(remaining.isEmpty)
    }

    @Test("deletes bill image and linked recognition record")
    func deleteBillImage() async throws {
        let env = try await makeEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        let data = Data("bill-bytes".utf8)
        let artifact = try await env.media.register(
            data: data,
            userId: env.userId,
            kind: .screenshotTransaction,
            retainOriginal: true
        )
        #expect(try await env.binaries.load(imageId: artifact.id, userId: env.userId) != nil)
        try await env.container.aiRecognitionRecords.upsert(
            AIRecognitionRecord(
                userId: env.userId,
                kind: .screenshotTransaction,
                sourceImageId: artifact.id,
                status: .recognized,
                summaryLabel: "截图记账识别"
            )
        )
        try await env.privacy.deleteBillImage(imageId: artifact.id, userId: env.userId)
        #expect(try await env.container.mediaArtifacts.fetch(id: artifact.id) == nil)
        #expect(try await env.binaries.load(imageId: artifact.id, userId: env.userId) == nil)
        #expect(try await env.container.aiRecognitionRecords.fetchAll(userId: env.userId).isEmpty)
    }

    @Test("deletes AI recognition record")
    func deleteRecognition() async throws {
        let env = try await makeEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        let record = AIRecognitionRecord(
            userId: env.userId,
            kind: .debtScan,
            status: .recognized,
            summaryLabel: "债务扫描"
        )
        try await env.container.aiRecognitionRecords.upsert(record)
        try await env.privacy.deleteAIRecognitionRecord(id: record.id, userId: env.userId)
        #expect(try await env.container.aiRecognitionRecords.fetchAll(userId: env.userId).isEmpty)
    }

    @Test("wipes all account data")
    func wipeAll() async throws {
        let env = try await makeEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        try await env.container.transactions.upsert(
            Transaction(
                userId: env.userId,
                accountId: env.account.id,
                amount: Money(amount: 10, currencyCode: "CNY"),
                transactionType: .expense
            )
        )
        try await env.container.debts.upsert(
            Debt(userId: env.userId, lender: "X", source: .userInput)
        )
        _ = try await env.media.register(
            data: Data("img".utf8),
            userId: env.userId,
            kind: .screenshotTransaction,
            retainOriginal: true
        )
        try await env.container.aiDataConsents.upsert(
            AIDataConsent(userId: env.userId, allowScreenshotImageToAI: true)
        )
        try await env.container.aiRecognitionRecords.upsert(
            AIRecognitionRecord(
                userId: env.userId,
                kind: .screenshotTransaction,
                status: .recognized,
                summaryLabel: "截图记账识别"
            )
        )

        try await env.privacy.wipeAllUserData(userId: env.userId)

        #expect(try await env.container.users.fetch(id: env.userId) == nil)
        #expect(try await env.container.accounts.fetchAll(userId: env.userId).isEmpty)
        #expect(try await env.container.transactions.fetchAll(userId: env.userId).isEmpty)
        #expect(try await env.container.debts.fetchAll(userId: env.userId).isEmpty)
        #expect(try await env.container.aiRecognitionRecords.fetchAll(userId: env.userId).isEmpty)
        #expect(try await env.container.aiDataConsents.fetch(userId: env.userId) == nil)
        #expect(try await env.container.mediaArtifacts.fetchAll(userId: env.userId).isEmpty)
    }
}

@Suite("Media lifecycle")
struct MediaLifecycleTests {
    @Test("default policy does not persist original binary")
    func noPersistByDefault() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "M"))
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: NoPersistMediaBinaryStore()
        )
        let artifact = try await media.register(
            data: Data("secret-bill".utf8),
            userId: userId,
            kind: .screenshotTransaction,
            retainOriginal: false
        )
        #expect(artifact.relativePath == nil)
        #expect(artifact.retention == .untilProcessed)
        #expect(MediaLifecyclePolicy.defaultRetainOriginalImages == false)
    }

    @Test("mark processed purges ephemeral image metadata")
    func purgeAfterAI() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "M"))
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-media-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)
        let media = MediaLifecycleService(artifacts: container.mediaArtifacts, binaries: binaries)

        let artifact = try await media.register(
            data: Data("bill".utf8),
            userId: userId,
            kind: .debtScan,
            retainOriginal: false
        )
        try await media.markProcessedAndMaybePurge(imageId: artifact.id, userId: userId)
        #expect(try await container.mediaArtifacts.fetch(id: artifact.id) == nil)
        #expect(try await binaries.load(imageId: artifact.id, userId: userId) == nil)
    }

    @Test("user retained images survive processed purge")
    func userRetain() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "M"))
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-retain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)
        let media = MediaLifecycleService(artifacts: container.mediaArtifacts, binaries: binaries)

        let artifact = try await media.register(
            data: Data("keep-me".utf8),
            userId: userId,
            kind: .screenshotTransaction,
            retainOriginal: true
        )
        try await media.markProcessedAndMaybePurge(imageId: artifact.id, userId: userId)
        #expect(try await container.mediaArtifacts.fetch(id: artifact.id) != nil)
        #expect(try await binaries.load(imageId: artifact.id, userId: userId) != nil)

        try await media.deleteImage(imageId: artifact.id, userId: userId)
        #expect(try await container.mediaArtifacts.fetch(id: artifact.id) == nil)
    }
}

@Suite("AI data consent")
struct AIDataConsentTests {
    @Test("default denies all AI payloads")
    func deniedDefault() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let consent = try await consentService.fetchOrDefault(userId: userId)
        #expect(consent.allowScreenshotImageToAI == false)
        #expect(consent.allowDebtScanImageToAI == false)
        #expect(consent.allowFinancialContextToAI == false)
        #expect(consent.retainOriginalImages == false)
        #expect(consent.disclosedPayloadDescriptions.contains { $0.contains("未授权") })
    }

    @Test("screenshot recognition requires consent when wired")
    func screenshotGate() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "C"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: NoPersistMediaBinaryStore()
        )
        let service = ScreenshotBookkeepingService(
            extractor: MockAIProvider(),
            transactionService: TransactionService(
                accounts: container.accounts,
                transactions: container.transactions
            ),
            accounts: container.accounts,
            consentService: consentService,
            media: media,
            recognitionRecords: container.aiRecognitionRecords
        )
        do {
            _ = try await service.recognize(imageData: Data("x".utf8), userId: userId)
            Issue.record("Expected consent required")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("记账截图"))
        }

        _ = try await consentService.acceptScreenshotPrivacy(userId: userId)
        let result = try await service.recognize(imageData: Data("x".utf8), userId: userId)
        #expect(result.sourceImageId != nil)
    }

    @Test("assistant requires financial context consent when wired")
    func assistantGate() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "A"))
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 1000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let service = FinancialAssistantService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: container.insights,
            users: container.users,
            assistant: MockAIProvider(),
            consentService: consentService
        )
        do {
            _ = try await service.ask(question: "我现在有多少钱？", userId: userId)
            Issue.record("Expected consent required")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("财务助手 Context"))
        }
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let answer = try await service.ask(question: "我现在有多少钱？", userId: userId)
        #expect(!answer.body.isEmpty)
    }

    @Test("discloses payload categories after grant")
    func disclosure() async throws {
        var consent = AIDataConsent.deniedDefault(userId: UUID())
        consent = consent.grantingScreenshotSession().grantingDebtScanSession().grantingAssistantContext()
        let texts = consent.disclosedPayloadDescriptions
        #expect(texts.contains { $0.contains("记账截图") })
        #expect(texts.contains { $0.contains("债务账单") })
        #expect(texts.contains { $0.contains("财务摘要") })
    }

    @Test("accept assistant privacy persists on refetch")
    func acceptPersists() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Accept"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let accepted = try await consentService.acceptAssistantPrivacy(userId: userId)
        #expect(accepted.allowFinancialContextToAI == true)
        let fetched = try await consentService.fetchOrDefault(userId: userId)
        #expect(fetched.allowFinancialContextToAI == true)
    }

    @Test("revoke assistant privacy clears financial context only")
    func revokeAssistantOnly() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Revoke"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptScreenshotPrivacy(userId: userId)
        _ = try await consentService.acceptDebtScanPrivacy(userId: userId)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let revoked = try await consentService.revokeAssistantPrivacy(userId: userId)
        #expect(revoked.allowFinancialContextToAI == false)
        #expect(revoked.allowScreenshotImageToAI == true)
        #expect(revoked.allowDebtScanImageToAI == true)
        #expect(revoked.retainOriginalImages == false)
    }

    @Test("revoke blocks assistant ask again")
    func revokeBlocksAsk() async throws {
        let env = try await makeAssistantConsentEnv()
        _ = try await env.consentService.acceptAssistantPrivacy(userId: env.userId)
        let answer = try await env.service.ask(question: "我现在有多少钱？", userId: env.userId)
        #expect(!answer.body.isEmpty)
        _ = try await env.consentService.revokeAssistantPrivacy(userId: env.userId)
        do {
            _ = try await env.service.ask(question: "我现在有多少钱？", userId: env.userId)
            Issue.record("Expected consent required after revoke")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("财务助手 Context"))
        }
    }

    @Test("assistant consent persists across store reload")
    func persistenceAcrossReload() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-consent-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = YoushuStore(fileURL: fileURL)
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Persist"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)

        let reloadedStore = try await YoushuStore.load(from: fileURL)
        let reloadedContainer = RepositoryContainer(store: reloadedStore)
        let reloadedConsent = AIDataConsentService(consents: reloadedContainer.aiDataConsents)
        let fetched = try await reloadedConsent.fetchOrDefault(userId: userId)
        #expect(fetched.allowFinancialContextToAI == true)
    }

    @Test("refresh insights requires financial context consent when wired")
    func refreshInsightsGate() async throws {
        let env = try await makeAssistantConsentEnv()
        let aiAssistant = AIAssistantService(
            insights: env.container.insights,
            assistant: env.service
        )
        do {
            _ = try await aiAssistant.refreshInsights(userId: env.userId)
            Issue.record("Expected consent required")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("财务助手 Context"))
        }
        _ = try await env.consentService.acceptAssistantPrivacy(userId: env.userId)
        let consent = try await env.consentService.fetchOrDefault(userId: env.userId)
        #expect(consent.allowFinancialContextToAI)
        _ = try await env.consentService.requireFinancialContext(userId: env.userId)
        let insights = try await env.service.refreshProactiveInsights(userId: env.userId)
        #expect(insights.allSatisfy { !$0.body.isEmpty })
    }

    private func makeAssistantConsentEnv() async throws -> (
        service: FinancialAssistantService,
        consentService: AIDataConsentService,
        container: RepositoryContainer,
        userId: UUID
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Assistant"))
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 1000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let service = FinancialAssistantService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: container.insights,
            users: container.users,
            assistant: MockAIProvider(),
            consentService: consentService
        )
        return (service, consentService, container, userId)
    }

    @Test("independent consent fields persist without overwriting each other")
    func independentFieldPersistence() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-consent-fields-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = YoushuStore(fileURL: fileURL)
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Fields"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)

        func reloadService() async throws -> AIDataConsentService {
            let reloaded = try await YoushuStore.load(from: fileURL)
            return AIDataConsentService(consents: RepositoryContainer(store: reloaded).aiDataConsents)
        }

        _ = try await consentService.acceptScreenshotPrivacy(userId: userId)
        var fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(fetched.allowScreenshotImageToAI)
        #expect(!fetched.allowDebtScanImageToAI)
        #expect(!fetched.allowFinancialContextToAI)
        #expect(!fetched.retainOriginalImages)

        _ = try await consentService.acceptDebtScanPrivacy(userId: userId)
        fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(fetched.allowScreenshotImageToAI)
        #expect(fetched.allowDebtScanImageToAI)
        #expect(!fetched.allowFinancialContextToAI)

        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(fetched.allowScreenshotImageToAI)
        #expect(fetched.allowDebtScanImageToAI)
        #expect(fetched.allowFinancialContextToAI)
        #expect(!fetched.retainOriginalImages)

        _ = try await consentService.setRetainOriginalImages(true, userId: userId)
        fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(fetched.allowScreenshotImageToAI)
        #expect(fetched.allowDebtScanImageToAI)
        #expect(fetched.allowFinancialContextToAI)
        #expect(fetched.retainOriginalImages)

        _ = try await consentService.revokeScreenshotPrivacy(userId: userId)
        fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(!fetched.allowScreenshotImageToAI)
        #expect(fetched.allowDebtScanImageToAI)
        #expect(fetched.allowFinancialContextToAI)
        #expect(fetched.retainOriginalImages)

        _ = try await consentService.revokeDebtScanPrivacy(userId: userId)
        fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(!fetched.allowDebtScanImageToAI)
        #expect(fetched.allowFinancialContextToAI)
        #expect(fetched.retainOriginalImages)

        _ = try await consentService.revokeAssistantPrivacy(userId: userId)
        fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(!fetched.allowFinancialContextToAI)
        #expect(fetched.retainOriginalImages)

        _ = try await consentService.setRetainOriginalImages(false, userId: userId)
        fetched = try await (await reloadService()).fetchOrDefault(userId: userId)
        #expect(!fetched.retainOriginalImages)
        #expect(!fetched.allowScreenshotImageToAI)
        #expect(!fetched.allowDebtScanImageToAI)
        #expect(!fetched.allowFinancialContextToAI)
    }

    @Test("screenshot revoke blocks recognition and skips extractor")
    func screenshotRevokeGate() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "ShotRevoke"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let extractor = CountingTransactionExtractor()
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: NoPersistMediaBinaryStore()
        )
        let service = ScreenshotBookkeepingService(
            extractor: extractor,
            transactionService: TransactionService(
                accounts: container.accounts,
                transactions: container.transactions
            ),
            accounts: container.accounts,
            consentService: consentService,
            media: media
        )

        _ = try await consentService.acceptScreenshotPrivacy(userId: userId)
        _ = try await service.recognize(imageData: Data("x".utf8), userId: userId)
        #expect(extractor.callCount == 1)

        _ = try await consentService.revokeScreenshotPrivacy(userId: userId)
        do {
            _ = try await service.recognize(imageData: Data("y".utf8), userId: userId)
            Issue.record("Expected consent required after revoke")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("记账截图"))
        }
        #expect(extractor.callCount == 1)
    }

    @Test("debt scan requires consent when wired")
    func debtScanGate() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "DebtGate"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let scanner = CountingDebtScanner()
        let service = DebtScannerService(
            scanner: scanner,
            debtService: DebtService(
                debts: container.debts,
                events: container.debtEvents,
                accounts: container.accounts,
                transactions: container.transactions
            ),
            consentService: consentService
        )
        let document = BillDocument(kind: .screenshot, data: Data("bill".utf8), fileName: "a.png")

        do {
            _ = try await service.scan(documents: [document], userId: userId)
            Issue.record("Expected consent required")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("债务账单图片"))
        }
        #expect(scanner.callCount == 0)

        _ = try await consentService.acceptDebtScanPrivacy(userId: userId)
        _ = try await service.scan(documents: [document], userId: userId)
        #expect(scanner.callCount == 1)
    }

    @Test("debt scan revoke blocks scan and skips scanner")
    func debtScanRevokeGate() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "DebtRevoke"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let scanner = CountingDebtScanner()
        let service = DebtScannerService(
            scanner: scanner,
            debtService: DebtService(
                debts: container.debts,
                events: container.debtEvents,
                accounts: container.accounts,
                transactions: container.transactions
            ),
            consentService: consentService
        )
        let document = BillDocument(kind: .screenshot, data: Data("bill".utf8), fileName: "a.png")

        _ = try await consentService.acceptDebtScanPrivacy(userId: userId)
        _ = try await service.scan(documents: [document], userId: userId)
        #expect(scanner.callCount == 1)

        _ = try await consentService.revokeDebtScanPrivacy(userId: userId)
        do {
            _ = try await service.scan(documents: [document], userId: userId)
            Issue.record("Expected consent required after revoke")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("债务账单图片"))
        }
        #expect(scanner.callCount == 1)
    }

    @Test("retainOriginalImages preference persists without changing AI consent fields")
    func retainOriginalImagesContract() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Retain"))
        let consentService = AIDataConsentService(consents: container.aiDataConsents)

        _ = try await consentService.acceptScreenshotPrivacy(userId: userId)
        _ = try await consentService.acceptDebtScanPrivacy(userId: userId)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)

        _ = try await consentService.setRetainOriginalImages(true, userId: userId)
        var fetched = try await consentService.fetchOrDefault(userId: userId)
        #expect(fetched.retainOriginalImages)
        #expect(fetched.allowScreenshotImageToAI)
        #expect(fetched.allowDebtScanImageToAI)
        #expect(fetched.allowFinancialContextToAI)

        _ = try await consentService.setRetainOriginalImages(false, userId: userId)
        fetched = try await consentService.fetchOrDefault(userId: userId)
        #expect(!fetched.retainOriginalImages)
        #expect(fetched.allowScreenshotImageToAI)
        #expect(fetched.allowDebtScanImageToAI)
        #expect(fetched.allowFinancialContextToAI)
    }

    @Test("evaluatePurchase requires financial context consent before provider call")
    func evaluatePurchaseConsentGate() async throws {
        let env = try await makeAssistantConsentEnv()
        let assistant = PurchaseScenarioCountingAssistant()
        let service = FinancialAssistantService(
            accounts: env.container.accounts,
            transactions: env.container.transactions,
            debts: env.container.debts,
            repaymentPlans: env.container.repaymentPlans,
            assets: env.container.assets,
            budgets: env.container.budgets,
            goals: env.container.goals,
            insights: env.container.insights,
            users: env.container.users,
            assistant: assistant,
            consentService: env.consentService
        )

        do {
            _ = try await service.evaluatePurchase(amount: 3_000, userId: env.userId)
            Issue.record("Expected consent required")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("财务助手 Context"))
        }
        #expect(assistant.phrasePurchaseScenarioCount == 0)

        _ = try await env.consentService.acceptAssistantPrivacy(userId: env.userId)
        let (_, answer) = try await service.evaluatePurchase(amount: 3_000, userId: env.userId)
        #expect(assistant.phrasePurchaseScenarioCount == 1)
        #expect(!answer.body.isEmpty)
    }
}

// MARK: - Test doubles

private final class CountingTransactionExtractor: TransactionExtracting, @unchecked Sendable {
    let name = "counting-extractor"
    private(set) var callCount = 0
    private let mock = MockAIProvider()

    func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
        callCount += 1
        return try await mock.extractTransactionDraft(fromImageData: data)
    }
}

private final class CountingDebtScanner: DebtScanning, @unchecked Sendable {
    let name = "counting-scanner"
    private(set) var callCount = 0
    private let mock = MockAIProvider()

    func scanDebts(from documents: [BillDocument]) async throws -> [DebtCandidate] {
        callCount += 1
        return try await mock.scanDebts(from: documents)
    }
}

private final class PurchaseScenarioCountingAssistant: FinancialAssisting, @unchecked Sendable {
    private let mock = MockAIProvider()
    private(set) var phrasePurchaseScenarioCount = 0
    var name: String { mock.name }

    func phraseAnswer(request: AssistantRequestDTO, facts: AnswerFactPack) async throws -> AssistantAnswerDraft {
        try await mock.phraseAnswer(request: request, facts: facts)
    }

    func phraseMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> AssistantAnswerDraft {
        try await mock.phraseMonthlySummary(request: request, facts: facts, riskAssessment: riskAssessment)
    }

    func phrasePurchaseScenario(
        request: AssistantRequestDTO,
        scenario: PurchaseScenario
    ) async throws -> AssistantAnswerDraft {
        phrasePurchaseScenarioCount += 1
        return try await mock.phrasePurchaseScenario(request: request, scenario: scenario)
    }

    func phraseInsight(request: AssistantRequestDTO, facts: InsightFactPack) async throws -> AssistantAnswerDraft {
        try await mock.phraseInsight(request: request, facts: facts)
    }
}

@Suite("Token and log security")
struct TokenAndLogSecurityTests {
    @Test("secure token store round-trips without logging token value")
    func tokenStore() throws {
        let store = InMemorySecureTokenStore()
        try store.save(token: "sk-test-secret-token", account: "api")
        #expect(try store.load(account: "api") == "sk-test-secret-token")
        try store.delete(account: "api")
        #expect(try store.load(account: "api") == nil)
    }

    @Test("log redactor strips amounts tokens keys and images")
    func logScan() {
        let raw = """
        amount=128.50 balance:999 Bearer eyJhbGciOiJIUzI1NiJ9.abc api_key=sk-live-abc123 \
        phone=13800138000 ¥36.50 data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """
        let safe = LogRedactor.redact(raw)
        #expect(!LogRedactor.containsSensitiveLeak(safe))
        #expect(safe.contains("[AMOUNT]") || safe.contains("¥[AMOUNT]"))
        #expect(safe.contains("[REDACTED]"))
        #expect(safe.contains("[IMAGE_REDACTED]") || safe.contains("[PII]"))
        #expect(!safe.contains("sk-live-abc123"))
        #expect(!safe.contains("eyJhbGciOiJIUzI1NiJ9"))
    }

    @Test("privacy safe error mapper never echoes token or amount")
    func errorMapper() {
        let message = PrivacySafeErrorMapper.userMessage(for: PrivacyError.tokenUnavailable)
        #expect(!message.contains("token"))
        #expect(!message.lowercased().contains("api"))
        let generic = PrivacySafeErrorMapper.userMessage(
            for: NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "amount=999 api_key=secret",
            ])
        )
        #expect(!generic.contains("999"))
        #expect(!generic.contains("secret"))
    }
}

@Suite("Debt source markers")
struct DebtSourcePrivacyTests {
    @Test("supports required debt source markers")
    func requiredSources() {
        let required: [DebtSource] = [
            .screenshot,
            .transactionInference,
            .userInput,
            .futureAPI,
        ]
        for source in required {
            #expect(DebtSource.allCases.contains(source))
        }
    }
}
