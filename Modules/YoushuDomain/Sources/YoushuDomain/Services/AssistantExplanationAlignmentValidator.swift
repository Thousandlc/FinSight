import Foundation

public struct AssistantRiskExplanation: Equatable, Sendable {
    public var reasonCode: FinancialRiskReasonCode
    public var text: String
    public var citedFactKeys: [String]

    public init(reasonCode: FinancialRiskReasonCode, text: String, citedFactKeys: [String]) {
        self.reasonCode = reasonCode
        self.text = text
        self.citedFactKeys = citedFactKeys
    }
}

public struct AssistantUnknownExplanation: Equatable, Sendable {
    public var reasonCode: FinancialRiskReasonCode
    public var text: String

    public init(reasonCode: FinancialRiskReasonCode, text: String) {
        self.reasonCode = reasonCode
        self.text = text
    }
}

public enum AssistantExplanationAlignmentError: Error, Equatable, Sendable {
    case riskExplanationCoverageMismatch
    case duplicateRiskExplanationReason
    case riskExplanationReasonNotInAssessment(FinancialRiskReasonCode)
    case unregisteredRiskExplanationFact(String)
    case riskExplanationFactNotInSignalSources(String)
    case duplicateRiskExplanationFact(String)
    case riskExplanationMissingPrimarySource(FinancialRiskReasonCode)
    case unknownExplanationCoverageMismatch
    case duplicateUnknownExplanationReason
    case unsupportedUnknownExplanationReason(FinancialRiskReasonCode)
}

extension AssistantExplanationAlignmentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .riskExplanationCoverageMismatch:
            return "riskExplanations 与 assessment signals 未一一对应。"
        case .duplicateRiskExplanationReason:
            return "riskExplanations 存在重复 reasonCode。"
        case .riskExplanationReasonNotInAssessment(let code):
            return "riskExplanation 引用了 assessment 中不存在的 reasonCode：\(code.rawValue)。"
        case .unregisteredRiskExplanationFact(let key):
            return "riskExplanation 引用了未注册 fact：\(key)。"
        case .riskExplanationFactNotInSignalSources(let key):
            return "riskExplanation 引用了 signal 不允许的 fact：\(key)。"
        case .duplicateRiskExplanationFact(let key):
            return "riskExplanation 存在重复 citedFactKey：\(key)。"
        case .riskExplanationMissingPrimarySource(let code):
            return "riskExplanation 缺少 primary source：\(code.rawValue)。"
        case .unknownExplanationCoverageMismatch:
            return "unknownExplanations 与 requiredUnknownReasonCodes 未一一对应。"
        case .duplicateUnknownExplanationReason:
            return "unknownExplanations 存在重复 reasonCode。"
        case .unsupportedUnknownExplanationReason(let code):
            return "unknownExplanation 引用了未要求的 reasonCode：\(code.rawValue)。"
        }
    }
}

/// Validates AI explanation arrays against deterministic FinancialRiskAssessment without recomputing risk.
public enum AssistantExplanationAlignmentValidator {
    public static func validate(
        riskExplanations: [AssistantRiskExplanation],
        unknownExplanations: [AssistantUnknownExplanation],
        assessment: FinancialRiskAssessment,
        facts: MonthlySummaryFacts
    ) throws {
        let pack = AssistantAnswerValidator.factPack(from: facts)
        let allowedFacts = Set(pack.facts.keys).union(pack.amounts.keys)
        let expectedRisk = expectedSignalReasonCodes(from: assessment)
        try validateRiskCoverage(riskExplanations: riskExplanations, expected: expectedRisk)
        try validateRiskProvenance(
            riskExplanations: riskExplanations,
            assessment: assessment,
            allowedFacts: allowedFacts
        )
        let expectedUnknown = assessment.dataCompleteness.requiredUnknownReasonCodes.sorted { $0.rawValue < $1.rawValue }
        try validateUnknownCoverage(
            unknownExplanations: unknownExplanations,
            expected: expectedUnknown
        )
    }

    public static func mapUnknownTexts(_ explanations: [AssistantUnknownExplanation]) -> [String] {
        explanations.map(\.text)
    }

    private static func expectedSignalReasonCodes(from assessment: FinancialRiskAssessment) -> [FinancialRiskReasonCode] {
        assessment.signals
            .filter { $0.level != .safe }
            .map(\.reasonCode)
            .sorted { $0.rawValue < $1.rawValue }
    }

    private static func validateRiskCoverage(
        riskExplanations: [AssistantRiskExplanation],
        expected: [FinancialRiskReasonCode]
    ) throws {
        var actual: [FinancialRiskReasonCode] = []
        var seen: Set<FinancialRiskReasonCode> = []
        for item in riskExplanations {
            if seen.contains(item.reasonCode) {
                throw AssistantExplanationAlignmentError.duplicateRiskExplanationReason
            }
            seen.insert(item.reasonCode)
            actual.append(item.reasonCode)
        }
        actual.sort { $0.rawValue < $1.rawValue }
        guard actual == expected else {
            throw AssistantExplanationAlignmentError.riskExplanationCoverageMismatch
        }
    }

    private static func validateRiskProvenance(
        riskExplanations: [AssistantRiskExplanation],
        assessment: FinancialRiskAssessment,
        allowedFacts: Set<String>
    ) throws {
        let signalByReason = Dictionary(
            uniqueKeysWithValues: assessment.signals
                .filter { $0.level != .safe }
                .map { ($0.reasonCode, $0) }
        )
        for explanation in riskExplanations {
            guard let signal = signalByReason[explanation.reasonCode] else {
                throw AssistantExplanationAlignmentError.riskExplanationReasonNotInAssessment(explanation.reasonCode)
            }
            let allowedSources = Set(signal.sourceFactKeys)
            var seenCited: Set<String> = []
            var hasPrimary = false
            for key in explanation.citedFactKeys {
                if seenCited.contains(key) {
                    throw AssistantExplanationAlignmentError.duplicateRiskExplanationFact(key)
                }
                seenCited.insert(key)
                guard allowedFacts.contains(key) else {
                    throw AssistantExplanationAlignmentError.unregisteredRiskExplanationFact(key)
                }
                guard allowedSources.contains(key) else {
                    throw AssistantExplanationAlignmentError.riskExplanationFactNotInSignalSources(key)
                }
                if key == signal.primarySourceFactKey {
                    hasPrimary = true
                }
            }
            if !hasPrimary {
                throw AssistantExplanationAlignmentError.riskExplanationMissingPrimarySource(explanation.reasonCode)
            }
        }
    }

    private static func validateUnknownCoverage(
        unknownExplanations: [AssistantUnknownExplanation],
        expected: [FinancialRiskReasonCode]
    ) throws {
        var actual: [FinancialRiskReasonCode] = []
        var seen: Set<FinancialRiskReasonCode> = []
        for item in unknownExplanations {
            if seen.contains(item.reasonCode) {
                throw AssistantExplanationAlignmentError.duplicateUnknownExplanationReason
            }
            seen.insert(item.reasonCode)
            actual.append(item.reasonCode)
        }
        actual.sort { $0.rawValue < $1.rawValue }
        guard actual == expected else {
            throw AssistantExplanationAlignmentError.unknownExplanationCoverageMismatch
        }
    }
}
