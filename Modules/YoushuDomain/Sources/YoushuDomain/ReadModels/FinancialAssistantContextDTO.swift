import Foundation
import YoushuFoundation

/// AI Provider 可接收的金额 DTO。禁止在 Provider payload 中使用 Domain `Money`。
public struct MoneyDTO: Codable, Equatable, Sendable, Hashable {
    public var amount: Decimal
    public var currencyCode: String

    public init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    public init(_ money: Money) {
        self.amount = money.amount
        self.currencyCode = money.currencyCode
    }
}

/// AI 安全财务 Context。由 Domain `FinancialContext` 映射而来，不含 UUID 与原始实体。
public struct FinancialAssistantContextDTO: Codable, Equatable, Sendable {
    public struct Meta: Codable, Equatable, Sendable {
        public var asOf: Date
        public var currencyCode: String

        public init(asOf: Date, currencyCode: String) {
            self.asOf = asOf
            self.currencyCode = currencyCode
        }
    }

    public struct Balance: Codable, Equatable, Sendable {
        public var availableCash: MoneyDTO
        public var estimatedMonthEnd: MoneyDTO

        public init(availableCash: MoneyDTO, estimatedMonthEnd: MoneyDTO) {
            self.availableCash = availableCash
            self.estimatedMonthEnd = estimatedMonthEnd
        }
    }

    public struct Monthly: Codable, Equatable, Sendable {
        public var income: MoneyDTO
        public var expense: MoneyDTO
        public var debtPayment: MoneyDTO
        public var debtToIncomePercent: Decimal?

        public init(
            income: MoneyDTO,
            expense: MoneyDTO,
            debtPayment: MoneyDTO,
            debtToIncomePercent: Decimal?
        ) {
            self.income = income
            self.expense = expense
            self.debtPayment = debtPayment
            self.debtToIncomePercent = debtToIncomePercent
        }
    }

    public struct Debt: Codable, Equatable, Sendable {
        public var totalOutstanding: MoneyDTO?
        public var totalOutstandingAvailability: FieldAvailability
        public var estimatedMonthlyRepayment: MoneyDTO?
        public var estimatedMonthlyRepaymentAvailability: FieldAvailability
        public var debtFreeMonth: Date?

        public init(
            totalOutstanding: MoneyDTO?,
            estimatedMonthlyRepayment: MoneyDTO?,
            debtFreeMonth: Date?,
            totalOutstandingAvailability: FieldAvailability = .known,
            estimatedMonthlyRepaymentAvailability: FieldAvailability = .known
        ) {
            self.totalOutstanding = totalOutstanding
            self.totalOutstandingAvailability = totalOutstandingAvailability
            self.estimatedMonthlyRepayment = estimatedMonthlyRepayment
            self.estimatedMonthlyRepaymentAvailability = estimatedMonthlyRepaymentAvailability
            self.debtFreeMonth = debtFreeMonth
        }

        enum CodingKeys: String, CodingKey {
            case totalOutstanding
            case totalOutstandingAvailability
            case estimatedMonthlyRepayment
            case estimatedMonthlyRepaymentAvailability
            case debtFreeMonth
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalOutstanding = try container.decodeIfPresent(MoneyDTO.self, forKey: .totalOutstanding)
            estimatedMonthlyRepayment = try container.decodeIfPresent(MoneyDTO.self, forKey: .estimatedMonthlyRepayment)
            debtFreeMonth = try container.decodeIfPresent(Date.self, forKey: .debtFreeMonth)
            totalOutstandingAvailability = try container.decodeIfPresent(
                FieldAvailability.self,
                forKey: .totalOutstandingAvailability
            ) ?? .known
            estimatedMonthlyRepaymentAvailability = try container.decodeIfPresent(
                FieldAvailability.self,
                forKey: .estimatedMonthlyRepaymentAvailability
            ) ?? .known
        }
    }

    public struct CashFlow30: Codable, Equatable, Sendable {
        public var endingBalance: MoneyDTO
        public var minimumBalance: MoneyDTO
        public var minimumBalanceDate: Date
        public var isBelowSafeBalance: Bool
        public var safeBalance: MoneyDTO

        public init(
            endingBalance: MoneyDTO,
            minimumBalance: MoneyDTO,
            minimumBalanceDate: Date,
            isBelowSafeBalance: Bool,
            safeBalance: MoneyDTO
        ) {
            self.endingBalance = endingBalance
            self.minimumBalance = minimumBalance
            self.minimumBalanceDate = minimumBalanceDate
            self.isBelowSafeBalance = isBelowSafeBalance
            self.safeBalance = safeBalance
        }
    }

    public struct Spending: Codable, Equatable, Sendable {
        public struct CategoryTotal: Codable, Equatable, Sendable {
            public var category: String
            public var amount: MoneyDTO

            public init(category: String, amount: MoneyDTO) {
                self.category = category
                self.amount = amount
            }
        }

        public var topCategories: [CategoryTotal]

        public init(topCategories: [CategoryTotal]) {
            self.topCategories = topCategories
        }
    }

    public struct Goal: Codable, Equatable, Sendable {
        public var name: String
        public var target: MoneyDTO
        public var current: MoneyDTO
        public var remaining: MoneyDTO
        public var progress: Decimal
        public var targetDate: Date?

        public init(
            name: String,
            target: MoneyDTO,
            current: MoneyDTO,
            remaining: MoneyDTO,
            progress: Decimal,
            targetDate: Date?
        ) {
            self.name = name
            self.target = target
            self.current = current
            self.remaining = remaining
            self.progress = progress
            self.targetDate = targetDate
        }
    }

    public struct Budget: Codable, Equatable, Sendable {
        public var name: String
        public var category: String?
        public var limit: MoneyDTO
        public var spent: MoneyDTO
        public var remaining: MoneyDTO

        public init(
            name: String,
            category: String?,
            limit: MoneyDTO,
            spent: MoneyDTO,
            remaining: MoneyDTO
        ) {
            self.name = name
            self.category = category
            self.limit = limit
            self.spent = spent
            self.remaining = remaining
        }
    }

    public var meta: Meta
    public var balance: Balance
    public var monthly: Monthly
    public var debt: Debt
    public var cashFlow30: CashFlow30?
    public var spending: Spending
    public var goals: [Goal]
    public var budgets: [Budget]

    public init(
        meta: Meta,
        balance: Balance,
        monthly: Monthly,
        debt: Debt,
        cashFlow30: CashFlow30?,
        spending: Spending,
        goals: [Goal],
        budgets: [Budget]
    ) {
        self.meta = meta
        self.balance = balance
        self.monthly = monthly
        self.debt = debt
        self.cashFlow30 = cashFlow30
        self.spending = spending
        self.goals = goals
        self.budgets = budgets
    }
}

/// Provider 请求 DTO：question / intent 与 Context 分离。
public struct AssistantRequestDTO: Codable, Equatable, Sendable {
    public var question: String
    public var intent: FinancialQuestionIntent
    public var context: FinancialAssistantContextDTO

    public init(question: String, intent: FinancialQuestionIntent, context: FinancialAssistantContextDTO) {
        self.question = question
        self.intent = intent
        self.context = context
    }
}

/// Domain `FinancialContext` → AI 安全 DTO。
public enum FinancialAssistantContextMapper {
    public static func map(context: FinancialContext, safeBalance: Money) -> FinancialAssistantContextDTO {
        let alignedSafe = Money(amount: safeBalance.amount, currencyCode: context.currencyCode)
        let cashFlow30 = context.cashFlow30.map { slice in
            FinancialAssistantContextDTO.CashFlow30(
                endingBalance: MoneyDTO(slice.endingBalance),
                minimumBalance: MoneyDTO(slice.minimumBalance),
                minimumBalanceDate: slice.minimumBalanceDate,
                isBelowSafeBalance: slice.isBelowSafeBalance,
                safeBalance: MoneyDTO(alignedSafe)
            )
        }
        return FinancialAssistantContextDTO(
            meta: .init(asOf: context.asOf, currencyCode: context.currencyCode),
            balance: .init(
                availableCash: MoneyDTO(context.availableCash),
                estimatedMonthEnd: MoneyDTO(context.estimatedMonthEndBalance)
            ),
            monthly: .init(
                income: MoneyDTO(context.monthlyIncome),
                expense: MoneyDTO(context.monthlyExpense),
                debtPayment: MoneyDTO(context.monthlyDebtPayment),
                debtToIncomePercent: context.debtPaymentToIncomePercent
            ),
            debt: .init(
                totalOutstanding: context.totalDebtAvailability == .missing
                    ? nil
                    : MoneyDTO(context.totalDebt),
                estimatedMonthlyRepayment: context.estimatedMonthlyRepaymentAvailability == .missing
                    ? nil
                    : MoneyDTO(context.estimatedMonthlyRepayment),
                debtFreeMonth: context.estimatedDebtFreeDate,
                totalOutstandingAvailability: context.totalDebtAvailability,
                estimatedMonthlyRepaymentAvailability: context.estimatedMonthlyRepaymentAvailability
            ),
            cashFlow30: cashFlow30,
            spending: .init(
                topCategories: context.topExpenseCategories.map {
                    .init(category: $0.category, amount: MoneyDTO($0.amount))
                }
            ),
            goals: context.goals.map {
                .init(
                    name: $0.name,
                    target: MoneyDTO($0.targetAmount),
                    current: MoneyDTO($0.currentAmount),
                    remaining: MoneyDTO($0.remainingAmount),
                    progress: $0.progressPercent,
                    targetDate: $0.targetDate
                )
            },
            budgets: context.budgets.map {
                .init(
                    name: $0.name,
                    category: $0.category,
                    limit: MoneyDTO($0.limit),
                    spent: MoneyDTO($0.spent),
                    remaining: MoneyDTO($0.remaining)
                )
            }
        )
    }

    public static func makeRequest(
        question: String,
        intent: FinancialQuestionIntent,
        context: FinancialContext,
        safeBalance: Money
    ) -> AssistantRequestDTO {
        AssistantRequestDTO(
            question: question,
            intent: intent,
            context: map(context: context, safeBalance: safeBalance)
        )
    }
}

public enum FinancialAssistantContextSerializerError: Error, Equatable, Sendable {
    case invalidUTF8
}

/// 将 AI DTO 序列化为 JSON。确定性、无 Repository 依赖。
public enum FinancialAssistantContextSerializer {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static func encodeContext(_ dto: FinancialAssistantContextDTO) throws -> Data {
        try encoder.encode(dto)
    }

    public static func encodeRequest(_ dto: AssistantRequestDTO) throws -> Data {
        try encoder.encode(dto)
    }

    public static func contextJSONString(_ dto: FinancialAssistantContextDTO) throws -> String {
        let data = try encodeContext(dto)
        guard let string = String(data: data, encoding: .utf8) else {
            throw FinancialAssistantContextSerializerError.invalidUTF8
        }
        return string
    }

    public static func requestJSONString(_ dto: AssistantRequestDTO) throws -> String {
        let data = try encodeRequest(dto)
        guard let string = String(data: data, encoding: .utf8) else {
            throw FinancialAssistantContextSerializerError.invalidUTF8
        }
        return string
    }
}
