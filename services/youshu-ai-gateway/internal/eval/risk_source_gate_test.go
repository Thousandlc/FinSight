package eval

import (
	"context"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

type noopUpstream struct {
	calls int
}

func (n *noopUpstream) DiagnoseMonthlySummary(context.Context, contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
	n.calls++
	return contract.AssistantAnswerDraftDTO{}, provider.DecodeDiagnostics{}, nil
}

func TestPreProviderMismatchBlocksWithoutHTTP(t *testing.T) {
	cases := AllCases()
	var target EvaluationCase
	for _, c := range cases {
		if c.ID == E01DiagnosticCaseID {
			target = c
			break
		}
	}
	facts := *target.Envelope.MonthlySummaryFacts
	facts.DebtPaymentToIncomePercent = nil
	target.Envelope.MonthlySummaryFacts = &facts

	upstream := &noopUpstream{}
	result := executeRun(context.Background(), upstream, target, 1, ResolveEvaluationMode())
	if upstream.calls != 0 {
		t.Fatalf("expected 0 HTTP attempts, got %d", upstream.calls)
	}
	if result.FailureClass != FailureRiskSourceFactUnavailable {
		t.Fatalf("failure=%s", result.FailureClass)
	}
	if result.ContractStages.RiskSourceFactAvailability != provider.StageFail {
		t.Fatalf("stage=%s", result.ContractStages.RiskSourceFactAvailability)
	}
}

func TestProductionGapAuditE01EvalFixtureAligned(t *testing.T) {
	cases := AllCases()
	var target EvaluationCase
	for _, c := range cases {
		if c.ID == E01DiagnosticCaseID {
			target = c
			break
		}
	}
	if _, err := ProductionLikeMonthlySummaryFacts(target); err != nil {
		t.Fatalf("production-like E01 fixture must satisfy invariant: %v", err)
	}
}

func TestProductionLikeE01FactsRegisterDTI(t *testing.T) {
	cases := AllCases()
	var target EvaluationCase
	for _, c := range cases {
		if c.ID == E01DiagnosticCaseID {
			target = c
			break
		}
	}
	facts, err := ProductionLikeMonthlySummaryFacts(target)
	if err != nil {
		t.Fatal(err)
	}
	if facts.DebtPaymentToIncomePercent == nil || *facts.DebtPaymentToIncomePercent != e01ProductionDTIPercent {
		t.Fatalf("dti=%v", facts.DebtPaymentToIncomePercent)
	}
}

func TestCanonicalDTIPercentMatchesProductionE01(t *testing.T) {
	got, ok := CanonicalDTIPercentString(e01ProductionMonthlyDebtPayment, e01ProductionMonthlyIncome)
	if !ok || got != e01ProductionDTIPercent {
		t.Fatalf("got=%q ok=%t", got, ok)
	}
}

func TestValidateDatasetRiskSourceFactAvailability(t *testing.T) {
	if err := ValidateDataset(AllCases()); err != nil {
		t.Fatal(err)
	}
}

func TestDeriveE01PostArchitectureReadinessRequiresFullPipeline(t *testing.T) {
	pass := RunResult{
		CaseID: E01DiagnosticCaseID, RunIndex: 1,
		Transport: BuildTransportFailureDetail(provider.DecodeDiagnostics{HTTP2xxSuccess: true}),
		ExplanationAlignmentPass: true,
		ProvenanceAssemblyPass:   true,
		EndToEndPass:               true,
	}
	pass.Transport.HTTP2xxSuccess = true
	readiness := DeriveE01PostArchitectureReadiness([]RunResult{pass, pass})
	if readiness.Verdict != ReadinessPass {
		t.Fatalf("verdict=%s", readiness.Verdict)
	}

	reasonOnly := pass
	reasonOnly.ProvenanceAssemblyPass = false
	reasonOnly.EndToEndPass = false
	readiness = DeriveE01PostArchitectureReadiness([]RunResult{reasonOnly, reasonOnly})
	if readiness.Verdict == ReadinessPass {
		t.Fatal("reason-only pass must not satisfy post-architecture readiness")
	}
}

func TestSignalProvenanceFactAvailabilityMatrix(t *testing.T) {
	cases := map[string]struct {
		caseID     string
		sourceKeys []string
	}{
		"highDebtPaymentToIncome":  {"E01_partial_debt_data", []string{"debtPaymentToIncomePercent"}},
		"negativeProjectedBalance": {"B04_short_term_negative_balance", []string{"minimumBalance"}},
		"cashFlowBelowSafeBalance": {"B01_minimum_below_safe", []string{"minimumBalance", "safeBalance"}},
		"monthEndBelowSafeBalance": {"B02_month_end_below_safe", []string{"estimatedMonthEndBalance", "safeBalance"}},
		"zeroIncomeWithExpenses":   {"D02_zero_income_month", []string{"monthlyIncome", "monthlyExpense"}},
		"highDebtPressureScore":    {"C04_multiple_debts", []string{"debtPressureLevel"}},
		"criticalDebtPressure":     {"C06_debt_but_adequate_cashflow", []string{"debtPressureLevel"}},
	}
	all := AllCases()
	byID := map[string]EvaluationCase{}
	for _, c := range all {
		byID[c.ID] = c
	}
	for reason, spec := range cases {
		c := byID[spec.caseID]
		if err := factpack.ValidateRiskSourceFactAvailability(&c.Assessment, c.Envelope.MonthlySummaryFacts); err != nil {
			t.Fatalf("%s via %s: %v", reason, spec.caseID, err)
		}
		for _, key := range spec.sourceKeys {
			if !containsFactKey(c.Envelope.MonthlySummaryFacts, key) {
				t.Fatalf("%s missing registered fact %s", spec.caseID, key)
			}
		}
	}
}

func TestB02HasMonthEndFactsButDoesNotEmitMonthEndBelowSafeBalance(t *testing.T) {
	if !B02DoesNotEmitMonthEndBelowSafeBalance() {
		t.Fatal("B02 must not emit monthEndBelowSafeBalance; it emits cashFlowBelowSafeBalance via minimumBalance path")
	}
	c, err := findCaseByID("B02_month_end_below_safe")
	if err != nil {
		t.Fatal(err)
	}
	for _, signal := range c.Assessment.Signals {
		switch signal.ReasonCode {
		case "cashFlowBelowSafeBalance", "highDebtPaymentToIncome":
		default:
			t.Fatalf("unexpected B02 signal: %+v", signal)
		}
	}
}

func containsFactKey(facts *contract.MonthlySummaryFactsDTO, key string) bool {
	keys := factpack.BuildKeySets(facts).AllowedFactKeys
	for _, item := range keys {
		if item == key {
			return true
		}
	}
	return false
}
