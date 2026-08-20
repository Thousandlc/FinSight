import Foundation
import YoushuFoundation

/// 统一账户余额引擎。所有余额必须经此计算，禁止 LLM 或 View 层硬算。
public enum AccountBalanceEngine {
    // MARK: - Public API

    /// 单个账户当前余额（opening + 全部关联交易）。
    public static func balance(
        account: Account,
        transactions: [Transaction],
        allAccounts: [Account] = []
    ) -> Money {
        let related = transactions.filter { $0.accountId == account.id }
        var result = account.openingBalance
        for tx in related.sorted(by: { $0.date < $1.date }) {
            result = apply(transaction: tx, to: result, account: account, allAccounts: allAccounts)
        }
        return result
    }

    /// 可用资金：仅汇总资产类账户余额（不含信用卡负债账户）。
    public static func availableFunds(
        accounts: [Account],
        transactions: [Transaction]
    ) -> Money {
        let activeAssets = accounts.filter { !$0.isArchived && $0.type.isAsset }
        let currency = activeAssets.first?.currencyCode
            ?? accounts.first?.currencyCode
            ?? "CNY"
        var total = Money(amount: 0, currencyCode: currency)
        for account in activeAssets {
            let bal = balance(account: account, transactions: transactions, allAccounts: accounts)
            guard bal.currencyCode == currency else { continue }
            total = total + bal
        }
        return total
    }

    /// 对单笔交易应用余额变化（用于测试与增量理解）。
    public static func apply(
        transaction: Transaction,
        to balance: Money,
        account: Account,
        allAccounts: [Account] = []
    ) -> Money {
        precondition(transaction.amount.currencyCode == balance.currencyCode, "Currency mismatch")
        let delta = delta(for: transaction, account: account, allAccounts: allAccounts)
        return Money(amount: balance.amount + delta, currencyCode: balance.currencyCode)
    }

    // MARK: - Delta rules

    public static func delta(
        for transaction: Transaction,
        account: Account,
        allAccounts: [Account] = []
    ) -> Decimal {
        let amount = transaction.amount.amount
        if account.type.isLiability {
            return liabilityDelta(for: transaction, amount: amount)
        }
        return assetDelta(for: transaction, amount: amount, account: account)
    }

    /// 资产账户：收入增、支出减、转出减、转入增、还款减。
    private static func assetDelta(for transaction: Transaction, amount: Decimal, account: Account) -> Decimal {
        switch transaction.transactionType {
        case .income, .refund, .reimbursement, .borrowing, .investmentSell:
            if isTransferInbound(transaction, accountId: account.id) {
                return amount
            }
            if transaction.category == TransactionCategory.transfer,
               transaction.transferCounterpartyAccountId != nil {
                return amount
            }
            return amount
        case .expense, .investmentBuy:
            return -amount
        case .repayment:
            return -amount
        case .transfer:
            return -amount
        }
    }

    /// 信用卡账户：消费增加欠款（余额更负），还款减少欠款。
    private static func liabilityDelta(for transaction: Transaction, amount: Decimal) -> Decimal {
        switch transaction.transactionType {
        case .expense:
            return -amount
        case .repayment:
            return amount
        case .income:
            if transaction.category == TransactionCategory.transfer {
                return amount
            }
            return amount
        case .refund, .reimbursement:
            return amount
        default:
            return 0
        }
    }

    private static func isTransferInbound(_ transaction: Transaction, accountId: UUID) -> Bool {
        transaction.transactionType == .income
            && transaction.category == TransactionCategory.transfer
            && transaction.accountId == accountId
            && transaction.transferCounterpartyAccountId != nil
    }
}

/// 向后兼容别名。
public typealias AccountBalanceCalculator = AccountBalanceEngine
