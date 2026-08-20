import Foundation
import YoushuDesignSystem
import YoushuDomain

@Observable
@MainActor
public final class DebtViewModel {
    public var phase: YSPagePhase<DebtListSnapshot> = .loading
    public var detail: DebtDetailSnapshot?
    public var selectedDebtId: UUID?
    public var isPresentingForm = false
    public var isPresentingRepayment = false
    public var isPresentingScanner = false
    public var editingDebt: Debt?
    public var pendingDeleteDebt: Debt?
    public var formError: String?
    public var isSaving = false

    public var sort: DebtListSort = .lender
    public var typeFilter: DebtType?
    public var statusFilter: DebtStatus?
    public var lenderQuery = ""

    public var accounts: [Account] = []

    private let provider: any DebtListProviding
    private let debtService: any DebtManaging
    private let detailProvider: any DebtDetailProviding
    private let accountsRepository: any AccountRepository
    private let session: AppSession
    private let onDataChanged: (@Sendable () async -> Void)?

    public init(
        provider: any DebtListProviding,
        debtService: any DebtManaging,
        detailProvider: any DebtDetailProviding,
        accounts: any AccountRepository,
        session: AppSession,
        onDataChanged: (@Sendable () async -> Void)? = nil
    ) {
        self.provider = provider
        self.debtService = debtService
        self.detailProvider = detailProvider
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
            accounts = try await accountsRepository.fetchAll(userId: userId).filter { !$0.isArchived }
            let snapshot = try await provider.loadSnapshot(userId: userId)
            phase = snapshot.isEmpty ? .empty(Self.emptyConfig) : .content(snapshot)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public func filteredDebts(from snapshot: DebtListSnapshot) -> [Debt] {
        DebtListService.filtered(
            snapshot.debts,
            sort: sort,
            typeFilter: typeFilter,
            statusFilter: statusFilter,
            lenderQuery: lenderQuery.isEmpty ? nil : lenderQuery
        )
    }

    public func openDetail(_ debt: Debt) {
        selectedDebtId = debt.id
    }

    public func loadDetail(debtId: UUID) async {
        guard let userId = session.currentUserId else { return }
        do {
            detail = try await detailProvider.loadDetail(debtId: debtId, userId: userId)
        } catch {
            formError = error.localizedDescription
        }
    }

    public func presentCreate() {
        editingDebt = nil
        formError = nil
        isPresentingForm = true
    }

    public func presentScanner() {
        formError = nil
        isPresentingScanner = true
    }

    public func presentEdit(_ debt: Debt) {
        editingDebt = debt
        formError = nil
        isPresentingForm = true
    }

    public func presentRepayment() {
        formError = nil
        isPresentingRepayment = true
    }

    public func confirmDelete(_ debt: Debt) {
        pendingDeleteDebt = debt
    }

    public func deleteConfirmed() async {
        guard let debt = pendingDeleteDebt, let userId = session.currentUserId else { return }
        pendingDeleteDebt = nil
        do {
            try await debtService.delete(debtId: debt.id, userId: userId)
            selectedDebtId = nil
            detail = nil
            await reloadAll()
        } catch {
            formError = error.localizedDescription
        }
    }

    public func saveForm(_ draft: DebtFormDraft) async -> Bool {
        guard let userId = session.currentUserId else {
            formError = "尚未完成账户初始化"
            return false
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }

        do {
            if let editingDebt {
                _ = try await debtService.update(
                    UpdateDebtInput(
                        debtId: editingDebt.id,
                        lender: draft.lender,
                        approximateBalance: draft.balanceDecimal,
                        productName: draft.productName.isEmpty ? nil : draft.productName,
                        debtType: draft.debtType,
                        originalAmount: draft.originalAmountDecimal,
                        currentDue: draft.currentDueDecimal,
                        minimumDue: draft.minimumDueDecimal,
                        installmentAmount: draft.installmentDecimal,
                        paymentFrequency: draft.paymentFrequency,
                        dueDate: draft.dueDate,
                        remainingInstallments: draft.remainingInstallmentsValue,
                        maturityDate: draft.maturityDate,
                        interestRate: draft.interestRateDecimal,
                        fee: draft.feeDecimal,
                        note: draft.note.isEmpty ? nil : draft.note,
                        status: draft.status
                    ),
                    userId: userId
                )
            } else {
                _ = try await debtService.create(
                    CreateDebtInput(
                        lender: draft.lender,
                        approximateBalance: draft.balanceDecimal,
                        productName: draft.productName.isEmpty ? nil : draft.productName,
                        debtType: draft.debtType,
                        originalAmount: draft.originalAmountDecimal,
                        currentDue: draft.currentDueDecimal,
                        minimumDue: draft.minimumDueDecimal,
                        installmentAmount: draft.installmentDecimal,
                        paymentFrequency: draft.paymentFrequency,
                        dueDate: draft.dueDate,
                        remainingInstallments: draft.remainingInstallmentsValue,
                        maturityDate: draft.maturityDate,
                        interestRate: draft.interestRateDecimal,
                        fee: draft.feeDecimal,
                        note: draft.note.isEmpty ? nil : draft.note,
                        status: draft.status
                    ),
                    userId: userId
                )
            }
            isPresentingForm = false
            editingDebt = nil
            await reloadAll()
            if let id = selectedDebtId {
                await loadDetail(debtId: id)
            }
            return true
        } catch {
            formError = error.localizedDescription
            return false
        }
    }

    public func saveRepayment(_ draft: DebtRepaymentDraft) async -> Bool {
        guard let userId = session.currentUserId, let debtId = selectedDebtId ?? detail?.id else {
            formError = "未选择债务"
            return false
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }

        do {
            _ = try await debtService.recordRepayment(
                RecordDebtRepaymentInput(
                    debtId: debtId,
                    amount: draft.amountDecimal,
                    date: draft.date,
                    note: draft.note.isEmpty ? nil : draft.note,
                    accountId: draft.accountId
                ),
                userId: userId
            )
            isPresentingRepayment = false
            await reloadAll()
            await loadDetail(debtId: debtId)
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
        icon: "creditcard",
        title: "搞清楚你到底欠多少钱",
        message: "批量上传账单截图，AI 帮你发现债务；也可以手动添加。",
        actionTitle: "开始扫描我的债务"
    )
}

public struct DebtFormDraft: Equatable {
    public var lender: String
    public var balanceText: String
    public var productName: String
    public var debtType: DebtType
    public var originalAmountText: String
    public var currentDueText: String
    public var minimumDueText: String
    public var installmentText: String
    public var paymentFrequency: PaymentFrequency
    public var dueDate: Date?
    public var includeDueDate: Bool
    public var remainingInstallmentsText: String
    public var maturityDate: Date?
    public var includeMaturityDate: Bool
    public var interestRateText: String
    public var feeText: String
    public var note: String
    public var status: DebtStatus

    public init(
        lender: String = "",
        balanceText: String = "",
        productName: String = "",
        debtType: DebtType = .creditCard,
        originalAmountText: String = "",
        currentDueText: String = "",
        minimumDueText: String = "",
        installmentText: String = "",
        paymentFrequency: PaymentFrequency = .unknown,
        dueDate: Date? = nil,
        includeDueDate: Bool = false,
        remainingInstallmentsText: String = "",
        maturityDate: Date? = nil,
        includeMaturityDate: Bool = false,
        interestRateText: String = "",
        feeText: String = "",
        note: String = "",
        status: DebtStatus = .active
    ) {
        self.lender = lender
        self.balanceText = balanceText
        self.productName = productName
        self.debtType = debtType
        self.originalAmountText = originalAmountText
        self.currentDueText = currentDueText
        self.minimumDueText = minimumDueText
        self.installmentText = installmentText
        self.paymentFrequency = paymentFrequency
        self.dueDate = dueDate
        self.includeDueDate = includeDueDate
        self.remainingInstallmentsText = remainingInstallmentsText
        self.maturityDate = maturityDate
        self.includeMaturityDate = includeMaturityDate
        self.interestRateText = interestRateText
        self.feeText = feeText
        self.note = note
        self.status = status
    }

    public static func from(_ debt: Debt) -> DebtFormDraft {
        DebtFormDraft(
            lender: debt.lender ?? "",
            balanceText: debt.outstandingBalance.map { "\($0.amount)" } ?? "",
            productName: debt.productName ?? "",
            debtType: DebtType.mvpCases.contains(debt.debtType) ? debt.debtType : .bankLoan,
            originalAmountText: debt.originalAmount.map { "\($0.amount)" } ?? "",
            currentDueText: debt.currentDue.map { "\($0.amount)" } ?? "",
            minimumDueText: debt.minimumDue.map { "\($0.amount)" } ?? "",
            installmentText: debt.installmentAmount.map { "\($0.amount)" } ?? "",
            paymentFrequency: debt.paymentFrequency,
            dueDate: debt.dueDate,
            includeDueDate: debt.dueDate != nil,
            remainingInstallmentsText: debt.remainingInstallments.map(String.init) ?? "",
            maturityDate: debt.maturityDate,
            includeMaturityDate: debt.maturityDate != nil,
            interestRateText: debt.interestRate.map { "\($0)" } ?? "",
            feeText: debt.fee.map { "\($0.amount)" } ?? "",
            note: debt.note ?? "",
            status: debt.status == .unknown ? .active : debt.status
        )
    }

    public var balanceDecimal: Decimal {
        Decimal(string: balanceText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    public var originalAmountDecimal: Decimal? { optionalDecimal(originalAmountText) }
    public var currentDueDecimal: Decimal? { optionalDecimal(currentDueText) }
    public var minimumDueDecimal: Decimal? { optionalDecimal(minimumDueText) }
    public var installmentDecimal: Decimal? { optionalDecimal(installmentText) }
    public var feeDecimal: Decimal? { optionalDecimal(feeText) }
    public var interestRateDecimal: Decimal? { optionalDecimal(interestRateText) }
    public var remainingInstallmentsValue: Int? {
        Int(remainingInstallmentsText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func optionalDecimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed.replacingOccurrences(of: ",", with: ""))
    }
}

public struct DebtRepaymentDraft: Equatable {
    public var amountText: String
    public var date: Date
    public var note: String
    public var accountId: UUID?

    public init(amountText: String = "", date: Date = Date(), note: String = "", accountId: UUID? = nil) {
        self.amountText = amountText
        self.date = date
        self.note = note
        self.accountId = accountId
    }

    public var amountDecimal: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}
