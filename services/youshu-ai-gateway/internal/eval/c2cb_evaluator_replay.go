package eval

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

const (
	c2cbFrozenC2ArtifactName  = "full-v2-20260817-070704.json"
	c2cbFrozenC2CArtifactName = "c2c-keyfact-targeted-20260817-074139.json"
	c2cbReplayArtifactPrefix  = "c2cb-evaluator-replay"
)

// C2CBReplayResult summarizes offline post-C2CB evaluator replay against frozen artifacts.
type C2CBReplayResult struct {
	EvaluatorIdentity     EvaluatorIdentity  `json:"evaluatorIdentity"`
	SourceC2Path          string             `json:"sourceC2Path,omitempty"`
	SourceC2CPath         string             `json:"sourceC2CPath,omitempty"`
	C2Replay              C2CBArtifactReplay `json:"c2Replay,omitempty"`
	C2CReplay             C2CBArtifactReplay `json:"c2cReplay,omitempty"`
	C01CitationRegression C2CBPairRegression `json:"c01CitationRegression"`
	C01KeyFactRegression  C2CBPairRegression `json:"c01KeyFactRegression"`
}

// C2CBArtifactReplay holds replay metrics for one frozen artifact.
type C2CBArtifactReplay struct {
	SourceArtifact          string          `json:"sourceArtifact"`
	RawEndToEndPassCount    int             `json:"rawEndToEndPassCount"`
	ReplayEndToEndPassCount int             `json:"replayEndToEndPassCount"`
	TotalRuns               int             `json:"totalRuns"`
	C01RunChanges           []C2CBRunChange `json:"c01RunChanges,omitempty"`
	Notes                   []string        `json:"notes,omitempty"`
}

// C2CBRunChange records one run whose strict E2E verdict changed after replay.
type C2CBRunChange struct {
	CaseID             string `json:"caseId"`
	RunIndex           int    `json:"runIndex"`
	RawEndToEndPass    bool   `json:"rawEndToEndPass"`
	ReplayEndToEndPass bool   `json:"replayEndToEndPass"`
	RawFailureClass    string `json:"rawFailureClass,omitempty"`
	ReplayFailureClass string `json:"replayFailureClass,omitempty"`
}

// C2CBPairRegression captures the core C01 pair contract.
type C2CBPairRegression struct {
	Passed bool   `json:"passed"`
	Detail string `json:"detail,omitempty"`
}

// ReplayEvaluationReport reapplies post-C2CB evaluator semantics to a saved report.
func ReplayEvaluationReport(report EvaluationReport, cases []EvaluationCase, mode string) EvaluationReport {
	if mode == "" {
		mode = report.EvaluationMode
	}
	if mode == "" {
		mode = EvaluationModeExplanationAlignmentV2
	}
	caseMap := indexCasesByID(cases)
	replayed := report
	replayed.Results = append([]RunResult(nil), report.Results...)
	for i := range replayed.Results {
		r := &replayed.Results[i]
		c, ok := caseMap[r.CaseID]
		if !ok {
			continue
		}
		RescoreRunWithPostC2CBEvaluator(r, c, mode)
	}
	identity := CurrentEvaluatorIdentity()
	replayed.EvaluatorVersion = identity.EvaluatorVersion
	replayed.EvaluatorFingerprint = identity.EvaluatorFingerprint
	replayed.Metrics = ComputeMetrics(replayed.Results, mode)
	replayed.Analysis = AnalyzeFullEvaluation(replayed.Results, cases, replayed.Metrics, mode)
	replayed.Summary = FormatSummary(replayed.Metadata, replayed.Metrics, replayed.Analysis, replayed.EvaluationVersion, mode)
	return replayed
}

// RescoreRunWithPostC2CBEvaluator updates one saved run with post-C2CB evaluator semantics.
func RescoreRunWithPostC2CBEvaluator(r *RunResult, c EvaluationCase, mode string) {
	if !r.ContractPass {
		if r.FailureClass == "" || r.ContractStages.FactValidation == provider.StageFail {
			r.FailureClass, r.FailureDetail = classifyFailure(
				r.ContractStages, r.Semantic, r.V2Semantic, r.ContractPass, mode,
				r.InvalidKeyFactSource, r.InventedFacts,
			)
		}
		r.AuditVerdict = SemanticAuditVerdict{
			CaseID:       r.CaseID,
			RunIndex:     r.RunIndex,
			FailureClass: r.FailureClass,
			Verdict:      VerdictAmbiguous,
			Notes:        []string{formatContractStageAuditNote(r.ContractStages)},
		}
		return
	}

	semantic := RescoreRunOffline(c, r.StructuredSnapshot)
	r.Semantic = semantic
	r.SemanticPass = semantic.Passed
	r.ForbiddenClaimCount = len(semantic.ForbiddenClaimHits)
	r.MissingConclusionCount = len(semantic.MissingStructuredConclusions)
	r.RiskMatch = semantic.RiskMatch
	r.UnknownBehaviorPass = semantic.UnknownBehaviorPass

	if IsV2EvaluationMode(mode) {
		v2 := RescoreRunOfflineV2(c, r.StructuredSnapshot, r.ExplanationAlignmentPass, r.ProvenanceAssemblyPass)
		r.V2Semantic = v2
		r.SemanticPass = v2.Passed
		r.PolicyStructuralPass = v2.PolicyStructuralPass
		r.FinalValidatorPass = v2.FinalValidatorPass
	}

	r.EndToEndPass = r.ContractPass && r.SemanticPass
	if !r.EndToEndPass {
		r.FailureClass, r.FailureDetail = classifyFailure(
			r.ContractStages, r.Semantic, r.V2Semantic, r.ContractPass, mode,
			r.InvalidKeyFactSource, r.InventedFacts,
		)
		r.FailureSeverity = ClassifyFailureSeverity(r.FailureClass, c, r.StructuredSnapshot)
		r.AuditVerdict = AuditSemanticFailure(c, *r, r.StructuredSnapshot)
	} else {
		r.FailureClass = ""
		r.FailureDetail = ""
		r.FailureSeverity = ""
	}
	r.EvaluationVerdict = ResolveEvaluationVerdict(*r)
}

// BuildC2CBReplayResult replays frozen C2 and C2C artifacts when available.
func BuildC2CBReplayResult(outputDir string) (C2CBReplayResult, error) {
	if outputDir == "" {
		var err error
		outputDir, err = ResolveOutputDir(DefaultOutputDir)
		if err != nil {
			return C2CBReplayResult{}, fmt.Errorf("resolve output dir: %w", err)
		}
	}
	out := C2CBReplayResult{
		EvaluatorIdentity:     CurrentEvaluatorIdentity(),
		C01CitationRegression: evaluateC01CitationPairRegression(),
		C01KeyFactRegression:  evaluateC01KeyFactPairRegression(),
	}
	cases := AllCases()

	c2Path := filepath.Join(outputDir, c2cbFrozenC2ArtifactName)
	if report, err := LoadReport(c2Path); err == nil {
		out.SourceC2Path = c2Path
		replayed := ReplayEvaluationReport(report, cases, report.EvaluationMode)
		out.C2Replay = summarizeArtifactReplay(c2Path, report, replayed)
	} else if !os.IsNotExist(err) {
		return C2CBReplayResult{}, fmt.Errorf("load C2 artifact: %w", err)
	}

	c2cPath := filepath.Join(outputDir, c2cbFrozenC2CArtifactName)
	if report, err := LoadReport(c2cPath); err == nil {
		out.SourceC2CPath = c2cPath
		replayed := ReplayEvaluationReport(report, cases, report.EvaluationMode)
		out.C2CReplay = summarizeArtifactReplay(c2cPath, report, replayed)
	} else if !os.IsNotExist(err) {
		return C2CBReplayResult{}, fmt.Errorf("load C2C artifact: %w", err)
	}

	return out, nil
}

func summarizeArtifactReplay(path string, raw, replayed EvaluationReport) C2CBArtifactReplay {
	summary := C2CBArtifactReplay{
		SourceArtifact: filepath.Base(path),
		TotalRuns:      len(raw.Results),
		Notes:          []string{"historical artifact preserved; replay uses post-C2CB evaluator only"},
	}
	for i, rawRun := range raw.Results {
		if rawRun.EndToEndPass {
			summary.RawEndToEndPassCount++
		}
		if i < len(replayed.Results) && replayed.Results[i].EndToEndPass {
			summary.ReplayEndToEndPassCount++
		}
		if rawRun.CaseID != C2CCaseC01 && rawRun.CaseID != "C01_no_debt" {
			continue
		}
		replayRun := replayed.Results[i]
		if rawRun.EndToEndPass != replayRun.EndToEndPass || rawRun.FailureClass != replayRun.FailureClass {
			summary.C01RunChanges = append(summary.C01RunChanges, C2CBRunChange{
				CaseID:             rawRun.CaseID,
				RunIndex:           rawRun.RunIndex,
				RawEndToEndPass:    rawRun.EndToEndPass,
				ReplayEndToEndPass: replayRun.EndToEndPass,
				RawFailureClass:    rawRun.FailureClass,
				ReplayFailureClass: replayRun.FailureClass,
			})
		}
	}
	if strings.Contains(path, "c2c-keyfact-targeted") && summary.TotalRuns > 0 &&
		summary.ReplayEndToEndPassCount == summary.TotalRuns {
		summary.Notes = append(summary.Notes, "C2C strict replay PASS")
	}
	if strings.Contains(path, "full-v2") {
		summary.Notes = append(summary.Notes, "C2 replay verifies citation scope does not regress other evaluator expectations")
	}
	return summary
}

func evaluateC01CitationPairRegression() C2CBPairRegression {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		return C2CBPairRegression{Detail: err.Error()}
	}
	draft := citationProbeDraft("monthlyDebtPayment")
	result := CheckExpectations(c, draft)
	if !result.CitationSemanticPass || !result.Passed {
		return C2CBPairRegression{Detail: "expected legal C01 citation PASS"}
	}
	return C2CBPairRegression{Passed: true}
}

func evaluateC01KeyFactPairRegression() C2CBPairRegression {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		return C2CBPairRegression{Detail: err.Error()}
	}
	draft := contractAssistantAnswerDraftWithKeyFact("monthlyDebtPayment")
	result := CheckExpectations(c, draft)
	if result.KeyFactSelectionSemanticPass || result.Passed {
		return C2CBPairRegression{Detail: "expected forbidden C01 keyFact FAIL"}
	}
	if !containsEvalFailureClass(result.FailureClasses, FailureForbiddenKeyFactSource) {
		return C2CBPairRegression{Detail: "expected forbidden-keyfact-source failure class"}
	}
	return C2CBPairRegression{Passed: true}
}

func contractAssistantAnswerDraftWithKeyFact(source string) contract.AssistantAnswerDraftDTO {
	return contract.AssistantAnswerDraftDTO{
		Title:         "probe",
		Body:          "probe",
		Answer:        "probe",
		CitedFactKeys: []string{"monthlyIncome"},
		KeyFacts: []contract.KeyFact{
			{Source: source, Kind: "debt", Label: source, Value: contract.KeyFactValue{Type: "money"}},
		},
	}
}

func containsEvalFailureClass(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}

// WriteC2CBReplayArtifact writes a timestamped offline replay artifact without modifying frozen inputs.
func WriteC2CBReplayArtifact(result C2CBReplayResult, outputDir string) (string, error) {
	if outputDir == "" {
		var err error
		outputDir, err = ResolveOutputDir(DefaultOutputDir)
		if err != nil {
			return "", fmt.Errorf("resolve output dir: %w", err)
		}
	}
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		return "", fmt.Errorf("create output dir: %w", err)
	}
	path := filepath.Join(outputDir, fmt.Sprintf("%s-%s.json", c2cbReplayArtifactPrefix, time.Now().UTC().Format("20060102-150405")))
	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return "", fmt.Errorf("marshal replay artifact: %w", err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return "", fmt.Errorf("write replay artifact: %w", err)
	}
	return path, nil
}

// ReplayFrozenC2CReport loads the frozen C2C artifact and returns post-C2CB replay report.
func ReplayFrozenC2CReport(outputDir string) (EvaluationReport, EvaluationReport, error) {
	if outputDir == "" {
		var err error
		outputDir, err = ResolveOutputDir(DefaultOutputDir)
		if err != nil {
			return EvaluationReport{}, EvaluationReport{}, fmt.Errorf("resolve output dir: %w", err)
		}
	}
	path := filepath.Join(outputDir, c2cbFrozenC2CArtifactName)
	raw, err := LoadReport(path)
	if err != nil {
		return EvaluationReport{}, EvaluationReport{}, err
	}
	replayed := ReplayEvaluationReport(raw, AllCases(), raw.EvaluationMode)
	return raw, replayed, nil
}

// ReplayFrozenC2Report loads the frozen C2 artifact and returns post-C2CB replay report.
func ReplayFrozenC2Report(outputDir string) (EvaluationReport, EvaluationReport, error) {
	if outputDir == "" {
		var err error
		outputDir, err = ResolveOutputDir(DefaultOutputDir)
		if err != nil {
			return EvaluationReport{}, EvaluationReport{}, fmt.Errorf("resolve output dir: %w", err)
		}
	}
	path := filepath.Join(outputDir, c2cbFrozenC2ArtifactName)
	raw, err := LoadReport(path)
	if err != nil {
		return EvaluationReport{}, EvaluationReport{}, err
	}
	replayed := ReplayEvaluationReport(raw, AllCases(), raw.EvaluationMode)
	return raw, replayed, nil
}
