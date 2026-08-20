package provider

import (
	"context"
	"fmt"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// MockUpstreamAIProvider returns structured JSON derived from request facts and assessment.
type MockUpstreamAIProvider struct{}

func NewMockUpstreamAIProvider() *MockUpstreamAIProvider {
	return &MockUpstreamAIProvider{}
}

func (p *MockUpstreamAIProvider) CompleteMonthlySummary(
	_ context.Context,
	req contract.RequestEnvelope,
) (contract.AssistantAnswerDraftDTO, error) {
	facts := req.MonthlySummaryFacts
	if facts == nil {
		return contract.AssistantAnswerDraftDTO{}, fmt.Errorf("missing monthlySummaryFacts")
	}
	if req.FinancialRiskAssessment == nil {
		return contract.AssistantAnswerDraftDTO{}, fmt.Errorf("missing financialRiskAssessment")
	}

	keyFacts := []contract.ModelKeyFactDTO{
		modelSelectionKeyFact("可用资金", "availableCash", "balance"),
		modelSelectionKeyFact("预计月底结余", "estimatedMonthEndBalance", "balance"),
	}
	references := []contract.Reference{
		{Key: "availableCash"},
		{Key: "estimatedMonthEndBalance"},
	}
	body := fmt.Sprintf(
		"本月主要压力来自%s。预计月底结余约 %s。",
		facts.PrimaryPressure,
		formatMoney(facts.EstimatedMonthEndBalance),
	)
	keyFacts = append(keyFacts, modelSelectionKeyFact("主要压力", "primaryPressure", "other"))
	references = append(references, contract.Reference{Key: "primaryPressure"})

	if facts.DebtPaymentToIncomePercent != nil {
		keyFacts = append(keyFacts, modelSelectionKeyFact("债务还款占比", "debtPaymentToIncomePercent", "debt"))
		references = append(references, contract.Reference{Key: "debtPaymentToIncomePercent"})
	}

	riskExplanations := buildSyntheticRiskExplanations(req.FinancialRiskAssessment)
	unknownExplanations := buildSyntheticUnknownExplanations(req.FinancialRiskAssessment)
	model := contract.ModelAssistantAnswerDraftDTO{
		Title:               "本月财务摘要",
		Body:                body,
		Answer:              body,
		CitedFactKeys:       []string{"monthlyIncome", "monthlyDebtPayment", "primaryPressure", "estimatedMonthEndBalance"},
		Confidence:          0.9,
		KeyFacts:            keyFacts,
		References:          references,
		RiskExplanations:    riskExplanations,
		UnknownExplanations: unknownExplanations,
	}
	if err := ValidateModelDraft(model); err != nil {
		return contract.AssistantAnswerDraftDTO{}, err
	}
	keySets := factpack.BuildKeySetsForRequest(facts, req.FinancialRiskAssessment)
	if err := ValidateKeyFactSelection(model, keySets); err != nil {
		return contract.AssistantAnswerDraftDTO{}, err
	}
	if err := ValidateExplanationAlignment(model, req.FinancialRiskAssessment, keySets); err != nil {
		return contract.AssistantAnswerDraftDTO{}, err
	}
	draft, err := MapModelDraftToGateway(model, req.FinancialRiskAssessment, facts)
	if err != nil {
		return contract.AssistantAnswerDraftDTO{}, err
	}
	if err := ValidateAssembledRiskExplanationProvenance(draft.RiskExplanations, req.FinancialRiskAssessment, keySets); err != nil {
		return contract.AssistantAnswerDraftDTO{}, err
	}
	return draft, nil
}

func buildSyntheticRiskExplanations(assessment *contract.FinancialRiskAssessmentDTO) []contract.ModelRiskExplanationDTO {
	var out []contract.ModelRiskExplanationDTO
	for _, signal := range assessment.Signals {
		if signal.Level == "safe" {
			continue
		}
		out = append(out, contract.ModelRiskExplanationDTO{
			ReasonCode: signal.ReasonCode,
			Text:       syntheticRiskExplanationText(signal.ReasonCode),
		})
	}
	return out
}

func buildSyntheticUnknownExplanations(assessment *contract.FinancialRiskAssessmentDTO) []contract.ModelUnknownExplanationDTO {
	var out []contract.ModelUnknownExplanationDTO
	for _, code := range assessment.DataCompleteness.RequiredUnknownReasonCodes {
		out = append(out, contract.ModelUnknownExplanationDTO{
			ReasonCode: code,
			Text:       syntheticUnknownExplanationText(code),
		})
	}
	return out
}

func syntheticRiskExplanationText(reasonCode string) string {
	switch reasonCode {
	case "highDebtPaymentToIncome":
		return "债务还款占收入比例已达到需要关注的水平，建议留意现金流安排。"
	case "highDebtPressureScore", "criticalDebtPressure":
		return "综合债务压力指标显示需要关注还款安排与现金流缓冲。"
	case "negativeProjectedBalance", "cashFlowBelowSafeBalance", "monthEndBelowSafeBalance":
		return "现金流预测显示未来余额可能偏紧，建议关注支出与缓冲资金。"
	case "zeroIncomeWithExpenses":
		return "本月暂无收入记录但存在支出，建议核对记账完整性。"
	default:
		return "系统已识别需要关注的财务信号，建议结合当前事实进一步查看。"
	}
}

func syntheticUnknownExplanationText(reasonCode string) string {
	switch reasonCode {
	case "debtDataMissing":
		return "当前缺少完整债务数据，以下分析未包含债务全貌。"
	case "cashFlowProjectionMissing":
		return "缺少未来现金流预测数据，相关结论可能不完整。"
	default:
		return "部分财务数据尚不完整，结论仅基于当前已知信息。"
	}
}

func modelSelectionKeyFact(label, source, kind string) contract.ModelKeyFactDTO {
	return contract.ModelKeyFactDTO{
		Label:  label,
		Kind:   kind,
		Source: source,
	}
}

func formatMoney(m contract.MoneyDTO) string {
	return "¥" + m.Amount
}
