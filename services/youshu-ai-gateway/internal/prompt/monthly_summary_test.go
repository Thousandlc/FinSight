package prompt_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
)

func sampleEnvelope() contract.RequestEnvelope {
	pct := "16.67"
	risk := "预计本月中有若干天余额接近安全线。"
	safe := contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"}
	return contract.RequestEnvelope{
		SchemaVersion: "v1",
		RequestID:     "prompt-test-1",
		Operation:     contract.OperationMonthlySummary,
		AssistantRequest: contract.AssistantRequestDTO{
			Question: "",
			Intent:   "unknown",
			Context: map[string]any{
				"meta": map[string]any{"currencyCode": "CNY"},
				"balance": map[string]any{
					"availableCash":     map[string]any{"amount": "10000", "currencyCode": "CNY"},
					"estimatedMonthEnd": map[string]any{"amount": "8000", "currencyCode": "CNY"},
				},
				"monthly": map[string]any{
					"income":      map[string]any{"amount": "12000", "currencyCode": "CNY"},
					"expense":     map[string]any{"amount": "6000", "currencyCode": "CNY"},
					"debtPayment": map[string]any{"amount": "2000", "currencyCode": "CNY"},
				},
			},
		},
		MonthlySummaryFacts: &contract.MonthlySummaryFactsDTO{
			AvailableCash:              contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
			MonthlyIncome:              contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
			MonthlyExpense:             contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
			MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
			DebtPaymentToIncomePercent: &pct,
			PrimaryPressure:            "日常支出",
			EstimatedMonthEndBalance:   contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
			CashFlowRiskExplanation:    &risk,
			SafeBalance:                &safe,
			SourceLabels:               []string{"Account", "Transaction", "Debt"},
		},
		FinancialRiskAssessment: &contract.FinancialRiskAssessmentDTO{
			OverallLevel:  "warning",
			PolicyVersion: "v1",
			DebtDataState: "knownDebt",
			Signals: []contract.FinancialRiskSignalDTO{
				{
					Kind:                          "debt",
					Level:                         "warning",
					ReasonCode:                    "highDebtPaymentToIncome",
					SourceFactKeys:                []string{"debtPaymentToIncomePercent"},
					RecommendedActionDestinations: []string{"debt", "cashFlow"},
				},
			},
			DataCompleteness: contract.FinancialDataCompletenessDTO{
				Debt:                       "known",
				CashFlowProjection:         "known",
				Income:                     "known",
				Expense:                    "known",
				RequiredUnknownReasonCodes: []string{},
			},
		},
	}
}

func TestPromptContainsRequiredSections(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	combined := prompts.System + prompts.User
	for _, section := range []string{
		"financial_context",
		"monthly_summary_facts",
		"financial_risk_assessment",
		"allowed_amount_keys",
		"allowed_fact_keys",
		"allowed_reference_keys",
		"expected_output_schema",
	} {
		if !strings.Contains(combined, section) {
			t.Fatalf("missing section %s", section)
		}
	}
	if !strings.Contains(prompts.User, "10000") {
		t.Fatal("expected facts amount in user prompt")
	}
}

func TestPromptDoesNotContainForbiddenIdentifiers(t *testing.T) {
	env := sampleEnvelope()
	env.AssistantRequest.Context["userId"] = "secret-uuid"
	env.AssistantRequest.Context["transactionId"] = "tx-1"
	env.AssistantRequest.Context["sourceTransactionIds"] = []string{"a", "b"}

	prompts, err := prompt.BuildMonthlySummary(env)
	if err != nil {
		t.Fatal(err)
	}
	combined := strings.ToLower(prompts.System + prompts.User)
	for _, forbidden := range []string{
		"userid", "transactionid", "sourcetransactionids", "accountid", "debtid",
	} {
		if strings.Contains(combined, forbidden) {
			t.Fatalf("prompt contains forbidden %s", forbidden)
		}
	}
}

func TestPromptAllowedKeysJSONValid(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	var keys []string
	start := strings.Index(prompts.User, "[")
	end := strings.Index(prompts.User, "]")
	if start < 0 || end <= start {
		t.Fatal("allowed keys array not found")
	}
	if err := json.Unmarshal([]byte(prompts.User[start:end+1]), &keys); err != nil {
		t.Fatalf("allowed keys not valid json array: %v", err)
	}
}

func TestSystemPromptRulesPresent(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(prompts.System, "不得编造金额") {
		t.Fatal("system prompt missing core rule")
	}
	if !strings.Contains(prompts.System, "JSON") {
		t.Fatal("system prompt missing JSON requirement")
	}
}

func TestPromptRequiresMoneyAmountJSONNumber(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	combined := prompts.System + prompts.User
	if !strings.Contains(combined, `"amount":10000`) {
		t.Fatal("prompt must show money amount as JSON number")
	}
	if !strings.Contains(combined, "JSON number") {
		t.Fatal("prompt must state money amount is JSON number")
	}
	if !strings.Contains(prompts.System, `"amount":"10000"`) {
		t.Fatal("prompt must explicitly forbid quoted string amount")
	}
	if !strings.Contains(prompts.System, "错误") {
		t.Fatal("quoted amount example must be marked as incorrect")
	}
	if !strings.Contains(combined, "JSON 类型转换") || !strings.Contains(combined, "不得自行计算") {
		t.Fatal("prompt must distinguish JSON type conversion from financial calculation")
	}
}

func TestExpectedOutputSchemaMatchesGatewayDTOTypes(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	schema := prompts.User
	for _, key := range []string{"title", "body", "answer", "citedFactKeys", "keyFacts", "riskExplanations", "unknownExplanations", "references"} {
		if !strings.Contains(schema, key) {
			t.Fatalf("expected output schema missing %s", key)
		}
	}
	if !strings.Contains(schema, "forbiddenTopLevelKeys") {
		t.Fatal("schema must forbid singular documentation keys")
	}
}

func TestB4BPromptContractRules(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	combined := prompts.System + prompts.User

	required := []string{
		"authoritative explanation worklist",
		"exactly one",
		"exactly once",
		"partial 并不表示",
		"structured explanation 是 mandatory",
		"knownNoDebt",
		"语义层面",
		"输出优先级",
		"machine value",
	}
	for _, phrase := range required {
		if !strings.Contains(combined, phrase) {
			t.Fatalf("missing B4B prompt rule phrase: %q", phrase)
		}
	}

	forbidden := []string{
		"E01_partial_debt_data",
		"C01_no_debt",
		"E01",
		"C01",
		"20%",
		">=20",
		"DTI >=",
		"critical debt",
		"safe balance threshold",
		"BAILIAN_API_KEY",
	}
	for _, phrase := range forbidden {
		if strings.Contains(combined, phrase) {
			t.Fatalf("prompt must not contain forbidden phrase: %q", phrase)
		}
	}
}

func TestB5EPromptOwnershipCleanup(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	combined := prompts.System + prompts.User

	required := []string{
		"authoritative explanation worklist",
		"exactly once",
		"exact reasonCode",
		"系统 deterministic 注入",
		"你无需输出 citedFactKeys",
	}
	for _, phrase := range required {
		if !strings.Contains(combined, phrase) {
			t.Fatalf("missing B5E prompt phrase: %q", phrase)
		}
	}

	forbidden := []string{
		"proxy substitution",
		"authoritative provenance 集合",
		"sourceFactKeys-only",
		"exact signal provenance",
	}
	for _, phrase := range forbidden {
		if strings.Contains(combined, phrase) {
			t.Fatalf("prompt must not contain removed B5C phrase: %q", phrase)
		}
	}
}

func TestB5EPromptContractVersionAndFingerprint(t *testing.T) {
	if prompt.MonthlySummaryPromptContractVersion != "20260817-f1" {
		t.Fatalf("unexpected prompt contract version: %s", prompt.MonthlySummaryPromptContractVersion)
	}
	fp, err := prompt.MonthlySummaryPromptContractFingerprint()
	if err != nil {
		t.Fatal(err)
	}
	if len(fp) != 16 {
		t.Fatalf("expected 16-char fingerprint, got %q", fp)
	}
	const expectedFingerprint = "b32b12e5bcfbfad5"
	if fp != expectedFingerprint {
		t.Fatalf("prompt fingerprint changed: got %s want %s", fp, expectedFingerprint)
	}
}

func TestB4BPromptUnknownContractUnchanged(t *testing.T) {
	prompts, err := prompt.BuildMonthlySummary(sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	combined := prompts.System + prompts.User
	if !strings.Contains(combined, "requiredUnknownReasonCodes") {
		t.Fatal("unknown contract must remain in prompt")
	}
	if !strings.Contains(combined, "unknownExplanations") {
		t.Fatal("unknownExplanations contract must remain in prompt")
	}
	if strings.Contains(combined, "warnings 与 actions 由系统策略引擎生成") {
		// warnings/actions still policy-owned, not model output
	} else {
		t.Fatal("prompt must keep warnings/actions ownership note")
	}
}
