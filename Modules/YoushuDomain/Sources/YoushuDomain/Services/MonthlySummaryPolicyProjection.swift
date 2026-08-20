import Foundation

/// Application-layer projection: deterministic `FinancialRiskAssessment` → Assistant warnings/actions.
/// Does not recompute risk, thresholds, or debt semantics — only consumes assessment output.
public enum MonthlySummaryPolicyProjection {
    public static func applyPolicyOwnership(
        to aiDraft: AssistantAnswerDraft,
        assessment: FinancialRiskAssessment
    ) -> AssistantAnswerDraft {
        var draft = aiDraft
        draft.warnings = projectWarnings(from: assessment)
        draft.actions = projectActions(from: assessment)
        return draft
    }

    public static func projectWarnings(from assessment: FinancialRiskAssessment) -> [AssistantWarning] {
        FinancialRiskSignalOrdering.sortSignals(assessment.signals)
            .filter { $0.level != .safe }
            .map(warning(from:))
    }

    public static func projectActions(from assessment: FinancialRiskAssessment) -> [AssistantAction] {
        let destinations = Set(
            assessment.signals.flatMap(\.recommendedActionDestinations)
        )
        let ordered = FinancialRiskSignalOrdering.sortActions(Array(destinations))
        return ordered.map { destination in
            let mapped = FinancialRiskAssistantMapper.mapActionDestination(destination)
            return AssistantAction(
                title: actionTitle(for: mapped),
                destination: mapped
            )
        }
    }

    private static func warning(from signal: FinancialRiskSignal) -> AssistantWarning {
        let copy = warningCopy(for: signal.reasonCode)
        let source = signal.primarySourceFactKey
        return AssistantWarning(
            title: copy.title,
            message: copy.message,
            severity: FinancialRiskAssistantMapper.mapLevel(signal.level),
            source: source
        )
    }

    private static func warningCopy(for reasonCode: FinancialRiskReasonCode) -> (title: String, message: String) {
        switch reasonCode {
        case .negativeProjectedBalance:
            return ("预计余额缺口", "预计余额可能出现缺口，请关注现金流。")
        case .cashFlowBelowSafeBalance:
            return ("现金流提醒", "现金流可能低于安全余额。")
        case .monthEndBelowSafeBalance:
            return ("月底结余提醒", "预计月底结余可能低于安全余额。")
        case .highDebtPaymentToIncome:
            return ("债务压力偏高", "债务还款占收入比例较高，需关注现金流。")
        case .highDebtPressureScore:
            return ("债务压力较高", "债务压力评分偏高，建议关注还款安排。")
        case .criticalDebtPressure:
            return ("债务压力严重", "债务压力达到临界水平，请优先处理。")
        case .zeroIncomeWithExpenses:
            return ("收支异常", "本月暂未记录收入，但已有支出。")
        default:
            return ("财务提醒", "请关注当前财务状况。")
        }
    }

    private static func actionTitle(for destination: AssistantActionDestination) -> String {
        switch destination {
        case .cashFlow:
            return "查看未来现金流"
        case .debt:
            return "查看债务详情"
        case .transactions:
            return "查看交易记录"
        case .accounts:
            return "查看账户"
        }
    }
}
