import Foundation

/// Builds synthetic explanation arrays from deterministic assessment (Mock / local tests only).
public enum MonthlySummaryExplanationBuilder {
    public static func build(
        assessment: FinancialRiskAssessment
    ) -> (risk: [AssistantRiskExplanation], unknown: [AssistantUnknownExplanation]) {
        let risk = assessment.signals
            .filter { $0.level != .safe }
            .map { signal in
                AssistantRiskExplanation(
                    reasonCode: signal.reasonCode,
                    text: syntheticRiskText(for: signal.reasonCode),
                    citedFactKeys: signal.sourceFactKeys
                )
            }
        let unknown = assessment.dataCompleteness.requiredUnknownReasonCodes.map { code in
            AssistantUnknownExplanation(
                reasonCode: code,
                text: syntheticUnknownText(for: code)
            )
        }
        return (risk, unknown)
    }

    private static func syntheticRiskText(for reasonCode: FinancialRiskReasonCode) -> String {
        switch reasonCode {
        case .highDebtPaymentToIncome:
            return "债务还款占收入比例已达到需要关注的水平，建议留意现金流安排。"
        case .highDebtPressureScore, .criticalDebtPressure:
            return "综合债务压力指标显示需要关注还款安排与现金流缓冲。"
        case .negativeProjectedBalance, .cashFlowBelowSafeBalance, .monthEndBelowSafeBalance:
            return "现金流预测显示未来余额可能偏紧，建议关注支出与缓冲资金。"
        case .zeroIncomeWithExpenses:
            return "本月暂无收入记录但存在支出，建议核对记账完整性。"
        default:
            return "系统已识别需要关注的财务信号，建议结合当前事实进一步查看。"
        }
    }

    private static func syntheticUnknownText(for reasonCode: FinancialRiskReasonCode) -> String {
        switch reasonCode {
        case .debtDataMissing:
            return "当前缺少完整债务数据，以下分析未包含债务全貌。"
        case .cashFlowProjectionMissing:
            return "缺少未来现金流预测数据，相关结论可能不完整。"
        default:
            return "部分财务数据尚不完整，结论仅基于当前已知信息。"
        }
    }
}
