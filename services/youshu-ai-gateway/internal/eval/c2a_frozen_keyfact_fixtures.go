package eval

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

const c2aFrozenArtifactName = "full-v2-20260817-070704.json"

// C2AFrozenRunSnapshot is the minimal per-run structure used for C2A offline adjudication.
type C2AFrozenRunSnapshot struct {
	CaseID             string
	RunIndex           int
	ContractPass       bool
	FactValidation     string
	InvalidKeyFactSource int
	FailureClass       string
	StructuredSnapshot StructuredSnapshot
	AuditVerdict       string
	EvaluationVerdict  string
}

func c2aFrozenArtifactPath() string {
	dir, err := ResolveOutputDir(DefaultOutputDir)
	if err != nil {
		dir = DefaultOutputDir
	}
	return filepath.Join(dir, c2aFrozenArtifactName)
}

func loadC2AFrozenReport(t interface {
	Helper()
	Fatal(...any)
}) EvaluationReport {
	t.Helper()
	path := c2aFrozenArtifactPath()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal("read frozen C2 artifact:", err)
	}
	var report EvaluationReport
	if err := json.Unmarshal(data, &report); err != nil {
		t.Fatal("unmarshal frozen C2 artifact:", err)
	}
	return report
}

func findC2AFrozenRun(report EvaluationReport, caseID string, runIndex int) (RunResult, bool) {
	for _, r := range report.Results {
		if r.CaseID == caseID && r.RunIndex == runIndex {
			return r, true
		}
	}
	return RunResult{}, false
}

func c2aCaseFacts(caseID string) *contract.MonthlySummaryFactsDTO {
	c, err := findCaseByID(caseID)
	if err != nil {
		panic(err)
	}
	return c.Envelope.MonthlySummaryFacts
}

// c2aDraftFromFrozenC01 reproduces C01 run=1 keyFact/citation pattern from frozen C2 evidence.
func c2aDraftFromFrozenC01() contract.AssistantAnswerDraftDTO {
	payment := c2aParseAmount("0")
	currency := "CNY"
	income := c2aParseAmount("12000")
	expense := c2aParseAmount("6000")
	cash := c2aParseAmount("15000")
	monthEnd := c2aParseAmount("12000")
	pressure := "日常支出"
	return contract.AssistantAnswerDraftDTO{
		Title:  "本月财务总结",
		Body:   "系统确认您当前无未结清债务。",
		Answer: "本月财务状况良好。",
		CitedFactKeys: []string{
			"monthlyIncome", "monthlyExpense", "primaryPressure",
			"availableCash", "estimatedMonthEndBalance", "monthlyDebtPayment",
		},
		KeyFacts: []contract.KeyFact{
			{Label: "收入", Kind: "income", Source: "monthlyIncome", Value: contract.KeyFactValue{Type: "money", Amount: &income, CurrencyCode: &currency}},
			{Label: "支出", Kind: "expense", Source: "monthlyExpense", Value: contract.KeyFactValue{Type: "money", Amount: &expense, CurrencyCode: &currency}},
			{Label: "压力", Kind: "other", Source: "primaryPressure", Value: contract.KeyFactValue{Type: "text", TextValue: &pressure}},
			{Label: "可用", Kind: "balance", Source: "availableCash", Value: contract.KeyFactValue{Type: "money", Amount: &cash, CurrencyCode: &currency}},
			{Label: "月末", Kind: "balance", Source: "estimatedMonthEndBalance", Value: contract.KeyFactValue{Type: "money", Amount: &monthEnd, CurrencyCode: &currency}},
			{Label: "还款", Kind: "debt", Source: "monthlyDebtPayment", Value: contract.KeyFactValue{Type: "money", Amount: &payment, CurrencyCode: &currency}},
		},
	}
}

// c2aDraftC04FailPattern reproduces C04 run=1: DTI keyFact emitted as money (invalid for percent source).
func c2aDraftC04FailPattern(facts *contract.MonthlySummaryFactsDTO) contract.AssistantAnswerDraftDTO {
	draft := c2aDraftC04PassPattern(facts)
	dtiAmount := c2aParseAmount("35")
	currency := "CNY"
	draft.KeyFacts = append(draft.KeyFacts, contract.KeyFact{
		Label:  "DTI",
		Kind:   "debt",
		Source: "debtPaymentToIncomePercent",
		Value:  contract.KeyFactValue{Type: "money", Amount: &dtiAmount, CurrencyCode: &currency},
	})
	draft.CitedFactKeys = append(draft.CitedFactKeys, "debtPaymentToIncomePercent", "debtPressureLevel")
	return draft
}

// c2aDraftC04PassPattern mirrors C06-style debtPressureLevel text keyFact without invalid DTI row.
func c2aDraftC04PassPattern(facts *contract.MonthlySummaryFactsDTO) contract.AssistantAnswerDraftDTO {
	currency := "CNY"
	income := c2aParseAmount(facts.MonthlyIncome.Amount)
	expense := c2aParseAmount(facts.MonthlyExpense.Amount)
	cash := c2aParseAmount(facts.AvailableCash.Amount)
	monthEnd := c2aParseAmount(facts.EstimatedMonthEndBalance.Amount)
	payment := c2aParseAmount(facts.MonthlyDebtPayment.Amount)
	level := "high"
	if facts.DebtPressureLevel != nil {
		level = *facts.DebtPressureLevel
	}
	return contract.AssistantAnswerDraftDTO{
		CitedFactKeys: []string{
			"monthlyIncome", "monthlyExpense", "availableCash",
			"estimatedMonthEndBalance", "monthlyDebtPayment", "debtPressureLevel",
		},
		KeyFacts: []contract.KeyFact{
			{Label: "收入", Kind: "income", Source: "monthlyIncome", Value: contract.KeyFactValue{Type: "money", Amount: &income, CurrencyCode: &currency}},
			{Label: "支出", Kind: "expense", Source: "monthlyExpense", Value: contract.KeyFactValue{Type: "money", Amount: &expense, CurrencyCode: &currency}},
			{Label: "可用", Kind: "balance", Source: "availableCash", Value: contract.KeyFactValue{Type: "money", Amount: &cash, CurrencyCode: &currency}},
			{Label: "月末", Kind: "balance", Source: "estimatedMonthEndBalance", Value: contract.KeyFactValue{Type: "money", Amount: &monthEnd, CurrencyCode: &currency}},
			{Label: "还款", Kind: "debt", Source: "monthlyDebtPayment", Value: contract.KeyFactValue{Type: "money", Amount: &payment, CurrencyCode: &currency}},
			{Label: "压力", Kind: "other", Source: "debtPressureLevel", Value: contract.KeyFactValue{Type: "text", TextValue: &level}},
		},
	}
}

// c2aDraftE01FailPattern reproduces E01 run=1 invalid DTI keyFact typing.
func c2aDraftE01FailPattern(facts *contract.MonthlySummaryFactsDTO) contract.AssistantAnswerDraftDTO {
	draft := c2aDraftE01PassPattern(facts)
	dtiAmount := c2aParseAmount("25")
	currency := "CNY"
	draft.KeyFacts = append(draft.KeyFacts, contract.KeyFact{
		Label:  "DTI",
		Kind:   "other",
		Source: "debtPaymentToIncomePercent",
		Value:  contract.KeyFactValue{Type: "money", Amount: &dtiAmount, CurrencyCode: &currency},
	})
	return draft
}

// c2aDraftE01PassPattern mirrors E01 run=3: DTI only in citations, not as invalid keyFact row.
func c2aDraftE01PassPattern(facts *contract.MonthlySummaryFactsDTO) contract.AssistantAnswerDraftDTO {
	currency := "CNY"
	cash := c2aParseAmount(facts.AvailableCash.Amount)
	monthEnd := c2aParseAmount(facts.EstimatedMonthEndBalance.Amount)
	income := c2aParseAmount(facts.MonthlyIncome.Amount)
	expense := c2aParseAmount(facts.MonthlyExpense.Amount)
	payment := c2aParseAmount(facts.MonthlyDebtPayment.Amount)
	return contract.AssistantAnswerDraftDTO{
		CitedFactKeys: []string{
			"availableCash", "estimatedMonthEndBalance", "monthlyIncome",
			"monthlyExpense", "monthlyDebtPayment", "debtPaymentToIncomePercent", "primaryPressure",
		},
		KeyFacts: []contract.KeyFact{
			{Label: "可用", Kind: "balance", Source: "availableCash", Value: contract.KeyFactValue{Type: "money", Amount: &cash, CurrencyCode: &currency}},
			{Label: "月末", Kind: "balance", Source: "estimatedMonthEndBalance", Value: contract.KeyFactValue{Type: "money", Amount: &monthEnd, CurrencyCode: &currency}},
			{Label: "收入", Kind: "income", Source: "monthlyIncome", Value: contract.KeyFactValue{Type: "money", Amount: &income, CurrencyCode: &currency}},
			{Label: "支出", Kind: "expense", Source: "monthlyExpense", Value: contract.KeyFactValue{Type: "money", Amount: &expense, CurrencyCode: &currency}},
			{Label: "还款", Kind: "debt", Source: "monthlyDebtPayment", Value: contract.KeyFactValue{Type: "money", Amount: &payment, CurrencyCode: &currency}},
		},
	}
}

func c2aParseAmount(s string) float64 {
	v, _ := strconv.ParseFloat(strings.TrimSpace(s), 64)
	return v
}
