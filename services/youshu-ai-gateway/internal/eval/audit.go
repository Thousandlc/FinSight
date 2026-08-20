package eval

import (
	"fmt"
	"strings"
)

// PilotAuditReport summarizes semantic evaluation audit for a pilot run.
type PilotAuditReport struct {
	RiskCheckerAlgorithm     string                 `json:"riskCheckerAlgorithm"`
	RawSemanticFailures      int                    `json:"rawSemanticFailures"`
	RawTotalRuns             int                    `json:"rawTotalRuns"`
	ConfirmedModelFailures   int                    `json:"confirmedModelFailures"`
	EvaluatorFalsePositives  int                    `json:"evaluatorFalsePositives"`
	AmbiguousManualReview    int                    `json:"ambiguousManualReview"`
	CaseAudits               []CaseAuditSummary     `json:"caseAudits"`
	RunVerdicts              []SemanticAuditVerdict `json:"runVerdicts"`
	EvaluationRulesToFix     []string               `json:"evaluationRulesToFix"`
	DatasetExpectationsToFix []string               `json:"datasetExpectationsToFix"`
	PromptChangeEvidence     string                 `json:"promptChangeEvidence"`
	ReadyForFullEval         bool                   `json:"readyForFullEval"`
	FullEvalBlockers         []string               `json:"fullEvalBlockers,omitempty"`
	SummaryText              string                 `json:"summaryText"`
}

// CaseAuditSummary per-case audit rollup.
type CaseAuditSummary struct {
	CaseID              string `json:"caseId"`
	ExpectedRiskLevel   RiskLevel `json:"expectedRiskLevel,omitempty"`
	FailureCount        int    `json:"failureCount"`
	TotalRuns           int    `json:"totalRuns"`
	PrimaryVerdict      string `json:"primaryVerdict"`
	ModelOverWarning    bool   `json:"modelOverWarningCandidate,omitempty"`
	DatasetBug          bool   `json:"datasetExpectationBug,omitempty"`
	CheckerFalseNegative bool  `json:"semanticCheckerFalseNegative,omitempty"`
	Notes               string `json:"notes,omitempty"`
}

const riskCheckerAlgorithmDoc = `Risk Checker Algorithm (eval.CheckExpectations):
1. Derive actualRisk from warnings[] using MAX severity aggregation:
   - warningCount=0 → actualRisk=none
   - max(severity): safe→safe, warning→warning, risk→risk
2. Compare expectedRiskLevel vs max(severity):
   - expected none/safe: pass if max is "" or "safe" only
   - expected warning: pass if max is "warning" OR "risk"
   - expected risk: pass only if max is "risk"
3. Multiple warnings: rank safe(1) < warning(2) < risk(3); highest wins.
4. RiskLevelNone rejects warning/risk severities but ALLOWS safe-severity warnings.`

// AuditPilotReport builds a semantic audit from evaluation results.
func AuditPilotReport(report EvaluationReport, cases []EvaluationCase) PilotAuditReport {
	caseMap := map[string]EvaluationCase{}
	for _, c := range cases {
		caseMap[c.ID] = c
	}

	audit := PilotAuditReport{
		RiskCheckerAlgorithm: riskCheckerAlgorithmDoc,
		RawTotalRuns:         len(report.Results),
	}

	var caseFailures = map[string]int{}
	var caseRuns = map[string]int{}

	for _, r := range report.Results {
		caseRuns[r.CaseID]++
		c := caseMap[r.CaseID]
		snap := r.StructuredSnapshot

		if !r.ContractPass || r.Timeout {
			if r.FailureClass == FailureTimeout {
				v := SemanticAuditVerdict{
					CaseID: r.CaseID, RunIndex: r.RunIndex,
					FailureClass: FailureTimeout, Verdict: VerdictAmbiguous,
					Notes: []string{"timeout prevents semantic audit"},
				}
				audit.RunVerdicts = append(audit.RunVerdicts, v)
				audit.AmbiguousManualReview++
			}
			continue
		}

		if r.SemanticPass {
			continue
		}

		audit.RawSemanticFailures++
		caseFailures[r.CaseID]++

		verdict := AuditSemanticFailure(c, r, snap)
		audit.RunVerdicts = append(audit.RunVerdicts, verdict)

		switch verdict.Verdict {
		case VerdictModelError:
			audit.ConfirmedModelFailures++
		case VerdictEvaluatorFalsePositive:
			audit.EvaluatorFalsePositives++
		case VerdictAmbiguous:
			audit.AmbiguousManualReview++
		}
	}

	audit.CaseAudits = buildCaseAuditSummaries(caseMap, caseFailures, caseRuns, audit.RunVerdicts)
	audit.EvaluationRulesToFix = collectEvaluationRulesToFix(audit)
	audit.DatasetExpectationsToFix = collectDatasetFixes(audit)
	audit.PromptChangeEvidence = assessPromptChangeEvidence(audit)
	audit.ReadyForFullEval, audit.FullEvalBlockers = assessFullEvalReadiness(audit)
	audit.SummaryText = FormatPilotAuditSummary(audit)
	return audit
}

func buildCaseAuditSummaries(
	caseMap map[string]EvaluationCase,
	failures, runs map[string]int,
	verdicts []SemanticAuditVerdict,
) []CaseAuditSummary {
	seen := map[string]*CaseAuditSummary{}
	for id, c := range caseMap {
		if runs[id] == 0 {
			continue
		}
		seen[id] = &CaseAuditSummary{
			CaseID:            id,
			ExpectedRiskLevel: c.ExpectedRiskLevel,
			FailureCount:      failures[id],
			TotalRuns:         runs[id],
		}
	}
	for _, v := range verdicts {
		s, ok := seen[v.CaseID]
		if !ok {
			continue
		}
		if s.PrimaryVerdict == "" {
			s.PrimaryVerdict = v.Verdict
		}
		if v.ModelOverWarningCandidate {
			s.ModelOverWarning = true
		}
		if v.DatasetExpectationBug {
			s.DatasetBug = true
		}
		if v.SemanticCheckerFalseNegative {
			s.CheckerFalseNegative = true
		}
		if len(v.Notes) > 0 && s.Notes == "" {
			s.Notes = v.Notes[0]
		}
	}
	out := make([]CaseAuditSummary, 0, len(seen))
	for _, s := range seen {
		if s.FailureCount > 0 {
			out = append(out, *s)
		}
	}
	return out
}

func collectEvaluationRulesToFix(a PilotAuditReport) []string {
	var fixes []string
	hasNarrative := false
	hasUnknown := false
	for _, v := range a.RunVerdicts {
		if v.SemanticCheckerFalseNegative {
			hasNarrative = true
		}
		if v.EvaluationRuleBug && v.FailureClass == FailureSemanticUnknown {
			hasUnknown = true
		}
	}
	if hasNarrative {
		fixes = append(fixes, "Ensure structured conclusion checker covers all required cases")
	}
	if hasUnknown {
		fixes = append(fixes, "Verify unknown expectation matches debt data semantics per case")
	}
	return fixes
}

func collectDatasetFixes(a PilotAuditReport) []string {
	var fixes []string
	for _, ca := range a.CaseAudits {
		if ca.DatasetBug {
			fixes = append(fixes, fmt.Sprintf("%s: dataset expectation needs review", ca.CaseID))
		}
	}
	return fixes
}

func assessPromptChangeEvidence(a PilotAuditReport) string {
	if a.ConfirmedModelFailures >= 5 {
		return "evidence suggests model over-warning in healthy scenarios (A01/F06) and under-warning in debt/risk scenarios (C03); prompt tuning may help AFTER eval framework fixes"
	}
	if a.EvaluatorFalsePositives > a.ConfirmedModelFailures {
		return "insufficient evidence for prompt change; evaluation rules likely causing majority of failures"
	}
	return "inconclusive without per-run structured snapshots; re-run pilot with extended report recommended"
}

func assessFullEvalReadiness(a PilotAuditReport) (bool, []string) {
	var blockers []string
	if a.EvaluatorFalsePositives > 0 {
		blockers = append(blockers, "fix evaluator false positives before full eval")
	}
	if a.DatasetExpectationsToFix != nil && len(a.DatasetExpectationsToFix) > 0 {
		blockers = append(blockers, "fix dataset expectation bugs (E01)")
	}
	if a.AmbiguousManualReview > a.ConfirmedModelFailures {
		blockers = append(blockers, "too many ambiguous cases require manual review with structured snapshots")
	}
	return len(blockers) == 0, blockers
}

// FormatPilotAuditSummary produces human-readable audit report.
func FormatPilotAuditSummary(a PilotAuditReport) string {
	var b strings.Builder
	b.WriteString("=== P0-4.4A Pilot Semantic Evaluation Audit ===\n\n")
	b.WriteString("--- Risk Checker Algorithm ---\n")
	b.WriteString(a.RiskCheckerAlgorithm)
	b.WriteString("\n\n--- Reclassified Failures ---\n")
	b.WriteString(fmt.Sprintf("Raw semantic failures: %d/%d\n", a.RawSemanticFailures, a.RawTotalRuns))
	b.WriteString(fmt.Sprintf("Confirmed model failures: %d\n", a.ConfirmedModelFailures))
	b.WriteString(fmt.Sprintf("Evaluator false positives: %d\n", a.EvaluatorFalsePositives))
	b.WriteString(fmt.Sprintf("Ambiguous / manual review: %d\n\n", a.AmbiguousManualReview))

	b.WriteString("--- Case Audits ---\n")
	for _, ca := range a.CaseAudits {
		b.WriteString(fmt.Sprintf("%s: failures=%d/%d verdict=%s expectedRisk=%s",
			ca.CaseID, ca.FailureCount, ca.TotalRuns, ca.PrimaryVerdict, ca.ExpectedRiskLevel))
		if ca.ModelOverWarning {
			b.WriteString(" modelOverWarning=true")
		}
		if ca.DatasetBug {
			b.WriteString(" datasetBug=true")
		}
		if ca.CheckerFalseNegative {
			b.WriteString(" checkerFalseNegative=true")
		}
		b.WriteString("\n")
	}

	b.WriteString("\n--- Evaluation Rules To Fix ---\n")
	for _, fix := range a.EvaluationRulesToFix {
		b.WriteString("- " + fix + "\n")
	}
	b.WriteString("\n--- Dataset Expectations To Fix ---\n")
	for _, fix := range a.DatasetExpectationsToFix {
		b.WriteString("- " + fix + "\n")
	}
	b.WriteString(fmt.Sprintf("\nPrompt change evidence: %s\n", a.PromptChangeEvidence))
	summary, err := BuildDatasetSummary()
	if err == nil {
		b.WriteString(fmt.Sprintf("Ready for full evaluation (%d runs): %v\n", summary.FullRuns, a.ReadyForFullEval))
	} else {
		b.WriteString(fmt.Sprintf("Ready for full evaluation: %v\n", a.ReadyForFullEval))
	}
	for _, blocker := range a.FullEvalBlockers {
		b.WriteString("- blocker: " + blocker + "\n")
	}
	return b.String()
}

// LoadAndAuditPilotReport loads latest.json and runs audit.
func LoadAndAuditPilotReport(path string) (PilotAuditReport, error) {
	report, err := LoadReport(path)
	if err != nil {
		return PilotAuditReport{}, err
	}
	return AuditPilotReport(report, AllCases()), nil
}
