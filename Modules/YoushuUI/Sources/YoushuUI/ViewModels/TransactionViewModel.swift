import Foundation
import YoushuDesignSystem
import YoushuDomain

@Observable
@MainActor
public final class TransactionViewModel {
    public var phase: YSPagePhase<TransactionListSnapshot> = .loading
    public var accounts: [Account] = []
    public var isPresentingForm = false
    public var isPresentingScreenshotBookkeeping = false
    public var editingItem: TransactionListItem?
    public var pendingDeleteItem: TransactionListItem?
    public var formError: String?
    public var isSaving = false

    private let provider: any TransactionListProviding
    private let transactionService: any TransactionManaging
    private let accountsRepository: any AccountRepository
    private let session: AppSession
    private let onDataChanged: (@Sendable () async -> Void)?

    public init(
        provider: any TransactionListProviding,
        transactionService: any TransactionManaging,
        accounts: any AccountRepository,
        session: AppSession,
        onDataChanged: (@Sendable () async -> Void)? = nil
    ) {
        self.provider = provider
        self.transactionService = transactionService
        self.accountsRepository = accounts
        self.session = session
        self.onDataChanged = onDataChanged
    }

    public func load() async {
        phase = .loading
        guard let userId = session.currentUserId else {
            phase = .error("尚未完成账户初始化")
            return
        }
        do {
            accounts = try await accountsRepository.fetchAll(userId: userId)
            let snapshot = try await provider.loadSnapshot(userId: userId)
            phase = snapshot.isEmpty ? .empty(Self.emptyConfig) : .content(snapshot)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public func presentCreate() {
        editingItem = nil
        formError = nil
        isPresentingForm = true
    }

    public func presentScreenshotBookkeeping() {
        formError = nil
        isPresentingScreenshotBookkeeping = true
    }

    public func presentEdit(_ item: TransactionListItem) {
        editingItem = item
        formError = nil
        isPresentingForm = true
    }

    public func confirmDelete(_ item: TransactionListItem) {
        pendingDeleteItem = item
    }

    public func deleteConfirmed() async {
        guard let item = pendingDeleteItem, let userId = session.currentUserId else { return }
        pendingDeleteItem = nil
        do {
            try await transactionService.delete(transactionId: item.transaction.id, userId: userId)
            await reloadAll()
        } catch {
            formError = error.localizedDescription
        }
    }

    public func saveForm(_ draft: TransactionFormDraft) async -> Bool {
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return false
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }

        do {
            if let editingItem {
                try await updateExisting(editingItem, draft: draft, userId: userId)
            } else {
                try await createNew(draft: draft, userId: userId)
            }
            isPresentingForm = false
            editingItem = nil
            await reloadAll()
            return true
        } catch {
            formError = error.localizedDescription
            return false
        }
    }

    private func createNew(draft: TransactionFormDraft, userId: UUID) async throws {
        if draft.formType == .transfer {
            guard let toAccountId = draft.toAccountId else {
                throw DomainError.validationFailed("请选择转入账户")
            }
            _ = try await transactionService.recordTransfer(
                RecordTransferInput(
                    amount: draft.amountDecimal,
                    date: draft.date,
                    fromAccountId: draft.accountId,
                    toAccountId: toAccountId,
                    note: draft.note
                ),
                userId: userId
            )
        } else {
            _ = try await transactionService.record(
                RecordTransactionInput(
                    amount: draft.amountDecimal,
                    date: draft.date,
                    merchant: draft.merchant,
                    category: draft.category,
                    accountId: draft.accountId,
                    note: draft.note,
                    formType: draft.formType
                ),
                userId: userId
            )
        }
    }

    private func updateExisting(_ item: TransactionListItem, draft: TransactionFormDraft, userId: UUID) async throws {
        _ = try await transactionService.update(
            UpdateTransactionInput(
                transactionId: item.transaction.id,
                amount: draft.amountDecimal,
                date: draft.date,
                merchant: draft.merchant,
                category: draft.category,
                accountId: draft.accountId,
                note: draft.note,
                formType: draft.formType,
                toAccountId: draft.toAccountId
            ),
            userId: userId
        )
    }

    private func reloadAll() async {
        await load()
        await onDataChanged?()
    }

    public static let emptyConfig = YSEmptyStateConfig(
        icon: "list.bullet.rectangle",
        title: "暂无账单",
        message: "点击右上角 + 记录第一笔收入或支出。",
        actionTitle: "刷新"
    )
}

/// UI 表单草稿，保存前转换为 Domain Input。
public struct TransactionFormDraft: Equatable {
    public var formType: TransactionFormType
    public var amountText: String
    public var date: Date
    public var merchant: String
    public var category: String
    public var accountId: UUID
    public var toAccountId: UUID?
    public var note: String

    public init(
        formType: TransactionFormType = .expense,
        amountText: String = "",
        date: Date = Date(),
        merchant: String = "",
        category: String = TransactionCategory.expense.first ?? "其他",
        accountId: UUID,
        toAccountId: UUID? = nil,
        note: String = ""
    ) {
        self.formType = formType
        self.amountText = amountText
        self.date = date
        self.merchant = merchant
        self.category = category
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.note = note
    }

    public var amountDecimal: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    public static func from(item: TransactionListItem, accounts: [Account]) -> TransactionFormDraft {
        let tx = item.transaction
        let formType: TransactionFormType
        if item.displayType == .transfer {
            formType = .transfer
        } else if tx.transactionType == .income {
            formType = .income
        } else {
            formType = .expense
        }
        return TransactionFormDraft(
            formType: formType,
            amountText: "\(tx.amount.amount)",
            date: tx.date,
            merchant: tx.merchant ?? "",
            category: tx.category ?? TransactionCategory.expense.first ?? "其他",
            accountId: tx.accountId,
            toAccountId: tx.transferCounterpartyAccountId,
            note: tx.note ?? ""
        )
    }
}
