package prompt

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

const KeyFactValueSchemaModeApplicationMaterialized = "applicationMaterialized"
const KeyFactValueSchemaModeFixedNullableObject = "fixedNullableObject"

// KeyFactValueSchemaMeta describes keyFactValue constraints from a bound JSON Schema.
type KeyFactValueSchemaMeta struct {
	SchemaMode           string
	ObjectRequiredFields []string
	TypeEnum             []string
	FieldTypes           map[string]string
	UsesConditionalAllOf bool
	UsesIfThen           bool
}

// DescribeKeyFactValueSchema extracts safe schema metadata without logging prompt content.
func DescribeKeyFactValueSchema(schemaRaw json.RawMessage) (KeyFactValueSchemaMeta, error) {
	var schema map[string]any
	if err := json.Unmarshal(schemaRaw, &schema); err != nil {
		return KeyFactValueSchemaMeta{}, err
	}
	defs, ok := schema["$defs"].(map[string]any)
	if !ok {
		return KeyFactValueSchemaMeta{}, fmt.Errorf("schema missing $defs")
	}
	valueDef, ok := defs["keyFactValue"].(map[string]any)
	if !ok {
		return KeyFactValueSchemaMeta{
			SchemaMode: KeyFactValueSchemaModeApplicationMaterialized,
		}, nil
	}

	meta := KeyFactValueSchemaMeta{
		SchemaMode:           detectKeyFactValueSchemaMode(valueDef),
		ObjectRequiredFields: stringList(valueDef["required"]),
		FieldTypes:           map[string]string{},
		UsesConditionalAllOf: valueDef["allOf"] != nil,
		UsesIfThen:           schemaUsesIfThen(valueDef),
	}
	if props, ok := valueDef["properties"].(map[string]any); ok {
		if typeNode, ok := props["type"].(map[string]any); ok {
			meta.TypeEnum = enumStrings(typeNode["enum"])
		}
		for key, raw := range props {
			if key == "type" {
				continue
			}
			meta.FieldTypes[key] = describeTypeSpec(raw)
		}
	}
	return meta, nil
}

func detectKeyFactValueSchemaMode(valueDef map[string]any) string {
	if valueDef["allOf"] != nil {
		return "conditionalPolymorphic"
	}
	required := stringList(valueDef["required"])
	for _, field := range []string{"textValue", "percentValue", "dateValue"} {
		if containsString(required, field) {
			return KeyFactValueSchemaModeFixedNullableObject
		}
	}
	return "unknown"
}

func schemaUsesIfThen(valueDef map[string]any) bool {
	allOf, ok := valueDef["allOf"].([]any)
	if !ok {
		return false
	}
	for _, item := range allOf {
		clause, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if _, ok := clause["if"]; ok {
			return true
		}
	}
	return false
}

func containsString(list []string, target string) bool {
	for _, item := range list {
		if item == target {
			return true
		}
	}
	return false
}

func describeTypeSpec(raw any) string {
	switch v := raw.(type) {
	case string:
		return v
	case []any:
		parts := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				parts = append(parts, s)
			}
		}
		sort.Strings(parts)
		return strings.Join(parts, "|")
	case map[string]any:
		if t, ok := v["type"].(string); ok {
			return t
		}
		if types, ok := v["type"].([]any); ok {
			return describeTypeSpec(types)
		}
	}
	return ""
}

func (m KeyFactValueSchemaMeta) Summary() string {
	parts := []string{
		fmt.Sprintf("keyFactValueSchemaMode=%s", m.SchemaMode),
		fmt.Sprintf("requiredFields=%s", strings.Join(m.ObjectRequiredFields, ",")),
		fmt.Sprintf("fieldTypes=%s", formatFieldTypes(m.FieldTypes)),
		fmt.Sprintf("typeEnum=%s", strings.Join(m.TypeEnum, ",")),
		fmt.Sprintf("usesAllOf=%t", m.UsesConditionalAllOf),
		fmt.Sprintf("usesIfThen=%t", m.UsesIfThen),
	}
	return strings.Join(parts, " ")
}

func stringList(raw any) []string {
	items, ok := raw.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	sort.Strings(out)
	return out
}

func enumStrings(raw any) []string {
	items, ok := raw.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	sort.Strings(out)
	return out
}

func formatFieldTypes(fields map[string]string) string {
	keys := make([]string, 0, len(fields))
	for k := range fields {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s:%s", k, fields[k]))
	}
	return strings.Join(parts, ",")
}
