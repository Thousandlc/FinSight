package eval

import (
	"encoding/json"
	"fmt"
	"sort"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
)

// ValidateDynamicSchemaOffline verifies dynamic schema enums bind to golden assessment and facts.
func ValidateDynamicSchemaOffline(c EvaluationCase, assessment contract.FinancialRiskAssessmentDTO) error {
	if c.Envelope.MonthlySummaryFacts == nil {
		return fmt.Errorf("case %s missing facts", c.ID)
	}
	base, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		return fmt.Errorf("load model schema: %w", err)
	}
	keys := factpack.BuildKeySets(c.Envelope.MonthlySummaryFacts)
	explanationKeys := prompt.BuildExplanationSchemaKeys(&assessment)
	bound, err := prompt.BuildAssistantAnswerSchema(base, keys, explanationKeys)
	if err != nil {
		return fmt.Errorf("bind schema: %w", err)
	}

	expectedRisk := sortedStrings(expectedSignalReasonCodes(&assessment))
	if !sortedEqual(expectedRisk, sortedStrings(explanationKeys.SignalReasonCodes)) {
		return fmt.Errorf("risk explanation keys mismatch")
	}
	expectedUnknown := sortedStrings(assessment.DataCompleteness.RequiredUnknownReasonCodes)
	if !sortedEqual(expectedUnknown, sortedStrings(explanationKeys.RequiredUnknownReasonCodes)) {
		return fmt.Errorf("unknown explanation keys mismatch")
	}

	var schema map[string]any
	if err := json.Unmarshal(bound, &schema); err != nil {
		return fmt.Errorf("unmarshal bound schema: %w", err)
	}
	if err := validateRiskExplanationSchema(schema, expectedRisk); err != nil {
		return err
	}
	if err := validateUnknownExplanationSchema(schema, expectedUnknown); err != nil {
		return err
	}
	if len(keys.AllowedFactKeys) == 0 {
		return fmt.Errorf("missing allowed fact keys")
	}
	return nil
}

func validateRiskExplanationSchema(schema map[string]any, expected []string) error {
	props, ok := schema["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing properties")
	}
	node, ok := props["riskExplanations"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing riskExplanations")
	}
	if len(expected) == 0 {
		if maxItems, ok := node["maxItems"].(float64); !ok || int(maxItems) != 0 {
			return fmt.Errorf("expected empty riskExplanations schema")
		}
		return nil
	}
	enum, err := extractDefReasonEnum(schema, "riskExplanation")
	if err != nil {
		return err
	}
	if !sortedEqual(sortedStrings(enum), expected) {
		return fmt.Errorf("bound risk enum mismatch")
	}
	return nil
}

func validateUnknownExplanationSchema(schema map[string]any, expected []string) error {
	props, ok := schema["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing properties")
	}
	node, ok := props["unknownExplanations"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing unknownExplanations")
	}
	if len(expected) == 0 {
		if maxItems, ok := node["maxItems"].(float64); !ok || int(maxItems) != 0 {
			return fmt.Errorf("expected empty unknownExplanations schema")
		}
		return nil
	}
	enum, err := extractDefReasonEnum(schema, "unknownExplanation")
	if err != nil {
		return err
	}
	if !sortedEqual(sortedStrings(enum), expected) {
		return fmt.Errorf("bound unknown enum mismatch")
	}
	return nil
}

func extractDefReasonEnum(schema map[string]any, defName string) ([]string, error) {
	defs, ok := schema["$defs"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("schema missing $defs")
	}
	def, ok := defs[defName].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("schema missing def %s", defName)
	}
	props, ok := def["properties"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("def %s missing properties", defName)
	}
	reasonNode, ok := props["reasonCode"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("def %s missing reasonCode", defName)
	}
	rawEnum, ok := reasonNode["enum"].([]any)
	if !ok {
		return nil, fmt.Errorf("def %s reasonCode enum missing", defName)
	}
	out := make([]string, 0, len(rawEnum))
	for _, item := range rawEnum {
		value, ok := item.(string)
		if !ok {
			return nil, fmt.Errorf("enum item is not string")
		}
		out = append(out, value)
	}
	return out, nil
}

func sortedStrings(items []string) []string {
	out := append([]string(nil), items...)
	sort.Strings(out)
	return out
}

func sortedEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
