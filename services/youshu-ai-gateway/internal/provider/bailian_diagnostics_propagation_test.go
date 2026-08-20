package provider_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func e01Envelope() contract.RequestEnvelope {
	env := sampleEnvelope()
	env.FinancialRiskAssessment = sampleE01PartialAssessment()
	pct := "25"
	env.MonthlySummaryFacts.DebtPaymentToIncomePercent = &pct
	return env
}

func compliantSafeDraftJSON() string {
	return validDraftJSON()
}

func compliantC03DraftJSON() string {
	return `{
		"title": "本月财务摘要",
		"body": "债务还款占收入比例需要关注。",
		"answer": "债务还款占收入比例需要关注。",
		"citedFactKeys": ["debtPaymentToIncomePercent", "availableCash"],
		"confidence": 0.85,
		"keyFacts": [{
			"label": "债务还款占比",
			"kind": "debt",
			"source": "debtPaymentToIncomePercent"
		},{
			"label": "可用资金",
			"kind": "balance",
			"source": "availableCash"
		}],
		"references": [{"key":"debtPaymentToIncomePercent"},{"key":"availableCash"}],
		"riskExplanations": [{
			"reasonCode": "highDebtPaymentToIncome",
			"text": "债务还款占收入比例已达到需要关注的水平。"
		}],
		"unknownExplanations": []
	}`
}

func e01MissingExplanationDraftJSON() string {
	return `{
		"title": "本月财务摘要",
		"body": "部分债务数据不完整，但现金流仍可观察。",
		"answer": "部分债务数据不完整，但现金流仍可观察。",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "availableCash"
		}],
		"references": [{"key":"availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
}

func TestBailianAnalyzeContentDiagnosticsNotLost(t *testing.T) {
	content := compliantSafeDraftJSON()
	_, contentDiag := provider.AnalyzeContent(content, sampleSafeAssessment(), sampleDTIFacts())
	if contentDiag.ExplanationAlignment != provider.StagePass {
		t.Fatalf("content alignment=%s", contentDiag.ExplanationAlignment)
	}

	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(content) + `}}]}`))
	})
	env := sampleEnvelope()
	_, diag, err := p.DiagnoseMonthlySummary(context.Background(), env)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if diag.ExplanationAlignment != provider.StagePass {
		t.Fatalf("provider alignment=%s want pass", diag.ExplanationAlignment)
	}
	if diag.AlignmentFailureCode != "" {
		t.Fatalf("alignment code should be empty on pass, got %q", diag.AlignmentFailureCode)
	}
}

func TestBailianE01AlignmentFailPreservesStageTruth(t *testing.T) {
	content := e01MissingExplanationDraftJSON()
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(content) + `}}]}`))
	})
	_, diag, err := p.DiagnoseMonthlySummary(context.Background(), e01Envelope())
	if err != nil {
		t.Fatalf("alignment fail should not surface as provider transport error: %v", err)
	}
	if diag.DraftDTODecode != provider.StagePass {
		t.Fatalf("dto=%s kind=%s", diag.DraftDTODecode, diag.DTODecodeErrorKind)
	}
	if diag.ExplanationAlignment != provider.StageFail {
		t.Fatalf("alignment=%s code=%s", diag.ExplanationAlignment, diag.AlignmentFailureCode)
	}
	if diag.AlignmentFailureCode != "riskExplanationCoverageMismatch" {
		t.Fatalf("code=%s", diag.AlignmentFailureCode)
	}
	if diag.DTODecodeErrorKind != "explanationAlignment" {
		t.Fatalf("kind=%s", diag.DTODecodeErrorKind)
	}
	if len(diag.ActualRiskExplanationReasons) != 0 {
		t.Fatalf("actual risk reasons=%v", diag.ActualRiskExplanationReasons)
	}
}

func TestBailianAlignmentFailPreservesActualReasonsWhenPresent(t *testing.T) {
	content := `{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [],
		"references": [],
		"riskExplanations": [{
			"reasonCode": "negativeProjectedBalance",
			"text": "unsupported reason"
		}],
		"unknownExplanations": []
	}`
	_, diag := provider.AnalyzeContent(content, sampleE01PartialAssessment(), sampleDTIFacts())
	if diag.ExplanationAlignment != provider.StageFail {
		t.Fatalf("alignment=%s", diag.ExplanationAlignment)
	}
	if len(diag.ActualRiskExplanationReasons) != 1 || diag.ActualRiskExplanationReasons[0] != "negativeProjectedBalance" {
		t.Fatalf("actual risk reasons=%v", diag.ActualRiskExplanationReasons)
	}
}

func TestBailianHTTPFailureLeavesExplanationNotAssessed(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	})
	_, diag, _ := p.DiagnoseMonthlySummary(context.Background(), sampleEnvelope())
	if diag.ExplanationAlignment != provider.StageSkip {
		t.Fatalf("alignment=%s want skip", diag.ExplanationAlignment)
	}
	if diag.DraftDTODecode != provider.StageSkip {
		t.Fatalf("dto=%s want skip", diag.DraftDTODecode)
	}
}

func TestBailianCompliantC03RiskExplanationPropagates(t *testing.T) {
	content := compliantC03DraftJSON()
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(content) + `}}]}`))
	})
	env := sampleEnvelope()
	env.FinancialRiskAssessment = sampleDTIAssessment()
	pct := "25"
	env.MonthlySummaryFacts.DebtPaymentToIncomePercent = &pct
	_, diag, err := p.DiagnoseMonthlySummary(context.Background(), env)
	if err != nil {
		t.Fatal(err)
	}
	if diag.ExplanationAlignment != provider.StagePass {
		t.Fatalf("alignment=%s", diag.ExplanationAlignment)
	}
	if len(diag.ActualRiskExplanationReasons) != 1 || diag.ActualRiskExplanationReasons[0] != "highDebtPaymentToIncome" {
		t.Fatalf("actual risk=%v", diag.ActualRiskExplanationReasons)
	}
}

func TestAnalyzeContentWithoutAssessmentMarksAlignmentSkip(t *testing.T) {
	_, diag := provider.AnalyzeContent(compliantSafeDraftJSON(), nil, nil)
	if diag.DraftDTODecode != provider.StagePass {
		t.Fatalf("dto=%s", diag.DraftDTODecode)
	}
	if diag.ExplanationAlignment != provider.StageSkip {
		t.Fatalf("alignment=%s want skip", diag.ExplanationAlignment)
	}
}

func TestDiagnosticSnapshotFieldsDoNotLeakSecrets(t *testing.T) {
	secret := "UNIQUE_SECRET_DIAGNOSTIC_TOKEN"
	content := `{
		"title":"t","body":"` + secret + `","answer":"a",
		"citedFactKeys":["availableCash"],
		"confidence":0.8,"keyFacts":[],"references":[],
		"riskExplanations":[{"reasonCode":"highDebtPaymentToIncome","text":"x"}],
		"unknownExplanations":[]
	}`
	_, diag := provider.AnalyzeContent(content, sampleE01PartialAssessment(), sampleDTIFacts())
	encoded, err := json.Marshal(diag)
	if err != nil {
		t.Fatal(err)
	}
	dump := string(encoded)
	if stringsContains(dump, secret) {
		t.Fatal("diagnostics leaked body secret")
	}
}

func stringsContains(s, sub string) bool {
	return len(sub) > 0 && stringsIndex(s, sub) >= 0
}

func stringsIndex(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
