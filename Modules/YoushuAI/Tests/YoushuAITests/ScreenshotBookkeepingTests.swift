import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Screenshot AI bookkeeping")
struct ScreenshotBookkeepingTests {
    private let sampleImage = Data("fake-screenshot-bytes".utf8)

    private func makeService(behavior: MockAIProvider.Behavior) -> (
        service: ScreenshotBookkeepingService,
        container: RepositoryContainer,
        userId: UUID,
        wechat: Account,
        cash: Account
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        let service = ScreenshotBookkeepingService(
            extractor: MockAIProvider(behavior: behavior),
            transactionService: txService,
            accounts: container.accounts
        )
        let wechat = Account(userId: userId, name: "微信", type: .weChat)
        let cash = Account(userId: userId, name: "现金", type: .cash)
        return (service, container, userId, wechat, cash)
    }

    private func seedUserAndAccounts(
        container: RepositoryContainer,
        userId: UUID,
        accounts: [Account]
    ) async throws {
        try await container.users.upsert(User(id: userId, displayName: "Tester"))
        for account in accounts {
            try await container.accounts.upsert(account)
        }
    }

    @Test("normal recognition returns structured draft")
    func normalRecognition() async throws {
        let env = makeService(behavior: .success)
        try await seedUserAndAccounts(container: env.container, userId: env.userId, accounts: [env.wechat, env.cash])

        let result = try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        #expect(result.aiDraft.amount == Decimal(string: "36.50"))
        #expect(result.aiDraft.merchant == "地铁出行")
        #expect(result.aiDraft.transactionType == .expense)
        #expect(result.aiDraft.category == "交通")
        #expect(result.aiDraft.confidence == 0.91)
        #expect(result.sourceImageId != nil)
        #expect(result.warnings.isEmpty)
    }

    @Test("amount missing fails recognition")
    func amountMissing() async throws {
        let env = makeService(behavior: .amountMissing)
        await #expect(throws: AIRecognitionError.self) {
            try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        }
    }

    @Test("date missing yields warning but allows recognition")
    func dateMissing() async throws {
        let env = makeService(behavior: .dateMissing)
        let result = try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        #expect(result.aiDraft.date == nil)
        #expect(result.aiDraft.amount == Decimal(string: "36.50"))
        #expect(result.warnings.contains(where: { $0.contains("时间") }))
    }

    @Test("ambiguous amounts fail recognition")
    func ambiguousAmounts() async throws {
        let env = makeService(behavior: .ambiguousAmount)
        do {
            _ = try await env.service.recognize(imageData: sampleImage, userId: env.userId)
            Issue.record("Expected ambiguous amount error")
        } catch let error as AIRecognitionError {
            guard case .ambiguousAmount(let amounts) = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
            #expect(amounts.count == 2)
        }
    }

    @Test("invalid AI response format fails")
    func invalidFormat() async throws {
        let env = makeService(behavior: .invalidResponse)
        await #expect(throws: AIRecognitionError.invalidResponse("JSON missing required envelope")) {
            try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        }
    }

    @Test("network error fails loudly")
    func networkError() async throws {
        let env = makeService(behavior: .networkError)
        await #expect(throws: AIRecognitionError.requestFailed("模拟网络错误")) {
            try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        }
    }

    @Test("timeout fails loudly")
    func timeout() async throws {
        let env = makeService(behavior: .timeout)
        await #expect(throws: AIRecognitionError.networkTimeout) {
            try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        }
    }

    @Test("empty image is unreadable")
    func emptyImage() async throws {
        let env = makeService(behavior: .success)
        await #expect(throws: AIRecognitionError.imageUnreadable) {
            try await env.service.recognize(imageData: Data(), userId: env.userId)
        }
    }

    @Test("user can modify recognition result before creating transaction")
    func userModifyThenCreate() async throws {
        let env = makeService(behavior: .success)
        try await seedUserAndAccounts(container: env.container, userId: env.userId, accounts: [env.wechat, env.cash])

        let result = try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        #expect(result.aiDraft.amount == Decimal(string: "36.50"))

        // 用户修改金额与商户；aiDraft 保持不变
        let tx = try await env.service.confirm(
            ConfirmScreenshotTransactionInput(
                amount: Decimal(string: "40.00")!,
                date: Date(timeIntervalSince1970: 1_700_000_100),
                merchant: "用户修改商户",
                category: "餐饮",
                accountId: env.cash.id,
                note: "手工核对",
                formType: .expense,
                recognitionConfidence: result.aiDraft.confidence,
                sourceImageId: result.sourceImageId
            ),
            userId: env.userId
        )

        #expect(tx.amount.amount == Decimal(string: "40.00"))
        #expect(tx.merchant == "用户修改商户")
        #expect(tx.category == "餐饮")
        #expect(tx.source == .screenshot)
        #expect(tx.recognitionConfidence == 0.91)
        #expect(tx.sourceImageId == result.sourceImageId)
        #expect(result.aiDraft.amount == Decimal(string: "36.50"))
        #expect(result.aiDraft.merchant == "地铁出行")
    }

    @Test("confirm creates transaction and updates account balance")
    func createTransactionUpdatesBalance() async throws {
        let env = makeService(behavior: .success)
        let cash = Account(
            userId: env.userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 1000, currencyCode: "CNY")
        )
        try await seedUserAndAccounts(container: env.container, userId: env.userId, accounts: [cash])

        let result = try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        let accountId = try await env.service.defaultAccountId(for: result.editableDraft, userId: env.userId)
        #expect(accountId == cash.id)

        let tx = try await env.service.confirm(
            ConfirmScreenshotTransactionInput(
                amount: result.editableDraft.amount!,
                date: result.editableDraft.date ?? Date(),
                merchant: result.editableDraft.merchant,
                category: result.editableDraft.category ?? "交通",
                accountId: cash.id,
                formType: .expense,
                recognitionConfidence: result.editableDraft.confidence,
                sourceImageId: result.sourceImageId
            ),
            userId: env.userId
        )

        let txs = try await env.container.transactions.fetchAll(userId: env.userId)
        #expect(txs.count == 1)
        #expect(txs[0].id == tx.id)

        let balance = AccountBalanceEngine.balance(account: cash, transactions: txs)
        #expect(balance.amount == Decimal(string: "963.50"))
    }

    @Test("suggested account name maps to wechat")
    func resolveSuggestedAccount() async throws {
        let env = makeService(behavior: .success)
        try await seedUserAndAccounts(container: env.container, userId: env.userId, accounts: [env.wechat, env.cash])
        let result = try await env.service.recognize(imageData: sampleImage, userId: env.userId)
        let resolved = try await env.service.defaultAccountId(for: result.aiDraft, userId: env.userId)
        #expect(resolved == env.wechat.id)
    }

    @Test("prompt constants exist for provider use")
    func promptExists() {
        #expect(!ScreenshotRecognitionPrompt.system.isEmpty)
        #expect(ScreenshotRecognitionPrompt.system.contains("禁止凭空补全金额"))
        #expect(!ScreenshotRecognitionPrompt.userTemplate.isEmpty)
    }
}
