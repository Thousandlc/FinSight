import Foundation
import YoushuDesignSystem
import YoushuDomain

@Observable
@MainActor
public final class AccountViewModel {
    public var phase: YSPagePhase<AccountListSnapshot> = .loading
    public var isPresentingForm = false
    public var editingSummary: AccountSummary?
    public var selectedAccountId: UUID?
    public var detailPhase: YSPagePhase<AccountDetailSnapshot> = .loading
    public var pendingDeleteSummary: AccountSummary?
    public var formError: String?
    public var isSaving = false
    public var isPresentingPrivacyAISettings = false

    private let provider: any AccountListProviding
    private let accountService: any AccountManaging
    private let session: AppSession
    private let onDataChanged: (@Sendable () async -> Void)?

    public init(
        provider: any AccountListProviding,
        accountService: any AccountManaging,
        session: AppSession,
        onDataChanged: (@Sendable () async -> Void)? = nil
    ) {
        self.provider = provider
        self.accountService = accountService
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
            let snapshot = try await provider.loadSnapshot(userId: userId)
            phase = snapshot.isEmpty ? .empty(Self.emptyConfig) : .content(snapshot)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public func openPrivacyAISettings() {
        isPresentingPrivacyAISettings = true
    }

    public func loadDetail(accountId: UUID) async {
        detailPhase = .loading
        guard let userId = session.currentUserId else {
            detailPhase = .error("尚未完成账户初始化")
            return
        }
        do {
            let detail = try await provider.loadDetail(accountId: accountId, userId: userId)
            detailPhase = .content(detail)
        } catch {
            detailPhase = .error(error.localizedDescription)
        }
    }

    public func presentCreate() {
        editingSummary = nil
        formError = nil
        isPresentingForm = true
    }

    public func presentEdit(_ summary: AccountSummary) {
        editingSummary = summary
        formError = nil
        isPresentingForm = true
    }

    public func openDetail(_ summary: AccountSummary) {
        selectedAccountId = summary.id
    }

    public func confirmDelete(_ summary: AccountSummary) {
        pendingDeleteSummary = summary
    }

    public func deleteConfirmed() async {
        guard let summary = pendingDeleteSummary, let userId = session.currentUserId else { return }
        pendingDeleteSummary = nil
        do {
            try await accountService.delete(accountId: summary.id, userId: userId)
            if selectedAccountId == summary.id { selectedAccountId = nil }
            await reloadAll()
        } catch {
            formError = error.localizedDescription
        }
    }

    public func saveForm(_ draft: AccountFormDraft) async -> Bool {
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return false
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }

        do {
            if let editingSummary {
                _ = try await accountService.update(
                    UpdateAccountInput(
                        accountId: editingSummary.id,
                        name: draft.name,
                        type: draft.type,
                        openingBalance: draft.openingBalanceDecimal,
                        currencyCode: draft.currencyCode,
                        note: draft.note.nilIfEmpty
                    ),
                    userId: userId
                )
            } else {
                _ = try await accountService.create(
                    CreateAccountInput(
                        name: draft.name,
                        type: draft.type,
                        openingBalance: draft.openingBalanceDecimal,
                        currencyCode: draft.currencyCode,
                        note: draft.note.nilIfEmpty,
                        createLinkedDebt: draft.type == .creditCard
                    ),
                    userId: userId
                )
            }
            isPresentingForm = false
            editingSummary = nil
            await reloadAll()
            if let id = selectedAccountId {
                await loadDetail(accountId: id)
            }
            return true
        } catch {
            formError = error.localizedDescription
            return false
        }
    }

    private func reloadAll() async {
        await load()
        await onDataChanged?()
    }

    public static let emptyConfig = YSEmptyStateConfig(
        icon: "wallet.pass",
        title: "暂无账户",
        message: "添加现金、银行卡、支付宝等账户，清楚掌握你的钱在哪里。",
        actionTitle: "添加账户"
    )
}

public struct AccountFormDraft: Equatable {
    public var name: String
    public var type: AccountType
    public var openingBalanceText: String
    public var currencyCode: String
    public var note: String

    public init(
        name: String = "",
        type: AccountType = .cash,
        openingBalanceText: String = "0",
        currencyCode: String = "CNY",
        note: String = ""
    ) {
        self.name = name
        self.type = type
        self.openingBalanceText = openingBalanceText
        self.currencyCode = currencyCode
        self.note = note
    }

    public var openingBalanceDecimal: Decimal {
        Decimal(string: openingBalanceText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    public static func from(summary: AccountSummary) -> AccountFormDraft {
        AccountFormDraft(
            name: summary.account.name,
            type: summary.account.type,
            openingBalanceText: "\(summary.account.openingBalance.amount)",
            currencyCode: summary.account.currencyCode,
            note: summary.account.note ?? ""
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
