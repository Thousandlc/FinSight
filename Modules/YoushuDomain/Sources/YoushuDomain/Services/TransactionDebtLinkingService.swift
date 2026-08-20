import Foundation
import YoushuFoundation

/// Transaction → DebtEvent → Debt 关联编排。
/// 匹配可参考 AI 提示，但 Debt 更新仅经 DebtEvent 确定性回放。
public struct TransactionDebtLinkingService: TransactionDebtLinking {
    private let debts: any DebtRepository
    private let events: any DebtEventRepository
    private let transactions: any TransactionRepository
    private let accounts: any AccountRepository
    private let pendingLinkRepo: any PendingDebtLinkRepository
    private let suspectedDebtRepo: any SuspectedDebtRepository
    private let debtManager: any DebtManaging
    private let matchAssistant: any DebtMatchAssisting

    public init(
        debts: any DebtRepository,
        events: any DebtEventRepository,
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        pendingLinks: any PendingDebtLinkRepository,
        suspectedDebts: any SuspectedDebtRepository,
        debtManager: any DebtManaging,
        matchAssistant: any DebtMatchAssisting = NoOpDebtMatchAssistant()
    ) {
        self.debts = debts
        self.events = events
        self.transactions = transactions
        self.accounts = accounts
        self.pendingLinkRepo = pendingLinks
        self.suspectedDebtRepo = suspectedDebts
        self.debtManager = debtManager
        self.matchAssistant = matchAssistant
    }

    public func processNewTransaction(_ transaction: Transaction, userId: UUID) async throws -> DebtLinkOutcome {
        guard transaction.userId == userId else { throw DomainError.userMismatch }
        if transaction.relatedDebtId != nil {
            return .skipped(reason: "交易已关联债务")
        }

        let debtList = try await debts.fetchAll(userId: userId)
        let accountList = try await accounts.fetchAll(userId: userId)
        let history = try await transactions.fetchAll(userId: userId)
        let openIds = debtList.filter { DebtCenterCalculator.isOpen($0) }.map(\.id)
        let aiHint = try? await matchAssistant.suggestDebtId(
            for: transaction,
            candidateDebtIds: openIds
        )

        let match = DebtMatcher.match(
            transaction: transaction,
            context: DebtMatcher.Context(
                debts: debtList,
                accounts: accountList,
                historicalTransactions: history.filter { $0.id != transaction.id },
                aiSuggestedDebtId: aiHint
            )
        )

        switch match.status {
        case .matched:
            guard let debtId = match.matchedDebtId else {
                return .unmatched(reason: match.reason)
            }
            let linked = try await applyRepaymentLink(
                transaction: transaction,
                debtId: debtId,
                userId: userId,
                note: "自动匹配还款：\(match.reason)"
            )
            return .autoLinked(debtId: linked.debt.id, eventId: linked.event.id)

        case .pendingConfirmation, .ambiguous:
            let pending = PendingDebtLink(
                userId: userId,
                transactionId: transaction.id,
                suggestedDebtId: match.matchedDebtId,
                candidateDebtIds: match.candidateDebtIds,
                confidence: match.confidence,
                reason: match.reason
            )
            try await pendingLinkRepo.upsert(pending)
            return .pendingConfirmation(pending)

        case .unmatched:
            return .unmatched(reason: match.reason)
        }
    }

    public func confirmPendingLink(pendingId: UUID, debtId: UUID, userId: UUID) async throws -> Debt {
        guard var pending = try await pendingLinkRepo.fetch(id: pendingId) else {
            throw DomainError.notFound(entity: "PendingDebtLink", id: pendingId)
        }
        guard pending.userId == userId else { throw DomainError.userMismatch }
        guard pending.status == .pending else {
            throw DomainError.validationFailed("该待确认关联已处理")
        }
        guard let tx = try await transactions.fetch(id: pending.transactionId) else {
            throw DomainError.notFound(entity: "Transaction", id: pending.transactionId)
        }

        let linked = try await applyRepaymentLink(
            transaction: tx,
            debtId: debtId,
            userId: userId,
            note: "用户确认匹配：\(pending.reason)"
        )

        pending.status = .confirmed
        pending.suggestedDebtId = debtId
        pending.updatedAt = Date()
        try await pendingLinkRepo.upsert(pending)
        return linked.debt
    }

    public func ignorePendingLink(pendingId: UUID, userId: UUID) async throws {
        guard var pending = try await pendingLinkRepo.fetch(id: pendingId) else {
            throw DomainError.notFound(entity: "PendingDebtLink", id: pendingId)
        }
        guard pending.userId == userId else { throw DomainError.userMismatch }
        pending.status = .ignored
        pending.updatedAt = Date()
        try await pendingLinkRepo.upsert(pending)
    }

    public func refreshSuspectedDebts(userId: UUID) async throws -> [SuspectedDebt] {
        let txs = try await transactions.fetchAll(userId: userId)
        let debtList = try await debts.fetchAll(userId: userId)
        let existing = try await suspectedDebtRepo.fetchAll(userId: userId)
        let ignoredKeys = Set(
            existing
                .filter { $0.status == .ignored || $0.status == .confirmed }
                .map { SuspectedDebtDetector.patternKey(merchant: $0.merchant, amount: $0.amount) }
        )
        let pendingKeys = Set(
            existing
                .filter { $0.status == .pending }
                .map { SuspectedDebtDetector.patternKey(merchant: $0.merchant, amount: $0.amount) }
        )

        let detected = SuspectedDebtDetector.detect(
            userId: userId,
            transactions: txs,
            existingDebts: debtList,
            ignoredKeys: ignoredKeys
        )

        var saved: [SuspectedDebt] = []
        for item in detected {
            let key = SuspectedDebtDetector.patternKey(merchant: item.merchant, amount: item.amount)
            if pendingKeys.contains(key) {
                if let old = existing.first(where: {
                    $0.status == .pending
                        && SuspectedDebtDetector.patternKey(merchant: $0.merchant, amount: $0.amount) == key
                }) {
                    var updated = old
                    updated.occurrenceCount = item.occurrenceCount
                    updated.sampleTransactionIds = item.sampleTransactionIds
                    updated.reason = item.reason
                    updated.dayOfMonth = item.dayOfMonth
                    updated.updatedAt = Date()
                    try await suspectedDebtRepo.upsert(updated)
                    saved.append(updated)
                }
                continue
            }
            try await suspectedDebtRepo.upsert(item)
            saved.append(item)
        }
        return try await suspectedDebtRepo.fetchPending(userId: userId)
    }

    public func confirmSuspectedDebt(suspectedId: UUID, userId: UUID) async throws -> Debt {
        guard var suspected = try await suspectedDebtRepo.fetch(id: suspectedId) else {
            throw DomainError.notFound(entity: "SuspectedDebt", id: suspectedId)
        }
        guard suspected.userId == userId else { throw DomainError.userMismatch }
        guard suspected.status == .pending else {
            throw DomainError.validationFailed("该疑似债务已处理")
        }

        let debt = try await debtManager.create(
            CreateDebtInput(
                lender: suspected.merchant,
                approximateBalance: suspected.amount.amount,
                currencyCode: suspected.amount.currencyCode,
                productName: "疑似分期/贷款",
                debtType: .consumerLoan,
                installmentAmount: suspected.amount.amount,
                paymentFrequency: .monthly,
                dueDate: nextDueDate(day: suspected.dayOfMonth),
                note: suspected.reason,
                status: .active,
                source: .transactionInference
            ),
            userId: userId
        )

        // 样本交易仅做溯源关联，不回放为还款事件（避免把历史已还金额再扣一次）。
        for txId in suspected.sampleTransactionIds {
            guard var tx = try await transactions.fetch(id: txId), tx.relatedDebtId == nil else { continue }
            tx.relatedDebtId = debt.id
            tx.updatedAt = Date()
            try await transactions.upsert(tx)
        }

        suspected.status = .confirmed
        suspected.updatedAt = Date()
        try await suspectedDebtRepo.upsert(suspected)
        return debt
    }

    public func ignoreSuspectedDebt(suspectedId: UUID, userId: UUID) async throws {
        guard var suspected = try await suspectedDebtRepo.fetch(id: suspectedId) else {
            throw DomainError.notFound(entity: "SuspectedDebt", id: suspectedId)
        }
        guard suspected.userId == userId else { throw DomainError.userMismatch }
        suspected.status = .ignored
        suspected.updatedAt = Date()
        try await suspectedDebtRepo.upsert(suspected)
    }

    public func pendingLinks(userId: UUID) async throws -> [PendingDebtLink] {
        try await pendingLinkRepo.fetchPending(userId: userId)
    }

    // MARK: - Private

    private func applyRepaymentLink(
        transaction: Transaction,
        debtId: UUID,
        userId: UUID,
        note: String
    ) async throws -> (debt: Debt, event: DebtEvent) {
        guard var debt = try await debts.fetch(id: debtId) else {
            throw DomainError.notFound(entity: "Debt", id: debtId)
        }
        guard debt.userId == userId else { throw DomainError.userMismatch }

        // 已存在同一交易的还款事件则幂等返回（不重放全部事件，避免重复扣减）
        let existingEvents = try await events.fetchAll(debtId: debtId)
        if let existing = existingEvents.first(where: {
            $0.type == .repayment && $0.relatedTransactionId == transaction.id
        }) {
            return (debt, existing)
        }

        let event = DebtEvent(
            debtId: debtId,
            userId: userId,
            type: .repayment,
            date: transaction.date,
            amount: transaction.amount,
            relatedTransactionId: transaction.id,
            note: note
        )
        try await events.upsert(event)

        // 增量应用新事件到当前 Debt 快照（全量回放会把历史还款叠扣到已更新余额上）
        debt = DebtBalanceCalculator.apply(events: [event], to: debt)
        try await debts.upsert(debt)

        var tx = transaction
        tx.relatedDebtId = debtId
        if tx.transactionType == .expense {
            // 保持事实类型；关联即可。不强制改写为 repayment，避免破坏账单分类。
        }
        tx.updatedAt = Date()
        try await transactions.upsert(tx)

        return (debt, event)
    }

    private func nextDueDate(day: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var comps = calendar.dateComponents([.year, .month], from: now)
        comps.day = min(max(day, 1), 28)
        if let thisMonth = calendar.date(from: comps), thisMonth >= now {
            return thisMonth
        }
        let next = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        var nextComps = calendar.dateComponents([.year, .month], from: next)
        nextComps.day = min(max(day, 1), 28)
        return calendar.date(from: nextComps) ?? next
    }
}
