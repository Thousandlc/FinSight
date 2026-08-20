package provider

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// ValidateModelDraft checks required model-owned keyFact selection fields.
func ValidateModelDraft(draft contract.ModelAssistantAnswerDraftDTO) error {
	for _, fact := range draft.KeyFacts {
		if strings.TrimSpace(fact.Source) == "" {
			return modelValidationError(fact.Source, "source is required")
		}
		if strings.TrimSpace(fact.Label) == "" {
			return modelValidationError(fact.Source, "label is required")
		}
		if strings.TrimSpace(fact.Kind) == "" {
			return modelValidationError(fact.Source, "kind is required")
		}
	}
	return nil
}

type modelDraftValidationError struct {
	source  string
	message string
}

func (e modelDraftValidationError) Error() string {
	return fmt.Sprintf("model draft validation for %s: %s", e.source, e.message)
}

func modelValidationError(source, message string) error {
	return modelDraftValidationError{source: source, message: message}
}

// MapModelDraftToGateway maps provider transport DTO to the Gateway/iOS contract,
// materializes canonical keyFact values from FactPack, and deterministically assembles
// risk explanation citations from assessment signals.
func MapModelDraftToGateway(
	model contract.ModelAssistantAnswerDraftDTO,
	assessment *contract.FinancialRiskAssessmentDTO,
	facts *contract.MonthlySummaryFactsDTO,
) (contract.AssistantAnswerDraftDTO, error) {
	keyFacts, err := factpack.MaterializeKeyFacts(model.KeyFacts, facts)
	if err != nil {
		return contract.AssistantAnswerDraftDTO{}, fmt.Errorf("keyfact materialization: %w", err)
	}
	unknowns := make([]string, len(model.UnknownExplanations))
	for i, item := range model.UnknownExplanations {
		unknowns[i] = item.Text
	}
	riskExplanations, err := AssembleRiskExplanations(model.RiskExplanations, assessment)
	if err != nil {
		return contract.AssistantAnswerDraftDTO{}, FormatProvenanceAssemblyError(err)
	}
	return contract.AssistantAnswerDraftDTO{
		Title:            model.Title,
		Body:             model.Body,
		Answer:           model.Answer,
		CitedFactKeys:    cloneStrings(model.CitedFactKeys),
		Disclaimer:       model.Disclaimer,
		Unknowns:         unknowns,
		Confidence:       model.Confidence,
		KeyFacts:         keyFacts,
		Warnings:         []contract.Warning{},
		Actions:          []contract.Action{},
		References:       cloneReferences(model.References),
		RiskExplanations: riskExplanations,
	}, nil
}

func cloneStrings(items []string) []string {
	if items == nil {
		return []string{}
	}
	out := make([]string, len(items))
	copy(out, items)
	return out
}

func cloneWarnings(items []contract.Warning) []contract.Warning {
	if items == nil {
		return []contract.Warning{}
	}
	out := make([]contract.Warning, len(items))
	copy(out, items)
	return out
}

func cloneActions(items []contract.Action) []contract.Action {
	if items == nil {
		return []contract.Action{}
	}
	out := make([]contract.Action, len(items))
	copy(out, items)
	return out
}

func cloneReferences(items []contract.Reference) []contract.Reference {
	if items == nil {
		return []contract.Reference{}
	}
	out := make([]contract.Reference, len(items))
	copy(out, items)
	return out
}
