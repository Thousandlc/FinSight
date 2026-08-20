package eval

import (
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestAllTransportFailureRegressionReport(t *testing.T) {
	var results []RunResult
	for _, caseID := range SmokeGoldenCaseIDs {
		for run := 1; run <= SmokeV2RepeatCount; run++ {
			c, err := findCaseByID(caseID)
			if err != nil {
				t.Fatal(err)
			}
			upstream := &FixtureTransportUpstream{
				Handler: func(contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
					return contract.AssistantAnswerDraftDTO{}, connectionFailureDiag(), providerUpstreamErr()
				},
			}
			results = append(results, executeRun(t.Context(), upstream, c, run, EvaluationModeExplanationAlignmentV2))
		}
	}
	if len(results) != 12 {
		t.Fatalf("expected 12 results, got %d", len(results))
	}

	metrics := ComputeMetrics(results, EvaluationModeExplanationAlignmentV2)
	analysis := AnalyzeFullEvaluation(results, AllCases(), metrics, EvaluationModeExplanationAlignmentV2)

	if metrics.RequestAttemptedCount != 12 {
		t.Fatalf("requestAttempted=%d", metrics.RequestAttemptedCount)
	}
	if metrics.HTTPResponseReceivedCount != 0 {
		t.Fatalf("httpResponseReceived=%d", metrics.HTTPResponseReceivedCount)
	}
	if metrics.HTTP2xxSuccessCount != 0 {
		t.Fatalf("http2xx=%d", metrics.HTTP2xxSuccessCount)
	}
	if metrics.ModelMetricsAssessed {
		t.Fatal("model metrics must not be assessed")
	}
	if metrics.FailureBreakdown[FailureSemanticAction] > 0 {
		t.Fatalf("unexpected semantic-action failures: %v", metrics.FailureBreakdown)
	}
	if analysis.SystemicPatterns.MissingDataOverconfidence {
		t.Fatal("missingDataOverconfidence must not trigger without model output")
	}
	srv := DeriveSmokeReadinessVerdicts(metrics, analysis)
	if srv.SmokeExplanationContractReadiness != ReadinessNotAssessed {
		t.Fatalf("explanation readiness=%s", srv.SmokeExplanationContractReadiness)
	}
	if srv.SmokeNarrativeReadiness != ReadinessNotAssessed {
		t.Fatalf("narrative readiness=%s", srv.SmokeNarrativeReadiness)
	}
	if srv.SmokeFullEvalReadiness != ReadinessBlocked {
		t.Fatalf("full eval readiness=%s", srv.SmokeFullEvalReadiness)
	}
	for _, wc := range metrics.WorstCases {
		if wc.TopFailure == FailureSemanticAction {
			t.Fatalf("%s topFailure must not be semantic-action on transport outage", wc.CaseID)
		}
	}
}

func TestHTTP401Classification(t *testing.T) {
	c, err := findCaseByID(ConnectivityProbeCaseID)
	if err != nil {
		t.Fatal(err)
	}
	diag := httpStatusFailureDiag(401, provider.ErrorCategoryHTTP401, "InvalidApiKey", "invalid api key")
	upstream := &FixtureTransportUpstream{
		Handler: func(contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
			return contract.AssistantAnswerDraftDTO{}, diag, providerUpstreamErr()
		},
	}
	result := executeRun(t.Context(), upstream, c, 1, EvaluationModeExplanationAlignmentV2)
	if !result.Transport.RequestAttempted || !result.Transport.HTTPResponseReceived || result.Transport.HTTP2xxSuccess {
		t.Fatalf("transport flags: %+v", result.Transport)
	}
	if result.FailureClass != FailureHTTPAuth {
		t.Fatalf("failureClass=%s want %s", result.FailureClass, FailureHTTPAuth)
	}
	if result.ModelResponseAssessed {
		t.Fatal("semantic stages must not be assessed")
	}
}

func TestHTTP400Classification(t *testing.T) {
	c, _ := findCaseByID(ConnectivityProbeCaseID)
	diag := httpStatusFailureDiag(400, provider.ErrorCategoryHTTP400, "InvalidParameter", "unsupported parameter")
	result := executeRun(t.Context(), &FixtureTransportUpstream{
		Handler: func(contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
			return contract.AssistantAnswerDraftDTO{}, diag, providerUpstreamErr()
		},
	}, c, 1, EvaluationModeExplanationAlignmentV2)
	if result.FailureClass != FailureHTTPBadRequest {
		t.Fatalf("failureClass=%s", result.FailureClass)
	}
	if result.Transport.ProviderErrorCode != "InvalidParameter" {
		t.Fatalf("provider code=%s", result.Transport.ProviderErrorCode)
	}
}

func TestHTTP404Classification(t *testing.T) {
	c, _ := findCaseByID(ConnectivityProbeCaseID)
	diag := httpStatusFailureDiag(404, provider.ErrorCategoryHTTP404, "NotFound", "model not found")
	result := executeRun(t.Context(), &FixtureTransportUpstream{
		Handler: func(contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
			return contract.AssistantAnswerDraftDTO{}, diag, providerUpstreamErr()
		},
	}, c, 1, EvaluationModeExplanationAlignmentV2)
	if result.FailureClass != FailureHTTPNotFound {
		t.Fatalf("failureClass=%s", result.FailureClass)
	}
}

func TestHTTP429Classification(t *testing.T) {
	c, _ := findCaseByID(ConnectivityProbeCaseID)
	diag := httpStatusFailureDiag(429, provider.ErrorCategoryHTTP429, "Throttling", "rate limit exceeded")
	result := executeRun(t.Context(), &FixtureTransportUpstream{
		Handler: func(contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
			return contract.AssistantAnswerDraftDTO{}, diag, providerUpstreamErr()
		},
	}, c, 1, EvaluationModeExplanationAlignmentV2)
	if result.FailureClass != FailureHTTPRateLimit {
		t.Fatalf("failureClass=%s", result.FailureClass)
	}
}

func TestTimeoutClassification(t *testing.T) {
	c, _ := findCaseByID(ConnectivityProbeCaseID)
	result := executeRun(t.Context(), &FixtureTransportUpstream{
		Handler: func(contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
			return contract.AssistantAnswerDraftDTO{}, timeoutFailureDiag(), providerUpstreamErr()
		},
	}, c, 1, EvaluationModeExplanationAlignmentV2)
	if result.FailureClass != FailureTimeout {
		t.Fatalf("failureClass=%s", result.FailureClass)
	}
	if !result.Timeout {
		t.Fatal("expected timeout flag")
	}
	if result.ModelResponseAssessed {
		t.Fatal("semantic must be N/A on timeout")
	}
}

func TestTransportDetailDoesNotLeakSecret(t *testing.T) {
	detail := BuildTransportFailureDetail(provider.DecodeDiagnostics{
		ProviderErrorMessage: "Bearer sk-secret should not appear",
	})
	if strings.Contains(detail.ProviderErrorMessage, "sk-secret") {
		t.Fatal("unsanitized provider message in transport detail")
	}
}

func TestConnectivityProbeRunPlan(t *testing.T) {
	plan, _, err := BuildRunPlan(ConnectivityProbeFilterOptions())
	if err != nil {
		t.Fatal(err)
	}
	if plan.Type != RunPlanTypeConnectivityProbe || plan.ExpectedCaseCount != 1 || plan.ExpectedRunCount != 1 {
		t.Fatalf("unexpected plan: %+v", plan)
	}
	if plan.SelectedCaseIDs[0] != ConnectivityProbeCaseID {
		t.Fatalf("case=%s", plan.SelectedCaseIDs[0])
	}
}

func TestV2SmokeReportSkipsLegacyPilotAuditSection(t *testing.T) {
	results := buildAllTransportFailureResults([]string{ConnectivityProbeCaseID}, 1, connectionFailureDiag())
	metrics := ComputeMetrics(results, EvaluationModeExplanationAlignmentV2)
	analysis := AnalyzeFullEvaluation(results, AllCases(), metrics, EvaluationModeExplanationAlignmentV2)
	meta := RunMetadata{SmokeV2Mode: true, TotalCases: 1, TotalRuns: 1}
	summary := FormatSummary(meta, metrics, analysis, EvaluationVersionV2, EvaluationModeExplanationAlignmentV2)
	if strings.Contains(summary, "P0-4.4A Pilot Semantic Evaluation Audit") {
		t.Fatal("v2 smoke summary must not include legacy pilot audit section")
	}
	if !strings.Contains(summary, "SmokeInfrastructure") {
		t.Fatal("expected smoke readiness section")
	}
}
