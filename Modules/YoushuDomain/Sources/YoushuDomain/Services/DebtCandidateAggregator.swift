import Foundation

/// 校验 AI 债务候选。禁止臆造利率/总欠款。
public enum DebtCandidateValidator {
    public static func validate(_ candidate: DebtCandidate) throws -> [String] {
        var warnings: [String] = []

        let lender = candidate.lender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if lender.isEmpty {
            throw AIRecognitionError.invalidResponse("债务候选缺少债权方")
        }

        let hasAnyAmount = candidate.outstandingBalance != nil
            || candidate.currentDue != nil
            || candidate.minimumDue != nil
            || candidate.installmentAmount != nil
        if !hasAnyAmount {
            throw AIRecognitionError.amountMissing
        }

        // 严格区分：不得用本期应还冒充总欠款（检测明显误填）
        if let outstanding = candidate.outstandingBalance,
           let current = candidate.currentDue,
           let minimum = candidate.minimumDue,
           outstanding == current,
           current == minimum,
           outstanding > 0 {
            warnings.append("「剩余总欠款 / 本期应还 / 最低还款」数值相同，请人工核对，勿混淆字段。")
        }

        if candidate.outstandingBalance == nil {
            warnings.append("未识别剩余总欠款，请确认后手动填写。")
        }

        if candidate.interestRate == nil || candidate.unknowns.contains("interestRate") {
            warnings.append("利率未知，未做猜测。")
        }

        if let confidence = candidate.confidence, confidence < 0.5 {
            warnings.append("识别置信度较低（\(Int(confidence * 100))%），请仔细核对。")
        }

        if let outstanding = candidate.outstandingBalance, outstanding < 0 {
            throw AIRecognitionError.invalidResponse("剩余总欠款不能为负")
        }
        if let current = candidate.currentDue, current < 0 {
            throw AIRecognitionError.invalidResponse("本期应还不能为负")
        }

        return warnings
    }

    public static func validateBatch(_ candidates: [DebtCandidate]) throws -> [String] {
        var warnings: [String] = []
        for candidate in candidates {
            warnings.append(contentsOf: try validate(candidate))
        }
        return Array(Set(warnings)).sorted()
    }
}

/// 将同一债权多页截图聚合为一个 DebtCandidate，避免重复建债。
public enum DebtCandidateAggregator {
    public static func aggregate(_ raw: [DebtCandidate]) -> [DebtCandidate] {
        var buckets: [String: DebtCandidate] = [:]
        var order: [String] = []

        for candidate in raw {
            let key = aggregationKey(for: candidate)
            if let existing = buckets[key] {
                buckets[key] = merge(existing, with: candidate)
            } else {
                buckets[key] = candidate
                order.append(key)
            }
        }
        return order.compactMap { buckets[$0] }
    }

    public static func aggregationKey(for candidate: DebtCandidate) -> String {
        let lender = normalize(candidate.lender)
        let product = normalize(candidate.productName)
        let type = (candidate.debtType ?? .other).rawValue
        if product.isEmpty {
            return "\(lender)|\(type)"
        }
        return "\(lender)|\(product)|\(type)"
    }

    /// 合并字段：只填补空值；总欠款取更完整/更大的非空值；绝不把 currentDue 写入 outstandingBalance。
    public static func merge(_ lhs: DebtCandidate, with rhs: DebtCandidate) -> DebtCandidate {
        var merged = lhs
        merged.lender = preferString(lhs.lender, rhs.lender)
        merged.productName = preferString(lhs.productName, rhs.productName)
        merged.debtType = lhs.debtType ?? rhs.debtType

        merged.outstandingBalance = preferAmount(lhs.outstandingBalance, rhs.outstandingBalance, preferMax: true)
        merged.currentDue = preferAmount(lhs.currentDue, rhs.currentDue, preferMax: false)
        merged.minimumDue = preferAmount(lhs.minimumDue, rhs.minimumDue, preferMax: false)
        merged.installmentAmount = preferAmount(lhs.installmentAmount, rhs.installmentAmount, preferMax: false)
        merged.originalAmount = preferAmount(lhs.originalAmount, rhs.originalAmount, preferMax: true)

        merged.dueDate = lhs.dueDate ?? rhs.dueDate
        merged.remainingInstallments = lhs.remainingInstallments ?? rhs.remainingInstallments
        // 利率：只有两边都有值时才保留；任一 unknown 不臆造
        merged.interestRate = lhs.interestRate ?? rhs.interestRate
        merged.currencyCode = lhs.currencyCode ?? rhs.currencyCode

        let confL = lhs.confidence ?? 0
        let confR = rhs.confidence ?? 0
        merged.confidence = max(confL, confR)

        merged.sourceDocuments = Array(Set(lhs.sourceDocuments + rhs.sourceDocuments)).sorted()
        merged.unknowns = Array(Set(lhs.unknowns + rhs.unknowns)).sorted()

        // 若合并后已有 outstandingBalance，移除对应 unknown
        if merged.outstandingBalance != nil {
            merged.unknowns.removeAll { $0 == "outstandingBalance" }
        }
        if merged.interestRate != nil {
            merged.unknowns.removeAll { $0 == "interestRate" }
        }
        return merged
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func preferString(_ a: String?, _ b: String?) -> String? {
        let left = a?.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let left, !left.isEmpty { return left }
        if let right, !right.isEmpty { return right }
        return nil
    }

    private static func preferAmount(_ a: Decimal?, _ b: Decimal?, preferMax: Bool) -> Decimal? {
        switch (a, b) {
        case let (l?, _) where preferMax == false: return l // 非总额字段：保留先出现的，避免被另一页本期金额覆盖
        case let (l?, r?) where preferMax: return max(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }
}
