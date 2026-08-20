import Foundation
import YoushuFoundation

public struct Debt: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID

    // Subject
    public var lender: String?
    public var productName: String?
    public var debtType: DebtType

    // Amounts (facts / tracked balances updated via DebtEvents, not LLM)
    public var originalAmount: Money?
    public var outstandingPrincipal: Money?
    public var outstandingBalance: Money?
    public var currentDue: Money?
    public var minimumDue: Money?

    // Repayment
    public var installmentAmount: Money?
    public var paymentFrequency: PaymentFrequency
    public var dueDate: Date?
    public var remainingInstallments: Int?
    public var maturityDate: Date?

    // Cost
    public var interestRate: Decimal?
    public var fee: Money?
    public var estimatedInterest: Money?

    // Status & provenance
    public var status: DebtStatus
    public var source: DebtSource
    /// 0...1 progressive profiling score. Recalculate via DebtProfileCompleteness.
    public var profileCompleteness: Double

    public var linkedAccountId: UUID?
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        lender: String? = nil,
        productName: String? = nil,
        debtType: DebtType = .other,
        originalAmount: Money? = nil,
        outstandingPrincipal: Money? = nil,
        outstandingBalance: Money? = nil,
        currentDue: Money? = nil,
        minimumDue: Money? = nil,
        installmentAmount: Money? = nil,
        paymentFrequency: PaymentFrequency = .unknown,
        dueDate: Date? = nil,
        remainingInstallments: Int? = nil,
        maturityDate: Date? = nil,
        interestRate: Decimal? = nil,
        fee: Money? = nil,
        estimatedInterest: Money? = nil,
        status: DebtStatus = .unknown,
        source: DebtSource = .userInput,
        profileCompleteness: Double? = nil,
        linkedAccountId: UUID? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.lender = lender
        self.productName = productName
        self.debtType = debtType
        self.originalAmount = originalAmount
        self.outstandingPrincipal = outstandingPrincipal
        self.outstandingBalance = outstandingBalance
        self.currentDue = currentDue
        self.minimumDue = minimumDue
        self.installmentAmount = installmentAmount
        self.paymentFrequency = paymentFrequency
        self.dueDate = dueDate
        self.remainingInstallments = remainingInstallments
        self.maturityDate = maturityDate
        self.interestRate = interestRate
        self.fee = fee
        self.estimatedInterest = estimatedInterest
        self.status = status
        self.source = source
        self.linkedAccountId = linkedAccountId
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.profileCompleteness = profileCompleteness ?? DebtProfileCompleteness.score(
            lender: lender,
            productName: productName,
            debtType: debtType,
            originalAmount: originalAmount,
            outstandingBalance: outstandingBalance,
            currentDue: currentDue,
            minimumDue: minimumDue,
            installmentAmount: installmentAmount,
            paymentFrequency: paymentFrequency,
            dueDate: dueDate,
            remainingInstallments: remainingInstallments,
            interestRate: interestRate,
            status: status
        )
    }
}

public struct DebtEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var debtId: UUID
    public var userId: UUID
    public var type: DebtEventType
    public var date: Date
    public var amount: Money?
    public var relatedTransactionId: UUID?
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        debtId: UUID,
        userId: UUID,
        type: DebtEventType,
        date: Date = Date(),
        amount: Money? = nil,
        relatedTransactionId: UUID? = nil,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.debtId = debtId
        self.userId = userId
        self.type = type
        self.date = date
        self.amount = amount
        self.relatedTransactionId = relatedTransactionId
        self.note = note
        self.createdAt = createdAt
    }
}

public struct RepaymentPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var debtId: UUID
    public var userId: UUID
    public var installmentAmount: Money
    public var frequency: PaymentFrequency
    public var startDate: Date
    public var endDate: Date?
    public var totalInstallments: Int?
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        debtId: UUID,
        userId: UUID,
        installmentAmount: Money,
        frequency: PaymentFrequency,
        startDate: Date,
        endDate: Date? = nil,
        totalInstallments: Int? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtId = debtId
        self.userId = userId
        self.installmentAmount = installmentAmount
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.totalInstallments = totalInstallments
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
