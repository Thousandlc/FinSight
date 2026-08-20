package provider

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

const KeyFactSelectionFailureCode = "keyFactSourceNotAllowed"

type keyFactSelectionError struct {
	source string
}

func (e keyFactSelectionError) Error() string {
	return fmt.Sprintf("keyFact source not allowed: %s", e.source)
}

// ValidateKeyFactSelection ensures model-selected keyFact sources belong to AllowedKeyFactKeys.
func ValidateKeyFactSelection(model contract.ModelAssistantAnswerDraftDTO, keySets factpack.KeySets) error {
	allowed := make(map[string]struct{}, len(keySets.AllowedKeyFactKeys))
	for _, key := range keySets.AllowedKeyFactKeys {
		allowed[key] = struct{}{}
	}
	for _, fact := range model.KeyFacts {
		source := strings.TrimSpace(fact.Source)
		if source == "" {
			return keyFactSelectionError{source: source}
		}
		if _, ok := allowed[source]; !ok {
			return keyFactSelectionError{source: source}
		}
	}
	return nil
}
