package prompt

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	AssistantAnswerDraftSchemaFile = "assistant-answer-draft.schema.json"
	AssistantAnswerDraftSchemaName = "youshu_assistant_answer_draft_v1"
)

var AllowedDraftTopLevelKeys = []string{
	"title",
	"body",
	"answer",
	"citedFactKeys",
	"disclaimer",
	"unknowns",
	"confidence",
	"keyFacts",
	"warnings",
	"actions",
	"references",
}

func IsAllowedDraftTopLevelKey(key string) bool {
	for _, allowed := range AllowedDraftTopLevelKeys {
		if key == allowed {
			return true
		}
	}
	return false
}

func LoadAssistantAnswerDraftSchema() (json.RawMessage, error) {
	dir, err := findPromptDir()
	if err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(filepath.Join(dir, AssistantAnswerDraftSchemaFile))
	if err != nil {
		return nil, fmt.Errorf("read draft schema: %w", err)
	}
	if !json.Valid(raw) {
		return nil, fmt.Errorf("draft schema is not valid JSON")
	}
	return json.RawMessage(raw), nil
}

func ValidateDraftJSON(raw []byte) error {
	schemaRaw, err := LoadAssistantAnswerDraftSchema()
	if err != nil {
		return err
	}
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

func validateSchemaNode(doc any, schema map[string]any, root map[string]any, path string) error {
	if ref, ok := schema["$ref"].(string); ok {
		resolved, err := resolveRef(ref, root)
		if err != nil {
			return err
		}
		return validateSchemaNode(doc, resolved, root, path)
	}
	if c, ok := schema["const"]; ok {
		if !enumContains([]any{c}, doc) {
			return fmt.Errorf("%s: value does not match const", path)
		}
		return nil
	}
	if doc == nil {
		if typeAllowsNull(schema["type"]) {
			return nil
		}
		return fmt.Errorf("%s: expected non-null", path)
	}
	if err := validateSchemaType(doc, schema["type"], path); err != nil {
		return err
	}
	if enums, ok := schema["enum"].([]any); ok {
		if !enumContains(enums, doc) {
			return fmt.Errorf("%s: value not in enum", path)
		}
	}
	if allOf, ok := schema["allOf"].([]any); ok {
		for _, item := range allOf {
			clause, ok := item.(map[string]any)
			if !ok {
				continue
			}
			if ifSchema, ok := clause["if"].(map[string]any); ok {
				if thenSchema, ok := clause["then"].(map[string]any); ok {
					if validateSchemaNode(doc, ifSchema, root, path) == nil {
						if err := applyThenSchema(doc, thenSchema, root, path); err != nil {
							return err
						}
					}
					continue
				}
			}
			if err := validateSchemaNode(doc, clause, root, path); err != nil {
				return err
			}
		}
	}
	switch typed := doc.(type) {
	case map[string]any:
		if add, ok := schema["additionalProperties"]; ok {
			if allowed, isBool := add.(bool); isBool && !allowed {
				props, _ := schema["properties"].(map[string]any)
				for key := range typed {
					if _, exists := props[key]; !exists {
						return fmt.Errorf("%s: unexpected property %s", path, key)
					}
				}
			}
		}
		if required, ok := schema["required"].([]any); ok {
			for _, item := range required {
				key, _ := item.(string)
				if _, exists := typed[key]; !exists {
					return fmt.Errorf("%s: missing required property %s", path, key)
				}
			}
		}
		props, _ := schema["properties"].(map[string]any)
		for key, value := range typed {
			sub, ok := props[key].(map[string]any)
			if !ok {
				continue
			}
			if err := validateSchemaNode(value, sub, root, path+"."+key); err != nil {
				return err
			}
		}
	case []any:
		items, _ := schema["items"].(map[string]any)
		if items == nil {
			return nil
		}
		for i, item := range typed {
			if err := validateSchemaNode(item, items, root, fmt.Sprintf("%s[%d]", path, i)); err != nil {
				return err
			}
		}
	}
	return nil
}

func applyThenSchema(doc any, thenSchema map[string]any, root map[string]any, path string) error {
	obj, ok := doc.(map[string]any)
	if !ok {
		return fmt.Errorf("%s: expected object", path)
	}
	if required, ok := thenSchema["required"].([]any); ok {
		for _, item := range required {
			key, _ := item.(string)
			if _, exists := obj[key]; !exists {
				return fmt.Errorf("%s: missing required property %s", path, key)
			}
		}
	}
	props, _ := thenSchema["properties"].(map[string]any)
	for key, value := range obj {
		sub, ok := props[key].(map[string]any)
		if !ok {
			continue
		}
		if err := validateSchemaNode(value, sub, root, path+"."+key); err != nil {
			return err
		}
	}
	return nil
}

func validateSchemaType(doc any, typeSpec any, path string) error {
	allowed := typeList(typeSpec)
	if len(allowed) == 0 {
		return nil
	}
	actual := jsonTypeName(doc)
	for _, candidate := range allowed {
		if candidate == actual {
			return nil
		}
		if candidate == "number" && actual == "integer" {
			return nil
		}
	}
	return fmt.Errorf("%s: type %s is not allowed", path, actual)
}

func typeList(typeSpec any) []string {
	switch v := typeSpec.(type) {
	case string:
		return []string{v}
	case []any:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				out = append(out, s)
			}
		}
		return out
	default:
		return nil
	}
}

func typeAllowsNull(typeSpec any) bool {
	for _, item := range typeList(typeSpec) {
		if item == "null" {
			return true
		}
	}
	return false
}

func jsonTypeName(doc any) string {
	switch doc.(type) {
	case map[string]any:
		return "object"
	case []any:
		return "array"
	case string:
		return "string"
	case float64:
		return "number"
	case bool:
		return "boolean"
	case nil:
		return "null"
	default:
		return fmt.Sprintf("%T", doc)
	}
}

func enumContains(enums []any, doc any) bool {
	encoded, _ := json.Marshal(doc)
	for _, item := range enums {
		itemJSON, _ := json.Marshal(item)
		if string(encoded) == string(itemJSON) {
			return true
		}
	}
	return false
}

func resolveRef(ref string, root map[string]any) (map[string]any, error) {
	if !strings.HasPrefix(ref, "#/") {
		return nil, fmt.Errorf("unsupported $ref %s", ref)
	}
	cur := any(root)
	for _, part := range strings.Split(strings.TrimPrefix(ref, "#/"), "/") {
		obj, ok := cur.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("cannot resolve $ref %s", ref)
		}
		cur, ok = obj[part]
		if !ok {
			return nil, fmt.Errorf("cannot resolve $ref %s", ref)
		}
	}
	resolved, ok := cur.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("$ref %s is not an object", ref)
	}
	return resolved, nil
}
