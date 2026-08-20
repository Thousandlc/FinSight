import Foundation
import YoushuFoundation

public enum TransactionDateSectionKind: String, CaseIterable, Sendable, Equatable {
    case today = "今日"
    case yesterday = "昨日"
    case thisWeek = "本周"
    case thisMonth = "本月"
    case earlier = "更早"
}

public struct TransactionListItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let transaction: Transaction
    public let accountName: String
    public let displayType: TransactionType

    public init(transaction: Transaction, accountName: String) {
        self.id = transaction.id
        self.transaction = transaction
        self.accountName = accountName
        self.displayType = TransactionCategory.displayType(for: transaction)
    }
}

public struct TransactionDateSection: Identifiable, Equatable, Sendable {
    public let id: TransactionDateSectionKind
    public let title: String
    public let items: [TransactionListItem]

    public init(kind: TransactionDateSectionKind, items: [TransactionListItem]) {
        self.id = kind
        self.title = kind.rawValue
        self.items = items
    }
}

public enum TransactionGrouper {
    /// 按 今日 / 昨日 / 本周 / 本月 / 更早 分组。转账仅展示转出腿，避免重复。
    public static func group(
        transactions: [Transaction],
        accounts: [Account],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [TransactionDateSection] {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let visible = transactions.filter { shouldDisplayInList($0) }
            .sorted { $0.date > $1.date }

        let items = visible.map { tx in
            TransactionListItem(
                transaction: tx,
                accountName: accountMap[tx.accountId] ?? "未知账户"
            )
        }

        var buckets: [TransactionDateSectionKind: [TransactionListItem]] = [:]
        for item in items {
            let kind = sectionKind(for: item.transaction.date, calendar: calendar, now: now)
            buckets[kind, default: []].append(item)
        }

        return TransactionDateSectionKind.allCases.compactMap { kind in
            guard let sectionItems = buckets[kind], !sectionItems.isEmpty else { return nil }
            return TransactionDateSection(kind: kind, items: sectionItems)
        }
    }

    /// 转账转入腿不在列表重复展示。
    public static func shouldDisplayInList(_ transaction: Transaction) -> Bool {
        if transaction.transactionType == .income,
           transaction.category == TransactionCategory.transfer,
           transaction.transferCounterpartyAccountId != nil {
            return false
        }
        return true
    }

    public static func sectionKind(for date: Date, calendar: Calendar, now: Date) -> TransactionDateSectionKind {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return .thisWeek
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return .thisMonth
        }
        return .earlier
    }
}

public struct MonthlyStats: Equatable, Sendable {
    public var income: Money
    public var expense: Money
    public var net: Money

    public init(income: Money, expense: Money) {
        self.income = income
        self.expense = expense
        self.net = income - expense
    }
}

public enum MonthlyStatsCalculator {
    public static func compute(
        transactions: [Transaction],
        month: Date,
        currencyCode: String,
        calendar: Calendar = .current
    ) -> MonthlyStats {
        let zero = Money(amount: 0, currencyCode: currencyCode)
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return MonthlyStats(income: zero, expense: zero)
        }

        var income = zero
        var expense = zero

        for tx in transactions where tx.date >= interval.start && tx.date < interval.end {
            guard tx.amount.currencyCode == currencyCode else { continue }
            switch tx.transactionType {
            case .income, .refund, .reimbursement:
                if tx.category != TransactionCategory.transfer {
                    income = income + tx.amount
                }
            case .expense:
                expense = expense + tx.amount
            default:
                break
            }
        }

        return MonthlyStats(income: income, expense: expense)
    }
}
