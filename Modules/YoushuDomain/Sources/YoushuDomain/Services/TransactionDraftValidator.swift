import Foundation

/// 校验 AI 输出的 TransactionDraft。金额计算与落库不在此完成。
public enum TransactionDraftValidator {
    /// 识别阶段校验：阻断性错误抛出；软性问题以 warnings 返回。
    public static func validateRecognition(_ draft: TransactionDraft) throws -> [String] {
        var warnings: [String] = []

        if draft.candidateAmounts.count > 1 {
            throw AIRecognitionError.ambiguousAmount(draft.candidateAmounts)
        }

        if draft.amount == nil {
            if draft.unknowns.contains("amount") || draft.candidateAmounts.isEmpty {
                throw AIRecognitionError.amountMissing
            }
            throw AIRecognitionError.amountMissing
        }

        if let amount = draft.amount, amount <= 0 {
            throw AIRecognitionError.amountMissing
        }

        if draft.date == nil || draft.unknowns.contains("date") {
            warnings.append(AIRecognitionError.dateMissing.userMessage)
        }

        if draft.transactionType == nil {
            warnings.append("未能判断收入/支出，请手动选择。")
        }

        if draft.category == nil {
            warnings.append("未能推测分类，请手动选择。")
        }

        if let confidence = draft.confidence, confidence < 0.5 {
            warnings.append("识别置信度较低（\(Int(confidence * 100))%），请仔细核对。")
        }

        return warnings
    }

    /// 确认落库前校验最终用户数据。
    public static func validateConfirmation(_ input: ConfirmScreenshotTransactionInput) throws {
        guard input.amount > 0 else {
            throw DomainError.validationFailed("金额必须大于 0")
        }
        guard input.formType != .transfer else {
            throw DomainError.validationFailed("截图记账暂不支持转账，请使用手动记账")
        }
        let type = input.formType.transactionType
        guard TransactionCategory.isValid(input.category, for: type) else {
            throw DomainError.validationFailed("分类与交易类型不匹配")
        }
    }

    /// 将 AI 推测账户名映射到本地账户（确定性匹配，非 LLM 计算）。
    public static func resolveAccountId(
        suggestedName: String?,
        accounts: [Account],
        fallback: UUID?
    ) -> UUID? {
        if let name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if let exact = accounts.first(where: { $0.name == name && !$0.isArchived }) {
                return exact.id
            }
            if let fuzzy = accounts.first(where: {
                !$0.isArchived && ($0.name.contains(name) || name.contains($0.name))
            }) {
                return fuzzy.id
            }
        }
        return fallback ?? accounts.first(where: { !$0.isArchived })?.id
    }
}
