import Foundation
import YoushuDomain

/// Conservative parser for supported WeChat Pay and Alipay transaction-detail screenshots.
/// It consumes transient OCR text only and has no persistence, network, or UI responsibility.
public struct DeterministicTransactionReceiptParser: TransactionRecognizedTextParsing {
    private enum Family {
        case weChat
        case alipay
    }

    private static let amountLabels = [
        "交易金额", "付款金额", "支付金额", "收款金额", "退款金额", "实付金额", "金额",
    ]
    private static let excludedAmountMarkers = [
        "订单号", "交易号", "商户单号", "流水号", "编号", "优惠券", "优惠", "红包",
        "手续费", "服务费", "余额", "原价", "折扣",
    ]
    private static let incomeMarkers = [
        "收款成功", "收款到账", "转账已到账", "已收钱", "收到转账", "收款金额", "收入",
        "退款成功", "退款金额", "refund received", "money received", "received",
    ]
    private static let expenseMarkers = [
        "支付成功", "付款成功", "付款金额", "支付金额", "实付金额", "支出", "付款方式", "支付方式",
        "payment successful", "paid", "payment amount",
    ]
    private static let transactionMarkers = incomeMarkers + expenseMarkers + [
        "交易成功", "账单详情", "transaction successful", "transaction details",
    ]
    private static let dateLabels = [
        "支付时间", "付款时间", "交易时间", "收款时间", "退款时间", "转账时间", "完成时间",
    ]
    private static let merchantLabels = [
        "商户", "商家", "收款方", "付款给", "交易对方", "付款方", "转账方", "对方",
    ]
    private static let accountLabels = ["支付方式", "付款方式", "收款方式"]

    public init() {}

    public func parseTransaction(from spans: [RecognizedTextSpan]) -> TransactionRecognitionOutcome {
        let lines = spans
            .map { normalize($0.text) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return .unreadable }
        guard let family = family(in: lines) else {
            return isReadable(lines) ? .unsupported : .unreadable
        }
        guard containsAny(lines, markers: Self.transactionMarkers) else { return .unsupported }
        guard let direction = direction(in: lines) else { return .unreadable }
        guard let amount = amount(in: lines) else { return .unreadable }

        let occurredAt = labeledDate(in: lines)
        let merchant = labeledValue(in: lines, labels: Self.merchantLabels)
        let accountHint = labeledValue(in: lines, labels: Self.accountLabels)

        var unknowns = ["category"]
        if occurredAt == nil { unknowns.append("date") }
        if merchant == nil { unknowns.append("merchant") }
        if accountHint == nil { unknowns.append("suggestedAccountName") }

        // The family check deliberately participates in support classification, not guessed field values.
        _ = family
        return .recognized(
            TransactionDraft(
                amount: amount,
                transactionType: direction,
                merchant: merchant,
                date: occurredAt,
                category: nil,
                suggestedAccountName: accountHint,
                currencyCode: "CNY",
                confidence: nil,
                source: .screenshot,
                candidateAmounts: [amount],
                unknowns: unknowns
            )
        )
    }

    private func family(in lines: [String]) -> Family? {
        if containsAny(lines, markers: ["微信", "wechat"]) { return .weChat }
        if containsAny(lines, markers: ["支付宝", "alipay"]) { return .alipay }
        return nil
    }

    private func direction(in lines: [String]) -> TransactionType? {
        let hasIncome = containsAny(lines, markers: Self.incomeMarkers)
        let hasExpense = containsAny(lines, markers: Self.expenseMarkers)
        guard hasIncome != hasExpense else { return nil }
        return hasIncome ? .income : .expense
    }

    private func amount(in lines: [String]) -> Decimal? {
        var strong: [String: Decimal] = [:]
        var weak: [String: Decimal] = [:]

        for (index, line) in lines.enumerated() {
            guard !containsAny([line], markers: Self.excludedAmountMarkers) else { continue }
            let hasLabel = Self.amountLabels.contains { line.localizedCaseInsensitiveContains($0) }
            let direct = monetaryValues(in: line)
            if hasLabel {
                add(direct, to: &strong)
                if direct.isEmpty, lines.indices.contains(index + 1) {
                    let next = lines[index + 1]
                    if !containsAny([next], markers: Self.excludedAmountMarkers) {
                        add(monetaryValues(in: next), to: &strong)
                    }
                }
            } else {
                add(direct, to: &weak)
            }
        }

        if strong.count == 1 { return strong.values.first }
        if strong.count > 1 { return nil }
        return weak.count == 1 ? weak.values.first : nil
    }

    private func add(_ values: [Decimal], to candidates: inout [String: Decimal]) {
        for value in values where value > 0 {
            candidates[NSDecimalNumber(decimal: value).stringValue] = value
        }
    }

    private func monetaryValues(in line: String) -> [Decimal] {
        let patterns = [
            #"[¥￥]\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
            #"[+-]\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:元)?"#,
            #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*元"#,
        ]
        var values: [String: Decimal] = [:]
        for pattern in patterns {
            for raw in captures(pattern: pattern, text: line) {
                let canonical = raw.replacingOccurrences(of: ",", with: "")
                guard let value = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")),
                      value > 0 else {
                    continue
                }
                values[NSDecimalNumber(decimal: value).stringValue] = value
            }
        }
        return Array(values.values)
    }

    private func labeledDate(in lines: [String]) -> Date? {
        for (index, line) in lines.enumerated() {
            guard Self.dateLabels.contains(where: { line.contains($0) }) else { continue }
            if let date = dateValue(in: line) { return date }
            if lines.indices.contains(index + 1), let date = dateValue(in: lines[index + 1]) { return date }
        }
        return nil
    }

    private func dateValue(in text: String) -> Date? {
        let pattern = #"(20[0-9]{2}[年./-][01]?[0-9][月./-][0-3]?[0-9]日?(?:\s+[0-2]?[0-9]:[0-5][0-9](?::[0-5][0-9])?)?)"#
        guard let raw = captures(pattern: pattern, text: text).first else { return nil }
        let normalized = raw
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        for format in ["yyyy-M-d HH:mm:ss", "yyyy-M-d HH:mm", "yyyy-M-d"] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) { return date }
        }
        return nil
    }

    private func labeledValue(in lines: [String], labels: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard let label = labels.first(where: { line.localizedCaseInsensitiveContains($0) }) else { continue }
            let suffix = valueAfter(label: label, in: line)
            if isSafeOptionalText(suffix) { return suffix }
            if lines.indices.contains(index + 1), isSafeOptionalText(lines[index + 1]) {
                return lines[index + 1]
            }
        }
        return nil
    }

    private func valueAfter(label: String, in line: String) -> String {
        guard let range = line.range(of: label, options: .caseInsensitive) else { return "" }
        return String(line[range.upperBound...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：")))
    }

    private func isSafeOptionalText(_ value: String) -> Bool {
        guard !value.isEmpty,
              monetaryValues(in: value).isEmpty,
              dateValue(in: value) == nil,
              !containsAny([value], markers: Self.transactionMarkers + Self.amountLabels + Self.dateLabels),
              value.count <= 80 else {
            return false
        }
        return true
    }

    private func captures(pattern: String, text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private func containsAny(_ lines: [String], markers: [String]) -> Bool {
        lines.contains { line in
            markers.contains { line.localizedCaseInsensitiveContains($0) }
        }
    }

    private func isReadable(_ lines: [String]) -> Bool {
        let joined = lines.joined(separator: " ")
        let letters = joined.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || (0x4E00...0x9FFF).contains(Int($0.value))
        }
        return letters.count >= 3
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
