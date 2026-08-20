package prompt

import (
	"encoding/json"
	"fmt"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// ExplanationSchemaKeys holds assessment-derived enums for model explanation fields.
type ExplanationSchemaKeys struct {
	SignalReasonCodes          []string
	RequiredUnknownReasonCodes []string
}

// BuildExplanationSchemaKeys derives dynamic explanation enums from a risk assessment.
func BuildExplanationSchemaKeys(assessment *contract.FinancialRiskAssessmentDTO) ExplanationSchemaKeys {
	if assessment == nil {
		return ExplanationSchemaKeys{}
	}
	var signalReasons []string
	for _, signal := range assessment.Signals {
		if signal.Level == "safe" {
			continue
		}
		signalReasons = append(signalReasons, signal.ReasonCode)
	}
	requiredUnknowns := append([]string(nil), assessment.DataCompleteness.RequiredUnknownReasonCodes...)
	return ExplanationSchemaKeys{
		SignalReasonCodes:          signalReasons,
		RequiredUnknownReasonCodes: requiredUnknowns,
	}
}

// BuildAssistantAnswerSchema clones the base draft schema and binds request-specific key enums.
func BuildAssistantAnswerSchema(
	base json.RawMessage,
	keys factpack.KeySets,
	explanation ExplanationSchemaKeys,
) (json.RawMessage, error) {
	if len(base) == 0 {
		return nil, fmt.Errorf("base schema is empty")
	}
	var schema map[string]any
	if err := json.Unmarshal(base, &schema); err != nil {
		return nil, fmt.Errorf("unmarshal base schema: %w", err)
	}
	if err := bindAllowedKeys(schema, keys, explanation); err != nil {
		return nil, err
	}
	out, err := json.Marshal(schema)
	if err != nil {
		return nil, fmt.Errorf("marshal bound schema: %w", err)
	}
	if !json.Valid(out) {
		return nil, fmt.Errorf("bound schema is not valid JSON")
	}
	return json.RawMessage(out), nil
}

// ValidateDraftJSONWithSchema validates a draft document against a specific schema document.
func ValidateDraftJSONWithSchema(raw []byte, schemaRaw json.RawMessage) error {
	var schema map[string]any
	if err := json.Unmarshal(schemaRaw, &schema); err != nil {
		return err
	}
	var doc any
	if err := json.Unmarshal(raw, &doc); err != nil {
		return fmt.Errorf("document is not JSON: %w", err)
	}
	return validateSchemaNode(doc, schema, schema, "$")
}

func bindAllowedKeys(schema map[string]any, keys factpack.KeySets, explanation ExplanationSchemaKeys) error {
	props, ok := schema["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing properties")
	}
	defs, ok := schema["$defs"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing $defs")
	}

	if err := bindStringArrayEnum(props, "citedFactKeys", keys.AllowedFactKeys); err != nil {
		return err
	}
	if err := bindDefStringEnum(defs, "keyFact", "source", keys.AllowedKeyFactKeys); err != nil {
		return err
	}
	if len(keys.AllowedKeyFactKeys) == 0 {
		if err := forceEmptyArray(props, "keyFacts"); err != nil {
			return err
		}
	}
	if err := bindDefStringEnum(defs, "reference", "key", keys.ReferenceKeyList); err != nil {
		return err
	}
	if len(keys.ReferenceKeyList) == 0 {
		if err := forceEmptyArray(props, "references"); err != nil {
			return err
		}
	}
	if err := bindExplanationArray(props, defs, "riskExplanations", "riskExplanation", explanation.SignalReasonCodes); err != nil {
		return err
	}
	if err := bindUnknownExplanationArray(props, defs, explanation.RequiredUnknownReasonCodes); err != nil {
		return err
	}
	return nil
}

func bindExplanationArray(
	props map[string]any,
	defs map[string]any,
	arrayField string,
	defName string,
	allowedReasons []string,
) error {
	node, ok := props[arrayField].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing %s array", arrayField)
	}
	if len(allowedReasons) == 0 {
		node["maxItems"] = 0
		return nil
	}
	delete(node, "maxItems")
	node["minItems"] = len(allowedReasons)
	node["maxItems"] = len(allowedReasons)

	def, ok := defs[defName].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing $defs/%s", defName)
	}
	defProps, ok := def["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("$defs/%s missing properties", defName)
	}
	reasonNode, ok := defProps["reasonCode"].(map[string]any)
	if !ok {
		return fmt.Errorf("$defs/%s missing reasonCode", defName)
	}
	reasonNode["enum"] = stringEnumSlice(allowedReasons)
	return nil
}

func bindUnknownExplanationArray(props map[string]any, defs map[string]any, allowedReasons []string) error {
	node, ok := props["unknownExplanations"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing unknownExplanations array")
	}
	if len(allowedReasons) == 0 {
		node["maxItems"] = 0
		return nil
	}
	delete(node, "maxItems")
	node["minItems"] = len(allowedReasons)
	node["maxItems"] = len(allowedReasons)

	def, ok := defs["unknownExplanation"].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing $defs/unknownExplanation")
	}
	defProps, ok := def["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("$defs/unknownExplanation missing properties")
	}
	reasonNode, ok := defProps["reasonCode"].(map[string]any)
	if !ok {
		return fmt.Errorf("$defs/unknownExplanation missing reasonCode")
	}
	reasonNode["enum"] = stringEnumSlice(allowedReasons)
	return nil
}

func bindStringArrayEnum(props map[string]any, field string, allowed []string) error {
	node, ok := props[field].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing %s array", field)
	}
	if len(allowed) == 0 {
		node["maxItems"] = 0
		if items, ok := node["items"].(map[string]any); ok {
			delete(items, "enum")
		}
		return nil
	}
	delete(node, "maxItems")
	items, ok := node["items"].(map[string]any)
	if !ok {
		return fmt.Errorf("%s.items is not an object", field)
	}
	items["enum"] = stringEnumSlice(allowed)
	return nil
}

func bindDefStringEnum(defs map[string]any, defName, field string, allowed []string) error {
	def, ok := defs[defName].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing $defs/%s", defName)
	}
	props, ok := def["properties"].(map[string]any)
	if !ok {
		return fmt.Errorf("$defs/%s missing properties", defName)
	}
	fieldNode, ok := props[field].(map[string]any)
	if !ok {
		return fmt.Errorf("$defs/%s missing %s", defName, field)
	}
	if len(allowed) == 0 {
		delete(fieldNode, "enum")
		fieldNode["not"] = map[string]any{"type": "string"}
		return nil
	}
	delete(fieldNode, "not")
	fieldNode["enum"] = stringEnumSlice(allowed)
	return nil
}

func forceEmptyArray(props map[string]any, field string) error {
	node, ok := props[field].(map[string]any)
	if !ok {
		return fmt.Errorf("schema missing %s array", field)
	}
	node["maxItems"] = 0
	return nil
}

func stringEnumSlice(values []string) []any {
	out := make([]any, len(values))
	for i, v := range values {
		out[i] = v
	}
	return out
}
