import Foundation
import YoushuFoundation

public enum AssistantValidationError: Error, Equatable, Sendable {
    case emptyBody
    case emptyTitle
    case emptyAnswer
    case missingDisclaimer
    case citedUnknownFact(String)
    case inventedAmount(String)
    case dataInsufficient
    case cannotAnswer(String)
    case invalidKeyFactSource(String)
    case invalidKeyFactValue(String)
    case invalidWarningSource(String)
    case invalidActionDestination(String)
    case invalidReference(String)
    case forbiddenIdentifier(String)

    public var userMessage: String {
        switch self {
        case .emptyBody: return "AI 回答内容为空。"
        case .emptyTitle: return "AI 回答标题为空。"
        case .emptyAnswer: return "AI 结构化回答正文为空。"
        case .missingDisclaimer: return "财务建议缺少必要的假设与免责声明。"
        case .citedUnknownFact(let key): return "AI 引用了未授权事实：\(key)"
        case .inventedAmount(let key): return "AI 输出了未提供的金额字段：\(key)"
        case .dataInsufficient: return "财务数据不足，无法可靠回答。"
        case .cannotAnswer(let reason): return reason
        case .invalidKeyFactSource(let key): return "结构化 keyFact 引用了未知来源：\(key)"
        case .invalidKeyFactValue(let key): return "结构化 keyFact 数值与事实包不一致：\(key)"
        case .invalidWarningSource(let key): return "结构化 warning 引用了未知来源：\(key)"
        case .invalidActionDestination(let key): return "结构化 action 目标页面无效：\(key)"
        case .invalidReference(let key): return "结构化 reference 无效：\(key)"
        case .forbiddenIdentifier(let key): return "结构化回答包含禁止的内部标识：\(key)"
        }
    }
}

extension AssistantValidationError: LocalizedError {
    public var errorDescription: String? { userMessage }
}

/// 校验 AI 草稿：只能引用事实包中的键与金额，建议类必须有免责声明。
public enum AssistantAnswerValidator {
    public static let defaultAdviceDisclaimer =
        "以上为基于当前账本数据的估算，已说明主要假设；不构成投资、贷款或法律建议，实际决策请结合完整情况自行判断。"

    private static let forbiddenIdentifierKeys: Set<String> = [
        "userId", "accountId", "transactionId", "debtId", "goalId", "budgetId",
        "sourceTransactionIds", "sourceDebtIds", "sourceAccountIds",
    ]

    public static func validate(
        draft: AssistantAnswerDraft,
        against pack: AnswerFactPack
    ) throws -> AssistantAnswerDraft {
        if pack.dataInsufficient {
            throw AssistantValidationError.dataInsufficient
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AssistantValidationError.emptyTitle }
        guard !body.isEmpty else { throw AssistantValidationError.emptyBody }
        guard !answer.isEmpty else { throw AssistantValidationError.emptyAnswer }

        let allowedKeys = Set(pack.facts.keys).union(pack.amounts.keys)
        for key in draft.citedFactKeys where !allowedKeys.contains(key) && !pack.sourceLabels.contains(key) {
            throw AssistantValidationError.citedUnknownFact(key)
        }

        let allowedAmountStrings = Set(pack.amounts.values.map { normalizeAmount($0.amount) })
        for token in extractYuanAmounts(from: answer) + extractYuanAmounts(from: body) {
            if !allowedAmountStrings.isEmpty, !allowedAmountStrings.contains(token) {
                throw AssistantValidationError.inventedAmount(token)
            }
        }

        try validateStructured(draft: draft, allowedKeys: allowedKeys, pack: pack)

        var disclaimer = draft.disclaimer?.trimmingCharacters(in: .whitespacesAndNewlines)
        if pack.requiresDisclaimer {
            if disclaimer == nil || disclaimer?.isEmpty == true {
                let lowered = answer.lowercased()
                let hasInline = lowered.contains("假设") || lowered.contains("不构成") || lowered.contains("仅供参考")
                if hasInline {
                    disclaimer = disclaimer ?? Self.defaultAdviceDisclaimer
                } else {
                    throw AssistantValidationError.missingDisclaimer
                }
            }
        }

        return AssistantAnswerDraft(
            title: title,
            body: body,
            answer: answer,
            citedFactKeys: draft.citedFactKeys,
            disclaimer: disclaimer,
            unknowns: Array(Set(draft.unknowns + pack.unknowns)),
            confidence: draft.confidence,
            keyFacts: draft.keyFacts,
            warnings: draft.warnings,
            actions: draft.actions,
            references: draft.references
        )
    }

    public static func validateSummary(
        draft: AssistantAnswerDraft,
        facts: MonthlySummaryFacts
    ) throws -> AssistantAnswerDraft {
        let pack = factPack(from: facts)
        return try validate(draft: draft, against: pack)
    }

    // MARK: - Structured validation

    private static func validateStructured(
        draft: AssistantAnswerDraft,
        allowedKeys: Set<String>,
        pack: AnswerFactPack
    ) throws {
        let allowedReferences = allowedReferenceKeys(from: allowedKeys)

        for field in collectStructuredStrings(from: draft) {
            try rejectForbiddenIdentifiers(in: field)
        }

        for fact in draft.keyFacts {
            try rejectForbiddenIdentifiers(in: fact.source)
            try rejectForbiddenIdentifiers(in: fact.label)
            guard allowedKeys.contains(fact.source) else {
                throw AssistantValidationError.invalidKeyFactSource(fact.source)
            }
            switch fact.value {
            case .money(let dto):
                guard let expected = pack.amounts[fact.source] else {
                    throw AssistantValidationError.invalidKeyFactSource(fact.source)
                }
                guard normalizeAmount(dto.amount) == normalizeAmount(expected.amount),
                      dto.currencyCode == expected.currencyCode else {
                    throw AssistantValidationError.invalidKeyFactValue(fact.source)
                }
            case .text(let text):
                guard let expected = pack.facts[fact.source], expected == text else {
                    throw AssistantValidationError.invalidKeyFactValue(fact.source)
                }
            case .percent(let value):
                guard let expectedRaw = pack.facts[fact.source],
                      let expected = parsePercent(expectedRaw),
                      expected == value else {
                    throw AssistantValidationError.invalidKeyFactValue(fact.source)
                }
            case .date(let value):
                guard let expectedRaw = pack.facts[fact.source],
                      let expected = ISO8601DateFormatter().date(from: expectedRaw),
                      Calendar.current.isDate(expected, inSameDayAs: value) else {
                    throw AssistantValidationError.invalidKeyFactValue(fact.source)
                }
            }
        }

        for warning in draft.warnings {
            try rejectForbiddenIdentifiers(in: warning.source)
            guard allowedReferences.contains(warning.source) || allowedKeys.contains(warning.source) else {
                throw AssistantValidationError.invalidWarningSource(warning.source)
            }
        }

        for action in draft.actions {
            guard AssistantActionDestination.allCases.contains(action.destination) else {
                throw AssistantValidationError.invalidActionDestination(action.destination.rawValue)
            }
        }

        for reference in draft.references {
            try rejectForbiddenIdentifiers(in: reference.key)
            try validateReferenceKey(reference.key, allowedReferences: allowedReferences)
        }
    }

    private static func validateReferenceKey(_ key: String, allowedReferences: Set<String>) throws {
        if key.hasPrefix("categoryAmount_") {
            guard allowedReferences.contains(key) else {
                throw AssistantValidationError.invalidReference(key)
            }
            return
        }
        guard allowedReferences.contains(key) else {
            throw AssistantValidationError.invalidReference(key)
        }
    }

    private static func parsePercent(_ raw: String) -> Decimal? {
        Decimal(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func allowedReferenceKeys(from allowedKeys: Set<String>) -> Set<String> {
        Set(AssistantReferenceKey.allCases.map(\.rawValue)).union(allowedKeys)
    }

    private static func collectStructuredStrings(from draft: AssistantAnswerDraft) -> [String] {
        var values = [draft.answer, draft.title]
        values.append(contentsOf: draft.keyFacts.map(\.label))
        values.append(contentsOf: draft.keyFacts.map(\.source))
        values.append(contentsOf: draft.warnings.map(\.title))
        values.append(contentsOf: draft.warnings.map(\.message))
        values.append(contentsOf: draft.warnings.map(\.source))
        values.append(contentsOf: draft.actions.map(\.title))
        values.append(contentsOf: draft.references.map(\.key))
        return values
    }

    private static func rejectForbiddenIdentifiers(in value: String) throws {
        let lowered = value.lowercased()
        for key in forbiddenIdentifierKeys where lowered.contains(key.lowercased()) {
            throw AssistantValidationError.forbiddenIdentifier(key)
        }
        if looksLikeUUID(value) {
            throw AssistantValidationError.forbiddenIdentifier(value)
        }
    }

    private static func looksLikeUUID(_ value: String) -> Bool {
        let pattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizeAmount(_ value: Decimal) -> String {
        var v = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &v, 2, .plain)
        return "\(rounded)"
    }

    private static func extractYuanAmounts(from text: String) -> [String] {
        let pattern = #"¥\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            let raw = String(text[r]).replacingOccurrences(of: ",", with: "")
            return normalizeAmount(Decimal(string: raw) ?? 0)
        }
    }
}
