import Foundation
import YoushuFoundation

/// 确定性债务匹配。AI 仅可提供辅助提示，最终分数与阈值由此计算。
public enum DebtMatcher {
    /// 自动关联阈值：需足够高且显著领先第二名。
    public static let autoLinkConfidence: Double = 0.85
    public static let autoLinkMargin: Double = 0.15
    /// 进入待确认的最低置信度。
    public static let pendingConfidence: Double = 0.55

    public struct Context: Sendable {
        public var debts: [Debt]
        public var accounts: [Account]
        public var historicalTransactions: [Transaction]
        /// 可选 AI 提示的债务 id（不得单独决定结果）。
        public var aiSuggestedDebtId: UUID?

        public init(
            debts: [Debt],
            accounts: [Account] = [],
            historicalTransactions: [Transaction] = [],
            aiSuggestedDebtId: UUID? = nil
        ) {
            self.debts = debts
            self.accounts = accounts
            self.historicalTransactions = historicalTransactions
            self.aiSuggestedDebtId = aiSuggestedDebtId
        }
    }

    public static func match(transaction: Transaction, context: Context) -> DebtMatchResult {
        guard isRepaymentLike(transaction) else {
            return .unmatched(reason: "交易不像债务还款（类型/商户不足以判断）")
        }

        let openDebts = context.debts.filter { DebtCenterCalculator.isOpen($0) }
        guard !openDebts.isEmpty else {
            return .unmatched(reason: "没有可匹配的未结清债务")
        }

        let scored: [(debt: Debt, score: Double, reasons: [String])] = openDebts.map { debt in
            let detail = score(transaction: transaction, debt: debt, context: context)
            return (debt, detail.score, detail.reasons)
        }
        .sorted { $0.score > $1.score }

        guard let best = scored.first else {
            return .unmatched(reason: "没有可匹配的未结清债务")
        }

        let second = scored.dropFirst().first?.score ?? 0
        let margin = best.score - second
        let reason = best.reasons.isEmpty ? "综合匹配" : best.reasons.joined(separator: "；")
        let candidateIds = scored.filter { $0.score >= pendingConfidence }.map(\.debt.id)

        // 多债务金额相似且分数接近 → 不自动更新
        if scored.count >= 2,
           best.score >= pendingConfidence,
           margin < autoLinkMargin,
           amountLooksSimilar(transaction, debts: scored.prefix(3).map(\.debt)) {
            return DebtMatchResult(
                status: .ambiguous,
                matchedDebtId: best.debt.id,
                confidence: best.score,
                reason: "多笔债务金额相近，无法可靠自动匹配。\(reason)",
                candidateDebtIds: candidateIds
            )
        }

        if best.score >= autoLinkConfidence, margin >= autoLinkMargin {
            return DebtMatchResult(
                status: .matched,
                matchedDebtId: best.debt.id,
                confidence: best.score,
                reason: reason,
                candidateDebtIds: [best.debt.id]
            )
        }

        if best.score >= pendingConfidence {
            return DebtMatchResult(
                status: .pendingConfirmation,
                matchedDebtId: best.debt.id,
                confidence: best.score,
                reason: reason,
                candidateDebtIds: candidateIds
            )
        }

        return DebtMatchResult(
            status: .unmatched,
            confidence: best.score,
            reason: "最高匹配置信度不足（\(Int(best.score * 100))%）：\(reason)",
            candidateDebtIds: candidateIds
        )
    }

    // MARK: - Scoring

    private static func score(
        transaction: Transaction,
        debt: Debt,
        context: Context
    ) -> (score: Double, reasons: [String]) {
        var score = 0.0
        var reasons: [String] = []
        let merchant = normalize(transaction.merchant)
        let lender = normalize(debt.lender)
        let product = normalize(debt.productName)
        let amount = transaction.amount.amount

        if transaction.transactionType == .repayment {
            score += 0.10
            reasons.append("交易类型为还款")
        }

        if !merchant.isEmpty, !lender.isEmpty, merchantContains(merchant, lender) || merchantContains(lender, merchant) {
            score += 0.35
            reasons.append("商户匹配债权方")
        } else if !merchant.isEmpty, !product.isEmpty, merchantContains(merchant, product) || merchantContains(product, merchant) {
            score += 0.20
            reasons.append("商户匹配产品名")
        }

        if let installment = debt.installmentAmount?.amount, amountsEqual(amount, installment) {
            score += 0.30
            reasons.append("金额匹配每期还款")
        } else if let current = debt.currentDue?.amount, amountsEqual(amount, current) {
            score += 0.25
            reasons.append("金额匹配本期应还")
        } else if let minimum = debt.minimumDue?.amount, amountsEqual(amount, minimum) {
            score += 0.15
            reasons.append("金额匹配最低还款")
        } else if let installment = debt.installmentAmount?.amount, amountsClose(amount, installment) {
            score += 0.18
            reasons.append("金额接近每期还款")
        }

        if let due = debt.dueDate {
            let dueDay = Calendar.current.component(.day, from: due)
            let txDay = Calendar.current.component(.day, from: transaction.date)
            if abs(dueDay - txDay) <= 1 || abs(dueDay - txDay) >= 27 {
                score += 0.15
                reasons.append("交易日接近还款日")
            }
        }

        if let linked = debt.linkedAccountId, linked == transaction.accountId {
            score += 0.15
            reasons.append("付款账户与债务关联账户一致")
        }

        let historyBoost = historicalBoost(
            transaction: transaction,
            debt: debt,
            history: context.historicalTransactions
        )
        if historyBoost > 0 {
            score += historyBoost
            reasons.append("与历史还款行为一致")
        }

        if let aiId = context.aiSuggestedDebtId, aiId == debt.id {
            score += 0.08
            reasons.append("AI 辅助提示一致")
        }

        return (min(score, 1), reasons)
    }

    private static func historicalBoost(
        transaction: Transaction,
        debt: Debt,
        history: [Transaction]
    ) -> Double {
        let related = history.filter {
            $0.relatedDebtId == debt.id
                && ($0.transactionType == .repayment || $0.transactionType == .expense)
        }
        guard !related.isEmpty else { return 0 }

        let merchant = normalize(transaction.merchant)
        let sameMerchant = related.contains {
            !merchant.isEmpty && normalize($0.merchant) == merchant
        }
        let sameAmount = related.contains {
            amountsEqual($0.amount.amount, transaction.amount.amount)
        }
        if sameMerchant && sameAmount { return 0.20 }
        if sameMerchant || sameAmount { return 0.10 }
        return 0.05
    }

    public static func isRepaymentLike(_ transaction: Transaction) -> Bool {
        switch transaction.transactionType {
        case .repayment:
            return true
        case .expense:
            let merchant = normalize(transaction.merchant)
            let keywords = ["还款", "贷款", "借呗", "微粒贷", "信用卡", "分期", "花呗", "白条", "消金", "银行"]
            if keywords.contains(where: { merchant.contains($0) }) { return true }
            if transaction.category == "生活" || transaction.category == "住房" { return false }
            return false
        default:
            return false
        }
    }

    private static func amountLooksSimilar(_ transaction: Transaction, debts: [Debt]) -> Bool {
        let amount = transaction.amount.amount
        let matches = debts.filter { debt in
            [debt.installmentAmount?.amount, debt.currentDue?.amount, debt.minimumDue?.amount]
                .compactMap { $0 }
                .contains { amountsClose(amount, $0) }
        }
        return matches.count >= 2
    }

    private static func amountsEqual(_ a: Decimal, _ b: Decimal) -> Bool {
        a == b
    }

    private static func amountsClose(_ a: Decimal, _ b: Decimal) -> Bool {
        guard b != 0 else { return a == 0 }
        let diff = abs(a - b)
        return diff / abs(b) <= Decimal(string: "0.01")!
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func merchantContains(_ a: String, _ b: String) -> Bool {
        !a.isEmpty && !b.isEmpty && (a.contains(b) || b.contains(a))
    }
}
