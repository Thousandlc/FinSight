import Foundation
import YoushuFoundation

/// 债务 CRUD / 还款 / 事件。金额变化经 DebtEvent 回放，AI 不参与。
public struct DebtService: DebtManaging, DebtDetailProviding {
    private let debts: any DebtRepository
    private let events: any DebtEventRepository
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository
    private let establishment: DebtInventoryEstablishmentService?

    public init(
        debts: any DebtRepository,
        events: any DebtEventRepository,
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        users: (any UserRepository)? = nil
    ) {
        self.debts = debts
        self.events = events
        self.accounts = accounts
        self.transactions = transactions
        self.establishment = users.map { DebtInventoryEstablishmentService(users: $0) }
    }

    public func create(_ input: CreateDebtInput, userId: UUID) async throws -> Debt {
        let lender = try requireLender(input.lender)
        if let amount = input.approximateBalance, amount < 0 {
            throw DomainError.validationFailed("欠款金额不能为负")
        }

        let debtId = input.idempotencyKey ?? UUID()
        if let existing = try await debts.fetch(id: debtId) {
            guard existing.userId == userId else { throw DomainError.userMismatch }
            if try await hasCreatedEvent(debtId: debtId) {
                return existing
            }
        }

        let money = input.approximateBalance.map { Money(amount: $0, currencyCode: input.currencyCode) }
        var debt = Debt(
            id: debtId,
            userId: userId,
            lender: lender,
            productName: normalized(input.productName),
            debtType: input.debtType,
            originalAmount: input.originalAmount.map { Money(amount: $0, currencyCode: input.currencyCode) } ?? money,
            outstandingPrincipal: money,
            outstandingBalance: money,
            currentDue: moneyOptional(input.currentDue, currency: input.currencyCode),
            minimumDue: moneyOptional(input.minimumDue, currency: input.currencyCode),
            installmentAmount: moneyOptional(input.installmentAmount, currency: input.currencyCode),
            paymentFrequency: input.paymentFrequency,
            dueDate: input.dueDate,
            remainingInstallments: input.remainingInstallments,
            maturityDate: input.maturityDate,
            interestRate: input.interestRate,
            fee: moneyOptional(input.fee, currency: input.currencyCode),
            status: input.status == .unknown ? .active : input.status,
            source: input.source,
            note: normalized(input.note)
        )
        debt.profileCompleteness = DebtProfileCompleteness.score(for: debt)
        try await debts.upsert(debt)

        if try await !hasCreatedEvent(debtId: debt.id) {
            let created = DebtEvent(
                id: Self.importCreatedEventId(for: debt.id),
                debtId: debt.id,
                userId: userId,
                type: .created,
                amount: money,
                note: "创建债务"
            )
            try await events.upsert(created)
        }
        if let establishment {
            try await establishment.markPartialFromFirstDebt(userId: userId)
        }
        return debt
    }

    public func update(_ input: UpdateDebtInput, userId: UUID) async throws -> Debt {
        let lender = try requireLender(input.lender)
        guard input.approximateBalance >= 0 else {
            throw DomainError.validationFailed("欠款金额不能为负")
        }
        guard var existing = try await debts.fetch(id: input.debtId) else {
            throw DomainError.notFound(entity: "Debt", id: input.debtId)
        }
        guard existing.userId == userId else { throw DomainError.userMismatch }

        let money = Money(amount: input.approximateBalance, currencyCode: input.currencyCode)
        existing.lender = lender
        existing.productName = normalized(input.productName)
        existing.debtType = input.debtType
        existing.originalAmount = input.originalAmount.map { Money(amount: $0, currencyCode: input.currencyCode) } ?? existing.originalAmount
        existing.outstandingBalance = money
        existing.outstandingPrincipal = money
        existing.currentDue = moneyOptional(input.currentDue, currency: input.currencyCode)
        existing.minimumDue = moneyOptional(input.minimumDue, currency: input.currencyCode)
        existing.installmentAmount = moneyOptional(input.installmentAmount, currency: input.currencyCode)
        existing.paymentFrequency = input.paymentFrequency
        existing.dueDate = input.dueDate
        existing.remainingInstallments = input.remainingInstallments
        existing.maturityDate = input.maturityDate
        existing.interestRate = input.interestRate
        existing.fee = moneyOptional(input.fee, currency: input.currencyCode)
        existing.note = normalized(input.note)
        existing.status = input.status
        existing.profileCompleteness = DebtProfileCompleteness.score(for: existing)
        existing.updatedAt = Date()
        try await debts.upsert(existing)

        let edit = DebtEvent(
            debtId: existing.id,
            userId: userId,
            type: .manualEdit,
            amount: money,
            note: "手动修改债务"
        )
        try await events.upsert(edit)
        return existing
    }

    public func delete(debtId: UUID, userId: UUID) async throws {
        guard let existing = try await debts.fetch(id: debtId) else {
            throw DomainError.notFound(entity: "Debt", id: debtId)
        }
        guard existing.userId == userId else { throw DomainError.userMismatch }
        try await debts.delete(id: debtId)
    }

    public func recordRepayment(_ input: RecordDebtRepaymentInput, userId: UUID) async throws -> Debt {
        guard input.amount > 0 else {
            throw DomainError.validationFailed("还款金额必须大于 0")
        }
        guard var debt = try await debts.fetch(id: input.debtId) else {
            throw DomainError.notFound(entity: "Debt", id: input.debtId)
        }
        guard debt.userId == userId else { throw DomainError.userMismatch }

        let money = Money(amount: input.amount, currencyCode: input.currencyCode)
        var relatedTxId: UUID?

        if let accountId = input.accountId {
            try await requireAccount(accountId, userId: userId)
            let tx = Transaction(
                userId: userId,
                accountId: accountId,
                amount: money,
                date: input.date,
                merchant: debt.lender,
                category: "生活",
                transactionType: .repayment,
                note: normalized(input.note),
                relatedDebtId: debt.id,
                source: .manual
            )
            try await transactions.upsert(tx)
            relatedTxId = tx.id
        }

        let event = DebtEvent(
            debtId: debt.id,
            userId: userId,
            type: .repayment,
            date: input.date,
            amount: money,
            relatedTransactionId: relatedTxId,
            note: normalized(input.note) ?? "还款"
        )
        try await events.upsert(event)

        // 仅增量应用本次还款事件；Debt 上已是最新余额，全量回放会重复扣减。
        debt = DebtBalanceCalculator.apply(events: [event], to: debt)
        try await debts.upsert(debt)
        return debt
    }

    public func loadDetail(debtId: UUID, userId: UUID) async throws -> DebtDetailSnapshot {
        guard let debt = try await debts.fetch(id: debtId), debt.userId == userId else {
            throw DomainError.notFound(entity: "Debt", id: debtId)
        }
        let events = try await events.fetchAll(debtId: debtId)
        return DebtDetailSnapshot(debt: debt, events: events)
    }

    // MARK: - Private

    private func requireLender(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainError.validationFailed("请填写债权方")
        }
        return trimmed
    }

    private func requireAccount(_ accountId: UUID, userId: UUID) async throws {
        guard let account = try await accounts.fetch(id: accountId), account.userId == userId else {
            throw DomainError.invalidRelation("Account not found for user")
        }
    }

    private func moneyOptional(_ amount: Decimal?, currency: String) -> Money? {
        guard let amount else { return nil }
        return Money(amount: amount, currencyCode: currency)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func hasCreatedEvent(debtId: UUID) async throws -> Bool {
        try await events.fetchAll(debtId: debtId).contains { $0.type == .created }
    }

    /// Stable id for import-local `.created` events keyed by Debt id.
    static func importCreatedEventId(for debtId: UUID) -> UUID {
        var bytes = debtId.uuid
        bytes.15 ^= 0xA5
        return UUID(uuid: bytes)
    }
}

/// 债务中心列表与汇总。
public struct DebtListService: DebtListProviding, DebtDetailProviding {
    private let debts: any DebtRepository
    private let events: any DebtEventRepository

    public init(debts: any DebtRepository, events: any DebtEventRepository) {
        self.debts = debts
        self.events = events
    }

    public func loadSnapshot(userId: UUID) async throws -> DebtListSnapshot {
        let list = try await debts.fetchAll(userId: userId)
            .sorted { ($0.lender ?? "") < ($1.lender ?? "") }

        var allEvents: [DebtEvent] = []
        for debt in list {
            let debtEvents = try await events.fetchAll(debtId: debt.id)
            allEvents.append(contentsOf: debtEvents)
        }

        let total = DebtCenterCalculator.totalDebt(debts: list)
        let outstanding = DebtMoneyPresentation.knownOutstandingTotal(from: list, computed: total)
        let monthly = DebtMoneyPresentation.estimatedMonthly(from: list)
        let last = DebtCenterCalculator.lastRepayment(events: allEvents)
        let next = DebtCenterCalculator.nextPayment(debts: list)
        let pressure = DebtCenterCalculator.debtPressureScore(
            debts: list,
            monthlyRepayment: monthly.isComplete ? monthly.knownAmount : nil
        )
        let highCost = DebtCenterCalculator.highCostDebts(debts: list)
        let freeDate = DebtCenterCalculator.debtFreeEstimate(debts: list)

        return DebtListSnapshot(
            debts: list,
            totalOutstanding: outstanding.knownAmount ?? .zeroCNY,
            outstandingAvailability: outstanding.availability,
            estimatedMonthlyRepayment: monthly.knownAmount ?? .zeroCNY,
            estimatedMonthlyRepaymentAvailability: monthly.availability,
            lastRepaymentDate: last?.date,
            lastRepaymentAmount: last?.amount,
            nextPaymentDate: next?.date,
            nextPaymentAmount: next?.amount,
            nextPaymentLabel: next.map { $0.debt.lender ?? $0.debt.productName ?? "债务" },
            debtPressureScore: pressure,
            debtPressureLevel: DebtCenterCalculator.debtPressureLevel(score: pressure),
            highCostDebts: highCost,
            debtFreeEstimate: freeDate
        )
    }

    public func loadDetail(debtId: UUID, userId: UUID) async throws -> DebtDetailSnapshot {
        guard let debt = try await debts.fetch(id: debtId), debt.userId == userId else {
            throw DomainError.notFound(entity: "Debt", id: debtId)
        }
        let debtEvents = try await events.fetchAll(debtId: debtId)
        return DebtDetailSnapshot(debt: debt, events: debtEvents)
    }

    public static func filtered(
        _ debts: [Debt],
        sort: DebtListSort,
        typeFilter: DebtType? = nil,
        statusFilter: DebtStatus? = nil,
        lenderQuery: String? = nil
    ) -> [Debt] {
        var result = debts
        if let typeFilter {
            result = result.filter { normalizedType($0.debtType) == normalizedType(typeFilter) }
        }
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        if let lenderQuery {
            let q = lenderQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty {
                result = result.filter { ($0.lender ?? "").localizedCaseInsensitiveContains(q) }
            }
        }

        switch sort {
        case .lender:
            return result.sorted { ($0.lender ?? "") < ($1.lender ?? "") }
        case .type:
            return result.sorted { $0.debtType.displayName < $1.debtType.displayName }
        case .status:
            return result.sorted { $0.status.displayName < $1.status.displayName }
        }
    }

    private static func normalizedType(_ type: DebtType) -> DebtType {
        switch type {
        case .mortgage, .carLoan, .studentLoan, .bankLoan: return .bankLoan
        default: return type
        }
    }
}
