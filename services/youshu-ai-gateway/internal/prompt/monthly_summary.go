package prompt

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// MonthlySummaryPromptContractVersion identifies the frozen prompt contract for smoke reruns.
const MonthlySummaryPromptContractVersion = "20260817-f1"

var forbiddenPromptSubstrings = []string{
	"userId",
	"accountId",
	"transactionId",
	"debtId",
	"goalId",
	"budgetId",
	"sourceTransactionIds",
	"sourceDebtIds",
	"sourceAccountIds",
	"BAILIAN_API_KEY",
}

var outputSchemaDescription = map[string]any{
	"allowedTopLevelKeys": []string{
		"title", "body", "answer", "citedFactKeys", "disclaimer", "confidence",
		"keyFacts", "references", "riskExplanations", "unknownExplanations",
	},
	"forbiddenTopLevelKeys": []string{"action", "keyFact", "warning", "reference", "warnings", "actions", "unknowns"},
	"note":                  "Provider model draft uses fixed nullable keyFactValue fields. Warnings/actions are policy-owned. Unknowns derive from unknownExplanations at gateway mapping.",
}

// MonthlySummaryPrompts holds system and user prompts for Bailian.
type MonthlySummaryPrompts struct {
	System string
	User   string
}

// MonthlySummaryPromptContractFingerprint returns a stable hash of system + user template files.
func MonthlySummaryPromptContractFingerprint() (string, error) {
	promptDir, err := findPromptDir()
	if err != nil {
		return "", err
	}
	systemBytes, err := os.ReadFile(filepath.Join(promptDir, "monthly-summary.system.md"))
	if err != nil {
		return "", fmt.Errorf("read system prompt: %w", err)
	}
	templateBytes, err := os.ReadFile(filepath.Join(promptDir, "monthly-summary.user.template.md"))
	if err != nil {
		return "", fmt.Errorf("read user template: %w", err)
	}
	sum := sha256.Sum256(append(systemBytes, templateBytes...))
	return hex.EncodeToString(sum[:])[:16], nil
}

// BuildMonthlySummary renders prompts from request envelope and facts.
func BuildMonthlySummary(req contract.RequestEnvelope) (MonthlySummaryPrompts, error) {
	if req.MonthlySummaryFacts == nil {
		return MonthlySummaryPrompts{}, fmt.Errorf("missing monthlySummaryFacts")
	}
	if req.FinancialRiskAssessment == nil {
		return MonthlySummaryPrompts{}, fmt.Errorf("missing financialRiskAssessment")
	}

	promptDir, err := findPromptDir()
	if err != nil {
		return MonthlySummaryPrompts{}, err
	}

	systemBytes, err := os.ReadFile(filepath.Join(promptDir, "monthly-summary.system.md"))
	if err != nil {
		return MonthlySummaryPrompts{}, fmt.Errorf("read system prompt: %w", err)
	}
	templateBytes, err := os.ReadFile(filepath.Join(promptDir, "monthly-summary.user.template.md"))
	if err != nil {
		return MonthlySummaryPrompts{}, fmt.Errorf("read user template: %w", err)
	}

	safeContext, err := sanitizeContext(req.AssistantRequest.Context)
	if err != nil {
		return MonthlySummaryPrompts{}, err
	}
	contextJSON, err := json.MarshalIndent(safeContext, "", "  ")
	if err != nil {
		return MonthlySummaryPrompts{}, err
	}

	factsJSON, err := json.MarshalIndent(req.MonthlySummaryFacts, "", "  ")
	if err != nil {
		return MonthlySummaryPrompts{}, err
	}
	assessmentJSON, err := json.MarshalIndent(req.FinancialRiskAssessment, "", "  ")
	if err != nil {
		return MonthlySummaryPrompts{}, err
	}

	keySets := factpack.BuildKeySets(req.MonthlySummaryFacts)
	amountKeysJSON, _ := json.Marshal(keySets.AmountKeyList)
	factKeysJSON, _ := json.Marshal(keySets.FactKeyList)
	refKeysJSON, _ := json.Marshal(keySets.ReferenceKeyList)
	schemaJSON, _ := json.MarshalIndent(outputSchemaDescription, "", "  ")

	data := map[string]string{
		"FinancialContextJSON":        string(contextJSON),
		"MonthlySummaryFactsJSON":     string(factsJSON),
		"FinancialRiskAssessmentJSON": string(assessmentJSON),
		"AllowedAmountKeysJSON":       string(amountKeysJSON),
		"AllowedFactKeysJSON":         string(factKeysJSON),
		"AllowedReferenceKeysJSON":    string(refKeysJSON),
		"OutputSchemaJSON":            string(schemaJSON),
	}

	tmpl, err := template.New("user").Parse(string(templateBytes))
	if err != nil {
		return MonthlySummaryPrompts{}, fmt.Errorf("parse user template: %w", err)
	}
	var userBuf bytes.Buffer
	if err := tmpl.Execute(&userBuf, data); err != nil {
		return MonthlySummaryPrompts{}, fmt.Errorf("execute user template: %w", err)
	}

	prompts := MonthlySummaryPrompts{
		System: string(systemBytes),
		User:   userBuf.String(),
	}
	if err := validatePromptSafety(prompts.System + prompts.User); err != nil {
		return MonthlySummaryPrompts{}, err
	}
	return prompts, nil
}

func sanitizeContext(ctx map[string]any) (map[string]any, error) {
	raw, err := json.Marshal(ctx)
	if err != nil {
		return nil, err
	}
	var copy map[string]any
	if err := json.Unmarshal(raw, &copy); err != nil {
		return nil, err
	}
	stripForbiddenFields(copy)
	return copy, nil
}

func stripForbiddenFields(value any) {
	switch v := value.(type) {
	case map[string]any:
		for key := range v {
			lower := strings.ToLower(key)
			if isForbiddenField(lower) {
				delete(v, key)
				continue
			}
			stripForbiddenFields(v[key])
		}
	case []any:
		for _, item := range v {
			stripForbiddenFields(item)
		}
	}
}

func isForbiddenField(key string) bool {
	forbidden := []string{
		"userid", "accountid", "transactionid", "debtid", "goalid", "budgetid",
		"sourcetransactionids", "sourcedebtids", "sourceaccountids",
	}
	for _, f := range forbidden {
		if key == f {
			return true
		}
	}
	return false
}

func validatePromptSafety(prompt string) error {
	lower := strings.ToLower(prompt)
	for _, forbidden := range forbiddenPromptSubstrings {
		if strings.Contains(lower, strings.ToLower(forbidden)) {
			return fmt.Errorf("prompt contains forbidden content: %s", forbidden)
		}
	}
	return nil
}

func findPromptDir() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	dir := wd
	for {
		candidate := filepath.Join(dir, "prompts", "financial-assistant", "v1")
		if st, err := os.Stat(candidate); err == nil && st.IsDir() {
			return candidate, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", fmt.Errorf("prompts/financial-assistant/v1 not found from %s", wd)
}
