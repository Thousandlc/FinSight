import Foundation
import YoushuFoundation

/// 从历史交易中发现疑似周期性债务还款（确定性规则，非 AI 数学）。
public enum SuspectedDebtDetector {
    public static let minimumOccurrences = 3
    public static let maxDaySpread = 3

    public static func detect(
        userId: UUID,
        transactions: [Transaction],
        existingDebts: [Debt],
        ignoredKeys: Set<String> = []
    ) -> [SuspectedDebt] {
        let candidates = transactions.filter { tx in
            tx.userId == userId
                && tx.relatedDebtId == nil
                && (tx.transactionType == .expense || tx.transactionType == .repayment)
                && tx.amount.amount > 0
        }

        var groups: [String: [Transaction]] = [:]
        for tx in candidates {
            let merchant = normalize(tx.merchant)
            guard !merchant.isEmpty else { continue }
            let key = "\(merchant)|\(tx.amount.amount)|\(tx.amount.currencyCode)"
            groups[key, default: []].append(tx)
        }

        let lenders = Set(existingDebts.compactMap { normalize($0.lender) }.filter { !$0.isEmpty })

        var results: [SuspectedDebt] = []
        for (_, txs) in groups {
            guard txs.count >= minimumOccurrences else { continue }
            let sorted = txs.sorted { $0.date < $1.date }
            let days = sorted.map { Calendar.current.component(.day, from: $0.date) }
            guard let minDay = days.min(), let maxDay = days.max() else { continue }
            let spread = maxDay - minDay
            // 允许跨月末：如 28/29/1/2
            let wrappedSpread = min(spread, (minDay + 31) - maxDay)
            guard wrappedSpread <= maxDaySpread || spread <= maxDaySpread else { continue }

            let merchant = normalize(sorted.first?.merchant)
            guard !merchant.isEmpty else { continue }
            if lenders.contains(where: { merchantContains(merchant, $0) }) {
                continue
            }

            let amount = sorted[0].amount
            let key = patternKey(merchant: merchant, amount: amount)
            if ignoredKeys.contains(key) { continue }

            let dayOfMonth = medianDay(days)
            let reason = "固定金额 \(amount.amount)、约每月 \(dayOfMonth) 日、连续出现 \(sorted.count) 次，商户「\(sorted[0].merchant ?? merchant)」疑似贷款/分期还款"

            results.append(
                SuspectedDebt(
                    userId: userId,
                    merchant: sorted[0].merchant ?? merchant,
                    amount: amount,
                    dayOfMonth: dayOfMonth,
                    occurrenceCount: sorted.count,
                    sampleTransactionIds: sorted.map(\.id),
                    reason: reason
                )
            )
        }

        return results.sorted { $0.occurrenceCount > $1.occurrenceCount }
    }

    public static func patternKey(merchant: String, amount: Money) -> String {
        "\(normalize(merchant))|\(amount.amount)|\(amount.currencyCode)"
    }

    private static func medianDay(_ days: [Int]) -> Int {
        let sorted = days.sorted()
        return sorted[sorted.count / 2]
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
