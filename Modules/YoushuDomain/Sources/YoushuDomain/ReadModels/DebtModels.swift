import Foundation
import YoushuFoundation

/// 债务中心首页 + 列表快照（派生数据，非权威账本）。
public struct DebtListSnapshot: Equatable, Sendable {
    public var debts: [Debt]
    public var totalOutstanding: Money
    public var outstandingAvailability: FieldAvailability
    public var estimatedMonthlyRepayment: Money
    public var estimatedMonthlyRepaymentAvailability: FieldAvailability
    public var lastRepaymentDate: Date?
    public var lastRepaymentAmount: Money?
    public var nextPaymentDate: Date?
    public var nextPaymentAmount: Money?
    public var nextPaymentLabel: String?
    public var debtPressureScore: Int
    public var debtPressureLevel: DebtPressureLevel
    public var highCostDebts: [Debt]
    public var debtFreeEstimate: Date?

    public var isEmpty: Bool { debts.isEmpty }

    public var outstandingPresentation: DebtMoneyPresentation {
        DebtMoneyPresentation(amount: totalOutstanding, availability: outstandingAvailability)
    }

    public var estimatedMonthlyPresentation: DebtMoneyPresentation {
        DebtMoneyPresentation(
            amount: estimatedMonthlyRepayment,
            availability: estimatedMonthlyRepaymentAvailability
        )
    }

    public init(
        debts: [Debt] = [],
        totalOutstanding: Money = .zeroCNY,
        outstandingAvailability: FieldAvailability = .known,
        estimatedMonthlyRepayment: Money = .zeroCNY,
        estimatedMonthlyRepaymentAvailability: FieldAvailability = .known,
        lastRepaymentDate: Date? = nil,
        lastRepaymentAmount: Money? = nil,
        nextPaymentDate: Date? = nil,
        nextPaymentAmount: Money? = nil,
        nextPaymentLabel: String? = nil,
        debtPressureScore: Int = 0,
        debtPressureLevel: DebtPressureLevel = .low,
        highCostDebts: [Debt] = [],
        debtFreeEstimate: Date? = nil
    ) {
        self.debts = debts
        self.totalOutstanding = totalOutstanding
        self.outstandingAvailability = outstandingAvailability
        self.estimatedMonthlyRepayment = estimatedMonthlyRepayment
        self.estimatedMonthlyRepaymentAvailability = estimatedMonthlyRepaymentAvailability
        self.lastRepaymentDate = lastRepaymentDate
        self.lastRepaymentAmount = lastRepaymentAmount
        self.nextPaymentDate = nextPaymentDate
        self.nextPaymentAmount = nextPaymentAmount
        self.nextPaymentLabel = nextPaymentLabel
        self.debtPressureScore = debtPressureScore
        self.debtPressureLevel = debtPressureLevel
        self.highCostDebts = highCostDebts
        self.debtFreeEstimate = debtFreeEstimate
    }
}

public struct DebtDetailSnapshot: Equatable, Sendable, Identifiable {
    public var debt: Debt
    public var events: [DebtEvent]
    public var profileCompletenessPercent: Int

    public var id: UUID { debt.id }

    public init(debt: Debt, events: [DebtEvent] = []) {
        self.debt = debt
        self.events = events.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.createdAt > rhs.createdAt
        }
        self.profileCompletenessPercent = DebtProfileCompleteness.percentage(for: debt)
    }
}

public enum DebtListSort: String, CaseIterable, Sendable {
    case lender
    case type
    case status

    public var title: String {
        switch self {
        case .lender: return "债权方"
        case .type: return "类型"
        case .status: return "状态"
        }
    }
}

/// 渐进式建档：债权方必填。
/// `approximateBalance` 是已知的剩余总欠款；`nil` 表示总欠款未知（不得用本期应还顶替）。
/// 手动建档 UI 仍要求用户明确填写大致欠款。
public struct CreateDebtInput: Sendable, Equatable {
    public var lender: String
    public var approximateBalance: Decimal?
    public var currencyCode: String
    public var productName: String?
    public var debtType: DebtType
    public var originalAmount: Decimal?
    public var currentDue: Decimal?
    public var minimumDue: Decimal?
    public var installmentAmount: Decimal?
    public var paymentFrequency: PaymentFrequency
    public var dueDate: Date?
    public var remainingInstallments: Int?
    public var maturityDate: Date?
    public var interestRate: Decimal?
    public var fee: Decimal?
    public var note: String?
    public var status: DebtStatus
    public var source: DebtSource
    /// Import-local idempotency key. When set, reused to upsert the same Debt id.
    public var idempotencyKey: UUID?

    public init(
        lender: String,
        approximateBalance: Decimal?,
        currencyCode: String = "CNY",
        productName: String? = nil,
        debtType: DebtType = .other,
        originalAmount: Decimal? = nil,
        currentDue: Decimal? = nil,
        minimumDue: Decimal? = nil,
        installmentAmount: Decimal? = nil,
        paymentFrequency: PaymentFrequency = .unknown,
        dueDate: Date? = nil,
        remainingInstallments: Int? = nil,
        maturityDate: Date? = nil,
        interestRate: Decimal? = nil,
        fee: Decimal? = nil,
        note: String? = nil,
        status: DebtStatus = .active,
        source: DebtSource = .userInput,
        idempotencyKey: UUID? = nil
    ) {
        self.lender = lender
        self.approximateBalance = approximateBalance
        self.currencyCode = currencyCode.uppercased()
        self.productName = productName
        self.debtType = debtType
        self.originalAmount = originalAmount
        self.currentDue = currentDue
        self.minimumDue = minimumDue
        self.installmentAmount = installmentAmount
        self.paymentFrequency = paymentFrequency
        self.dueDate = dueDate
        self.remainingInstallments = remainingInstallments
        self.maturityDate = maturityDate
        self.interestRate = interestRate
        self.fee = fee
        self.note = note
        self.status = status
        self.source = source
        self.idempotencyKey = idempotencyKey
    }
}

public struct UpdateDebtInput: Sendable, Equatable {
    public var debtId: UUID
    public var lender: String
    public var approximateBalance: Decimal
    public var currencyCode: String
    public var productName: String?
    public var debtType: DebtType
    public var originalAmount: Decimal?
    public var currentDue: Decimal?
    public var minimumDue: Decimal?
    public var installmentAmount: Decimal?
    public var paymentFrequency: PaymentFrequency
    public var dueDate: Date?
    public var remainingInstallments: Int?
    public var maturityDate: Date?
    public var interestRate: Decimal?
    public var fee: Decimal?
    public var note: String?
    public var status: DebtStatus

    public init(
        debtId: UUID,
        lender: String,
        approximateBalance: Decimal,
        currencyCode: String = "CNY",
        productName: String? = nil,
        debtType: DebtType = .other,
        originalAmount: Decimal? = nil,
        currentDue: Decimal? = nil,
        minimumDue: Decimal? = nil,
        installmentAmount: Decimal? = nil,
        paymentFrequency: PaymentFrequency = .unknown,
        dueDate: Date? = nil,
        remainingInstallments: Int? = nil,
        maturityDate: Date? = nil,
        interestRate: Decimal? = nil,
        fee: Decimal? = nil,
        note: String? = nil,
        status: DebtStatus = .active
    ) {
        self.debtId = debtId
        self.lender = lender
        self.approximateBalance = approximateBalance
        self.currencyCode = currencyCode.uppercased()
        self.productName = productName
        self.debtType = debtType
        self.originalAmount = originalAmount
        self.currentDue = currentDue
        self.minimumDue = minimumDue
        self.installmentAmount = installmentAmount
        self.paymentFrequency = paymentFrequency
        self.dueDate = dueDate
        self.remainingInstallments = remainingInstallments
        self.maturityDate = maturityDate
        self.interestRate = interestRate
        self.fee = fee
        self.note = note
        self.status = status
    }
}

public struct RecordDebtRepaymentInput: Sendable, Equatable {
    public var debtId: UUID
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var note: String?
    public var accountId: UUID?

    public init(
        debtId: UUID,
        amount: Decimal,
        currencyCode: String = "CNY",
        date: Date = Date(),
        note: String? = nil,
        accountId: UUID? = nil
    ) {
        self.debtId = debtId
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.date = date
        self.note = note
        self.accountId = accountId
    }
}
