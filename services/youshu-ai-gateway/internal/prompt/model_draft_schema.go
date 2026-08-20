package prompt

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

const (
	AssistantAnswerModelDraftSchemaFile = "assistant-answer-model-draft.schema.json"
	AssistantAnswerModelDraftSchemaName = "youshu_assistant_answer_model_draft_v1"
	// ModelSchemaContractMarker identifies the C2B keyFact ownership contract (source-only model keyFacts).
	ModelSchemaContractMarker = "c2b-keyfact-materialized"
)

// AllowedModelDraftTopLevelKeys lists provider transport top-level keys.
var AllowedModelDraftTopLevelKeys = []string{
	"title",
	"body",
	"answer",
	"citedFactKeys",
	"disclaimer",
	"confidence",
	"keyFacts",
	"references",
	"riskExplanations",
	"unknownExplanations",
}

func IsAllowedModelDraftTopLevelKey(key string) bool {
	for _, allowed := range AllowedModelDraftTopLevelKeys {
		if key == allowed {
			return true
		}
	}
	return false
}

// LoadAssistantAnswerModelDraftSchema loads the fixed-shape provider transport schema.
func LoadAssistantAnswerModelDraftSchema() (json.RawMessage, error) {
	dir, err := findPromptDir()
	if err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(filepath.Join(dir, AssistantAnswerModelDraftSchemaFile))
	if err != nil {
		return nil, fmt.Errorf("read model draft schema: %w", err)
	}
	if !json.Valid(raw) {
		return nil, fmt.Errorf("model draft schema is not valid JSON")
	}
	return json.RawMessage(raw), nil
}

// ModelDraftSchemaFingerprint returns a stable hash of the base model draft JSON schema file.
func ModelDraftSchemaFingerprint() (string, error) {
	raw, err := LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])[:16], nil
}
