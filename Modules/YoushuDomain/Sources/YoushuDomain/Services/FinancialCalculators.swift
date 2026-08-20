import Foundation
import YoushuFoundation

/// Progressive profiling score for a debt record (0...1).
/// 不强制用户填满；仅反映已填写字段比例。
public enum DebtProfileCompleteness {
    private static let fieldCount = 12

    public static func score(
        lender: String?,
        productName: String?,
        debtType: DebtType,
        originalAmount: Money?,
        outstandingBalance: Money?,
        currentDue: Money?,
        minimumDue: Money?,
        installmentAmount: Money?,
        paymentFrequency: PaymentFrequency,
        dueDate: Date?,
        remainingInstallments: Int?,
        interestRate: Decimal?,
        status: DebtStatus
    ) -> Double {
        var filled = 0

        if let lender, !lender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { filled += 1 }
        if let productName, !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { filled += 1 }
        if debtType != .other { filled += 1 }
        if originalAmount != nil { filled += 1 }
        if outstandingBalance != nil { filled += 1 }
        if currentDue != nil { filled += 1 }
        if minimumDue != nil { filled += 1 }
        if installmentAmount != nil { filled += 1 }
        if paymentFrequency != .unknown { filled += 1 }
        if dueDate != nil { filled += 1 }
        if remainingInstallments != nil { filled += 1 }
        if interestRate != nil { filled += 1 }
        // status unknown still counts as filled when explicitly set via active/overdue/paidOff
        if status != .unknown { filled += 1 }

        // 12 base fields above but status is 13th conceptually — keep denominator stable at fieldCount+status handled
        let total = fieldCount + 1
        return Double(filled) / Double(total)
    }

    public static func score(for debt: Debt) -> Double {
        score(
            lender: debt.lender,
            productName: debt.productName,
            debtType: debt.debtType,
            originalAmount: debt.originalAmount,
            outstandingBalance: debt.outstandingBalance,
            currentDue: debt.currentDue,
            minimumDue: debt.minimumDue,
            installmentAmount: debt.installmentAmount,
            paymentFrequency: debt.paymentFrequency,
            dueDate: debt.dueDate,
            remainingInstallments: debt.remainingInstallments,
            interestRate: debt.interestRate,
            status: debt.status
        )
    }

    public static func percentage(for debt: Debt) -> Int {
        Int((score(for: debt) * 100).rounded())
    }
}

/// Deterministic debt balance helpers. Never delegate this to an LLM.
public enum DebtBalanceCalculator {
    /// Sum outstanding balances for active / overdue / unknown debts.
    public static func totalOutstanding(debts: [Debt]) -> Money {
        let relevant = debts.filter { $0.status == .active || $0.status == .overdue || $0.status == .unknown }
        guard let currency = relevant.compactMap({ $0.outstandingBalance?.currencyCode }).first else {
            return .zeroCNY
        }
        return relevant.reduce(Money(amount: 0, currencyCode: currency)) { partial, debt in
            guard let balance = debt.outstandingBalance else { return partial }
            precondition(balance.currencyCode == currency, "Mixed currencies not supported in MVP total")
            return partial + balance
        }
    }

    /// Apply ordered debt events onto a debt snapshot. Returns updated debt.
    ///
    /// Callers that already persist the latest balance on `Debt` must pass **only new** events
    /// (incremental). Passing the full history onto an already-updated snapshot double-counts repayments.
    public static func apply(events: [DebtEvent], to debt: Debt) -> Debt {
        var updated = debt
        let ordered = events.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.createdAt < rhs.createdAt
        }

        for event in ordered {
            switch event.type {
            case .created:
                if let amount = event.amount {
                    if updated.originalAmount == nil { updated.originalAmount = amount }
                    if updated.outstandingBalance == nil { updated.outstandingBalance = amount }
                    if updated.outstandingPrincipal == nil { updated.outstandingPrincipal = amount }
                }
                if updated.status == .unknown {
                    updated.status = .active
                }

            case .repayment:
                if let amount = event.amount {
                    let currency = amount.currencyCode
                    let balance = updated.outstandingBalance ?? Money(amount: 0, currencyCode: currency)
                    updated.outstandingBalance = maxMoney(balance - amount, currency: currency)
                    if let principal = updated.outstandingPrincipal {
                        updated.outstandingPrincipal = maxMoney(principal - amount, currency: principal.currencyCode)
                    }
                    if let due = updated.currentDue {
                        updated.currentDue = maxMoney(due - amount, currency: due.currencyCode)
                    }
                    if let remaining = updated.remainingInstallments, remaining > 0 {
                        updated.remainingInstallments = remaining - 1
                    }
                    if let bal = updated.outstandingBalance, bal.amount <= 0 {
                        updated.status = .paidOff
                        updated.outstandingBalance = Money(amount: 0, currencyCode: bal.currencyCode)
                        updated.outstandingPrincipal = Money(amount: 0, currencyCode: bal.currencyCode)
                        updated.currentDue = Money(amount: 0, currencyCode: bal.currencyCode)
                        updated.remainingInstallments = 0
                    }
                }

            case .interestChanged, .interestAccrued, .feeCharged:
                if let amount = event.amount {
                    let base = updated.outstandingBalance
                        ?? Money(amount: 0, currencyCode: amount.currencyCode)
                    updated.outstandingBalance = base + amount
                    if event.type == .interestChanged || event.type == .interestAccrued {
                        updated.estimatedInterest = amount
                    }
                    if event.type == .feeCharged {
                        updated.fee = amount
                    }
                }

            case .billUpdated:
                if let amount = event.amount {
                    updated.outstandingBalance = amount
                    updated.currentDue = amount
                }

            case .overdue:
                updated.status = .overdue

            case .installmentCompleted:
                updated.remainingInstallments = 0
                if let bal = updated.outstandingBalance, bal.amount <= 0 {
                    updated.status = .paidOff
                }

            case .manualEdit, .adjustment:
                if let amount = event.amount {
                    updated.outstandingBalance = amount
                    if updated.outstandingPrincipal == nil {
                        updated.outstandingPrincipal = amount
                    }
                }

            case .statusChanged, .scheduleUpdated:
                break
            }
        }

        updated.profileCompleteness = DebtProfileCompleteness.score(for: updated)
        updated.updatedAt = Date()
        return updated
    }

    private static func maxMoney(_ value: Money, currency: String) -> Money {
        Money(amount: max(value.amount, 0), currencyCode: currency)
    }
}
