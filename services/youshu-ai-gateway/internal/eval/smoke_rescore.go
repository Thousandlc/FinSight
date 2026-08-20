package eval

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// SmokeRescoreResult holds raw and corrected offline adjudication for a frozen smoke artifact.
type SmokeRescoreResult struct {
	RawReport       EvaluationReport       `json:"rawReport"`
	CorrectedReport EvaluationReport       `json:"correctedReport"`
	RawReadiness    SmokeReadinessVerdicts `json:"rawReadiness"`
	CorrectedReadiness SmokeReadinessVerdicts `json:"correctedReadiness"`
	E01Audits       []E01RunAudit          `json:"e01Audits,omitempty"`
}

// E01RunAudit captures offline adjudication for one E01 run.
type E01RunAudit struct {
	CaseID               string `json:"caseId"`
	RunIndex             int    `json:"runIndex"`
	AlignmentFailureCode string `json:"alignmentFailureCode,omitempty"`
	Adjudication         string `json:"adjudication"`
	Notes                string `json:"notes,omitempty"`
}

// RescoreSmokeArtifactReport reapplies evaluator fixes to a saved smoke report without HTTP calls.
func RescoreSmokeArtifactReport(report EvaluationReport, cases []EvaluationCase) SmokeRescoreResult {
	caseMap := indexCasesByID(cases)
	rawReadiness := report.SmokeReadiness
	if rawReadiness.SmokeInfrastructureReadiness == "" {
		rawReadiness = DeriveSmokeReadinessVerdicts(report.Metrics, report.Analysis)
	}

	corrected := report
	corrected.Results = append([]RunResult(nil), report.Results...)
	var e01Audits []E01RunAudit

	for i := range corrected.Results {
		r := &corrected.Results[i]
		c, ok := caseMap[r.CaseID]
		if !ok {
			continue
		}
		NormalizeLegacyRunStages(r)
		RescoreRunSemantics(r, c)
		if r.CaseID == "E01_partial_debt_data" && r.ContractStages.ExplanationAlignment == "fail" {
			e01Audits = append(e01Audits, auditE01Run(*r))
		}
	}

	corrected.Metrics = ComputeMetrics(corrected.Results, corrected.EvaluationMode)
	corrected.Analysis = AnalyzeFullEvaluation(corrected.Results, cases, corrected.Metrics, corrected.EvaluationMode)
	corrected.SmokeReadiness = DeriveSmokeReadinessVerdicts(corrected.Metrics, corrected.Analysis)
	corrected.ModelVerdict = corrected.Analysis.ReadinessVerdicts
	corrected.Summary = FormatSummary(corrected.Metadata, corrected.Metrics, corrected.Analysis, corrected.EvaluationVersion, corrected.EvaluationMode)

	return SmokeRescoreResult{
		RawReport:          report,
		CorrectedReport:    corrected,
		RawReadiness:       rawReadiness,
		CorrectedReadiness: corrected.SmokeReadiness,
		E01Audits:          e01Audits,
	}
}

// NormalizeLegacyRunStages fixes pre-B4A conflation of alignment failure with DTO decode failure.
func NormalizeLegacyRunStages(r *RunResult) {
	cs := &r.ContractStages
	if !cs.HTTP2xxSuccess && !cs.HTTPSuccess {
		return
	}
	if !cs.ContentJSONValid || cs.GenericJSONObjectDecode != "pass" {
		return
	}
	if cs.DraftDTODecode == "pass" {
		return
	}
	if cs.DTODecodeErrorKind != "explanationAlignment" {
		return
	}
	cs.DraftDTODecode = "pass"
	cs.ExplanationAlignment = "fail"
	if cs.AlignmentFailureCode == "" {
		cs.AlignmentFailureCode = InferAlignmentFailureCodeFromCase(r.CaseID)
	}
	r.ExplanationAlignmentPass = false
	if r.Transport.FailureStage == "modelDecode" {
		r.Transport.FailureStage = "explanationAlignment"
	}
}

// RescoreRunSemantics reapplies narrative/explanation evaluator fixes on saved run data.
func RescoreRunSemantics(r *RunResult, c EvaluationCase) {
	if r.ContractPass && len(r.Semantic.ForbiddenClaimHits) > 0 {
		draft := draftFromRunSnapshot(*r)
		v2 := CheckExplanationExpectationsV2(c, draft, r.ExplanationAlignmentPass, r.ExplanationAlignmentPass)
		r.V2Semantic = v2
		r.SemanticPass = v2.Passed
		r.EndToEndPass = r.ContractPass && v2.Passed
		if !r.EndToEndPass {
			r.FailureClass, r.FailureDetail = classifyFailure(r.ContractStages, r.Semantic, v2, r.ContractPass, EvaluationModeExplanationAlignmentV2, r.InvalidKeyFactSource, r.InventedFacts)
			r.FailureSeverity = ClassifyFailureSeverity(r.FailureClass, c, r.StructuredSnapshot)
			r.AuditVerdict = AuditSemanticFailure(c, *r, r.StructuredSnapshot)
			r.EvaluationVerdict = ResolveEvaluationVerdict(*r)
		}
	}

	if r.ContractStages.ExplanationAlignment == "fail" {
		alignCode := r.ContractStages.AlignmentFailureCode
		if alignCode == "" {
			alignCode = InferAlignmentFailureCodeFromCase(r.CaseID)
			r.ContractStages.AlignmentFailureCode = alignCode
		}
		r.FailureClass = ClassifyAlignmentFailure(alignCode)
		r.FailureDetail = "explanation alignment: " + alignCode
		r.AuditVerdict = SemanticAuditVerdict{
			CaseID:       r.CaseID,
			RunIndex:     r.RunIndex,
			FailureClass: r.FailureClass,
			Verdict:      adjudicateAlignmentFailure(alignCode),
			Notes:        []string{"HTTP 200 with explanation alignment failure"},
		}
		r.EvaluationVerdict = ResolveEvaluationVerdict(*r)
	}
}

func adjudicateAlignmentFailure(code string) string {
	switch strings.TrimSpace(code) {
	case "", "unknown":
		return VerdictAmbiguous
	case "riskExplanationCoverageMismatch", "riskExplanationReasonNotInAssessment",
		"unregistered riskExplanation citedFactKey", "riskExplanation citedFactKeyNotInSignalSources",
		"riskExplanation missingPrimarySource", "unknownExplanationCoverageMismatch":
		return VerdictModelError
	default:
		if strings.Contains(code, "Mismatch") || strings.Contains(code, "NotInAssessment") {
			return VerdictModelError
		}
		return VerdictAmbiguous
	}
}

func auditE01Run(r RunResult) E01RunAudit {
	code := r.ContractStages.AlignmentFailureCode
	if code == "" {
		code = InferAlignmentFailureCodeFromCase(r.CaseID)
	}
	adj := adjudicateAlignmentFailure(code)
	notes := "artifact lacks saved model riskExplanations; inferred from golden contract"
	if r.DiagnosticSnapshot.AlignmentFailureCode != "" {
		notes = "alignmentFailureCode from diagnostic snapshot"
	}
	return E01RunAudit{
		CaseID:               r.CaseID,
		RunIndex:             r.RunIndex,
		AlignmentFailureCode: code,
		Adjudication:         adj,
		Notes:                notes,
	}
}

func indexCasesByID(cases []EvaluationCase) map[string]EvaluationCase {
	out := make(map[string]EvaluationCase, len(cases))
	for _, c := range cases {
		out[c.ID] = c
	}
	return out
}

func draftFromRunSnapshot(r RunResult) contract.AssistantAnswerDraftDTO {
	body := r.StructuredSnapshot.Body
	if body == "" && len(r.Semantic.ForbiddenClaimHits) > 0 {
		body = "正文包含" + r.Semantic.ForbiddenClaimHits[0]
	}
	return contract.AssistantAnswerDraftDTO{
		Title:         "",
		Body:          body,
		Answer:        r.StructuredSnapshot.Answer,
		CitedFactKeys: cloneStringSlice(r.StructuredSnapshot.CitedFactKeys),
		Unknowns:      cloneStringSlice(r.StructuredSnapshot.Unknowns),
	}
}

// LoadAndRescoreSmokeArtifact loads a frozen smoke JSON and returns offline corrected metrics.
func LoadAndRescoreSmokeArtifact(path string) (SmokeRescoreResult, error) {
	report, err := LoadReport(path)
	if err != nil {
		return SmokeRescoreResult{}, err
	}
	if report.Metadata.TotalRuns == 0 {
		return SmokeRescoreResult{}, fmt.Errorf("report has zero runs")
	}
	return RescoreSmokeArtifactReport(report, AllCases()), nil
}
