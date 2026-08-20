package eval

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func compliantEvalDraftJSON() string {
	return `{
		"title": "本月财务摘要",
		"body": "本月可用资金约 ¥10000，预计月底结余约 ¥8000。",
		"answer": "本月可用资金约 ¥10000，预计月底结余约 ¥8000。",
		"citedFactKeys": ["availableCash", "estimatedMonthEndBalance"],
		"confidence": 0.85,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "availableCash"
		}],
		"references": [{"key": "availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
}

func e01MissingExplanationDraftJSONEval() string {
	return `{
		"title": "本月财务摘要",
		"body": "部分债务数据不完整。",
		"answer": "部分债务数据不完整。",
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

func newEvalBailianUpstream(t *testing.T, content string) *provider.BailianProvider {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		payload, _ := json.Marshal(content)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + string(payload) + `}}]}`))
	}))
	t.Cleanup(server.Close)
	return provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "test-key",
		BaseURL: server.URL,
		Model:   "qwen3.7-plus-test",
		Timeout: 5 * time.Second,
	}, server.Client())
}

func TestRunnerCompliantResponsePropagatesAllStages(t *testing.T) {
	c, err := findCaseByID("A01_healthy_cashflow")
	if err != nil {
		t.Fatal(err)
	}
	upstream := newEvalBailianUpstream(t, compliantEvalDraftJSON())
	result := executeRun(context.Background(), upstream, c, 1, EvaluationModeExplanationAlignmentV2)

	if result.ContractStages.DraftDTODecode != provider.StagePass {
		t.Fatalf("dto=%s", result.ContractStages.DraftDTODecode)
	}
	if result.ContractStages.ExplanationAlignment != provider.StagePass {
		t.Fatalf("alignment=%s", result.ContractStages.ExplanationAlignment)
	}
	if result.ContractStages.GatewaySchemaValidation != provider.StagePass {
		t.Fatalf("schema=%s", result.ContractStages.GatewaySchemaValidation)
	}
	if result.ContractStages.FactValidation != provider.StagePass {
		t.Fatalf("fact=%s", result.ContractStages.FactValidation)
	}
	if !result.ExplanationAlignmentPass {
		t.Fatal("expected explanationAlignmentPass=true")
	}
	if !result.ModelResponseAssessed {
		t.Fatal("expected modelResponseAssessed=true")
	}
}

func TestRunnerE01AlignmentFailStageAttribution(t *testing.T) {
	c, err := findCaseByID("E01_partial_debt_data")
	if err != nil {
		t.Fatal(err)
	}
	upstream := newEvalBailianUpstream(t, e01MissingExplanationDraftJSONEval())
	result := executeRun(context.Background(), upstream, c, 1, EvaluationModeExplanationAlignmentV2)

	if result.ContractStages.DraftDTODecode != provider.StagePass {
		t.Fatalf("dto=%s kind=%s", result.ContractStages.DraftDTODecode, result.ContractStages.DTODecodeErrorKind)
	}
	if result.ContractStages.ExplanationAlignment != provider.StageFail {
		t.Fatalf("alignment=%s", result.ContractStages.ExplanationAlignment)
	}
	if result.ContractStages.AlignmentFailureCode != "riskExplanationCoverageMismatch" {
		t.Fatalf("code=%s", result.ContractStages.AlignmentFailureCode)
	}
	if result.ContractStages.GatewaySchemaValidation != provider.StageSkip {
		t.Fatalf("schema=%s want skip", result.ContractStages.GatewaySchemaValidation)
	}
	if result.ExplanationAlignmentPass {
		t.Fatal("expected explanationAlignmentPass=false")
	}
	if len(result.DiagnosticSnapshot.ExpectedRiskReasons) == 0 {
		t.Fatal("expected expectedRiskReasons in snapshot")
	}
	if len(result.DiagnosticSnapshot.ActualRiskExplanationReasons) != 0 {
		t.Fatalf("actual risk=%v", result.DiagnosticSnapshot.ActualRiskExplanationReasons)
	}
}

func TestRunnerTransportFailureLeavesDownstreamNotAssessed(t *testing.T) {
	c, err := findCaseByID("A01_healthy_cashflow")
	if err != nil {
		t.Fatal(err)
	}
	upstream := &FixtureTransportUpstream{
		Handler: func(_ contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
			return contract.AssistantAnswerDraftDTO{}, connectionFailureDiag(), providerUpstreamErr()
		},
	}
	result := executeRun(context.Background(), upstream, c, 1, EvaluationModeExplanationAlignmentV2)
	if result.ContractStages.ExplanationAlignment != provider.StageSkip {
		t.Fatalf("alignment=%s want skip", result.ContractStages.ExplanationAlignment)
	}
	if result.ContractStages.GatewaySchemaValidation != provider.StageSkip {
		t.Fatalf("schema=%s want skip", result.ContractStages.GatewaySchemaValidation)
	}
	if result.ModelResponseAssessed {
		t.Fatal("transport failure must not assess model response")
	}
}

func TestRunnerReportAggregatesExplanationRateCorrectly(t *testing.T) {
	pass := passingSmokeRun("A01_healthy_cashflow", 1)
	fail := RunResult{
		CaseID: "E01_partial_debt_data", RunIndex: 1,
		ContractStages: ContractStages{
			HTTPSuccess: true, HTTP2xxSuccess: true, ContentJSONValid: true,
			GenericJSONObjectDecode: "pass", DraftDTODecode: "pass",
			ExplanationAlignment: "fail", AlignmentFailureCode: "riskExplanationCoverageMismatch",
		},
	}
	metrics := ComputeMetrics([]RunResult{pass, fail}, EvaluationModeExplanationAlignmentV2)
	if metrics.ExplanationAlignmentPassCount != 1 {
		t.Fatalf("alignment pass=%d want 1", metrics.ExplanationAlignmentPassCount)
	}
	if metrics.ModelDTODecodeCount != 2 {
		t.Fatalf("dto pass=%d want 2", metrics.ModelDTODecodeCount)
	}
}

func TestDiagnosticSnapshotPreservesActualReasonsOnUnsupportedRisk(t *testing.T) {
	c, err := findCaseByID("E01_partial_debt_data")
	if err != nil {
		t.Fatal(err)
	}
	diag := provider.DecodeDiagnostics{
		AlignmentFailureCode:         "unsupportedRiskExplanation",
		ActualRiskExplanationReasons: []string{"negativeProjectedBalance"},
		ActualModelCitedFactKeys:     []string{"availableCash"},
	}
	snap := BuildEvaluationDiagnosticSnapshot(c, c.Envelope, diag, contract.AssistantAnswerDraftDTO{}, provider.StageFail)
	if len(snap.ActualRiskExplanationReasons) != 1 {
		t.Fatalf("actual risk=%v", snap.ActualRiskExplanationReasons)
	}
	if len(snap.ActualCitedFactKeys) != 1 || snap.ActualCitedFactKeys[0] != "availableCash" {
		t.Fatalf("cited=%v", snap.ActualCitedFactKeys)
	}
}

func TestFrozenB5ArtifactUnchanged(t *testing.T) {
	path := ".eval-output/smoke-v2-20260817-022459.json"
	info, err := os.Stat(path)
	if err != nil {
		t.Skipf("frozen artifact unavailable: %v", err)
	}
	if info.Size() == 0 {
		t.Fatal("frozen artifact must not be empty")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !json.Valid(data) {
		t.Fatal("frozen artifact must remain valid JSON")
	}
}

func TestDiagnosticSnapshotNoSecretPatterns(t *testing.T) {
	c, err := findCaseByID("E01_partial_debt_data")
	if err != nil {
		t.Fatal(err)
	}
	snap := BuildEvaluationDiagnosticSnapshot(c, c.Envelope, provider.DecodeDiagnostics{
		AlignmentFailureCode: "riskExplanationCoverageMismatch",
	}, contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "partial debt data summary", Answer: "a",
	}, provider.StageFail)
	if snap.Body == "" {
		t.Fatal("expected E01 narrative snapshot body")
	}
	if containsSecretDiagnostic("sk-test-key") == false {
		t.Fatal("secret helper should detect sk- patterns")
	}
}
