package eval

import (
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// SemanticResult captures deterministic semantic expectation checks.
type SemanticResult struct {
	Passed                     bool
	FailureClasses             []string
	ForbiddenClaimHits         []string
	MissingStructuredConclusions []string
	DiagnosticKeywordMisses  []string
	RiskMatch                  bool
	RiskMismatchDirection      string
	ActualDerivedRisk          RiskLevel
	UnknownBehaviorPass        bool
	UnknownExpectation         UnknownExpectation
	StructuredConclusionPass   bool
	ActionCompliancePass       bool
	ReferenceCompliancePass    bool
	FactKeyCompliancePass      bool // legacy composite: keyFactSelectionSemanticPass && citationSemanticPass
	KeyFactSelectionSemanticPass bool
	CitationSemanticPass         bool
	ManualReviewRequired       bool
	Details                    []string
}

// CheckExpectations evaluates deterministic semantic rules for a decoded draft.
func CheckExpectations(c EvaluationCase, draft contract.AssistantAnswerDraftDTO) SemanticResult {
	result := SemanticResult{
		RiskMatch:               true,
		UnknownBehaviorPass:     true,
		StructuredConclusionPass: true,
		ActionCompliancePass:    true,
		ReferenceCompliancePass: true,
		FactKeyCompliancePass:   true,
		KeyFactSelectionSemanticPass: true,
		CitationSemanticPass:         true,
		ManualReviewRequired:    c.ManualReviewRequired,
		UnknownExpectation:      ResolveUnknownExpectation(c),
	}

	narrative := collectNarrative(draft)

	result.ForbiddenClaimHits = findForbiddenClaims(narrative, c.ForbiddenClaims, c.Assessment.DebtDataState)
	if len(result.ForbiddenClaimHits) > 0 {
		result.addFailure(FailureSemanticForbidden, "forbidden claim detected")
	}

	result.DiagnosticKeywordMisses = RecordDiagnosticKeywords(narrative, c.DiagnosticKeywords)

	riskAudit := BuildRiskAudit(c.ExpectedRiskLevel, draft.Warnings)
	result.RiskMatch = riskAudit.Matched
	result.ActualDerivedRisk = riskAudit.ActualDerivedRisk
	result.RiskMismatchDirection = riskAudit.MismatchDirection
	if !riskAudit.Matched {
		result.addFailure(FailureSemanticRisk, "expected risk level mismatch")
	}

	if passed, detail := CheckUnknownExpectation(result.UnknownExpectation, draft.Unknowns); !passed {
		result.UnknownBehaviorPass = false
		result.addFailure(FailureSemanticUnknown, detail)
	}

	if !checkAllowedActions(c.AllowedActions, draft.Actions) {
		result.ActionCompliancePass = false
		result.addFailure(FailureSemanticAction, "action destination not allowed")
	}

	if !checkForbiddenReferences(c.ForbiddenReferences, draft.References) {
		result.ReferenceCompliancePass = false
		result.addFailure(FailureSemanticForbidden, "forbidden reference key")
	}

	if !c.StructuredConclusion.IsZero() {
		passed, missing := CheckStructuredConclusion(c.StructuredConclusion, draft)
		result.StructuredConclusionPass = passed
		result.MissingStructuredConclusions = missing
		if !passed {
			result.addFailure(FailureSemanticConclusion, "structured conclusion missing")
		}
	} else if len(c.RequiredFactKeys) > 0 {
		if !checkRequiredFactKeys(c.RequiredFactKeys, draft) {
			result.FactKeyCompliancePass = false
			result.addFailure(FailureSemanticConclusion, "required fact key missing")
		}
	}

	scope := ResolveForbiddenScopes(c)
	if !checkForbiddenKeyFactSources(scope.KeyFactSources, draft) {
		result.KeyFactSelectionSemanticPass = false
		result.FactKeyCompliancePass = false
		result.addFailure(FailureForbiddenKeyFactSource, "forbidden keyFact source")
	}
	if !checkForbiddenCitationFactKeys(scope.CitationFactKeys, draft) {
		result.CitationSemanticPass = false
		result.FactKeyCompliancePass = false
		result.addFailure(FailureForbiddenCitationFact, "forbidden top-level citation fact key")
	}

	result.Passed = len(result.FailureClasses) == 0
	return result
}

func (r *SemanticResult) addFailure(class, detail string) {
	r.FailureClasses = appendUnique(r.FailureClasses, class)
	r.Details = append(r.Details, detail)
}

func collectNarrative(draft contract.AssistantAnswerDraftDTO) string {
	parts := []string{draft.Title, draft.Body, draft.Answer}
	for _, w := range draft.Warnings {
		parts = append(parts, w.Title, w.Message)
	}
	return strings.ToLower(strings.Join(parts, " "))
}

func findForbiddenClaims(narrative string, forbidden []string, debtDataState string) []string {
	var hits []string
	lower := strings.ToLower(narrative)
	for _, claim := range forbidden {
		if claim == "" {
			continue
		}
		claimLower := strings.ToLower(claim)
		if !strings.Contains(lower, claimLower) {
			continue
		}
		if debtDataState == "knownNoDebt" && isKnownNoDebtDebtPressurePhrase(claim) {
			if !containsUnnegatedPhrase(lower, claimLower) {
				continue
			}
		}
		hits = append(hits, claim)
	}
	return hits
}

func checkAllowedActions(allowed []string, actions []contract.Action) bool {
	if len(allowed) == 0 {
		return true
	}
	allowedSet := map[string]struct{}{}
	for _, a := range allowed {
		allowedSet[a] = struct{}{}
	}
	for _, action := range actions {
		if _, ok := allowedSet[action.Destination]; !ok {
			return false
		}
	}
	return true
}

func checkForbiddenReferences(forbidden []string, refs []contract.Reference) bool {
	if len(forbidden) == 0 {
		return true
	}
	forbiddenSet := map[string]struct{}{}
	for _, key := range forbidden {
		forbiddenSet[key] = struct{}{}
	}
	for _, ref := range refs {
		if _, ok := forbiddenSet[ref.Key]; ok {
			return false
		}
	}
	return true
}

func checkRequiredFactKeys(required []string, draft contract.AssistantAnswerDraftDTO) bool {
	if len(required) == 0 {
		return true
	}
	cited := map[string]struct{}{}
	for _, key := range draft.CitedFactKeys {
		cited[key] = struct{}{}
	}
	for _, fact := range draft.KeyFacts {
		cited[fact.Source] = struct{}{}
	}
	for _, key := range required {
		if _, ok := cited[key]; !ok {
			return false
		}
	}
	return true
}

func checkForbiddenKeyFactSources(forbidden []string, draft contract.AssistantAnswerDraftDTO) bool {
	if len(forbidden) == 0 {
		return true
	}
	forbiddenSet := stringSet(forbidden)
	for _, fact := range draft.KeyFacts {
		if _, ok := forbiddenSet[fact.Source]; ok {
			return false
		}
	}
	return true
}

func checkForbiddenCitationFactKeys(forbidden []string, draft contract.AssistantAnswerDraftDTO) bool {
	if len(forbidden) == 0 {
		return true
	}
	forbiddenSet := stringSet(forbidden)
	for _, key := range draft.CitedFactKeys {
		if _, ok := forbiddenSet[key]; ok {
			return false
		}
	}
	return true
}

// checkForbiddenFactKeys is the legacy combined checker retained for historical compatibility tests.
func checkForbiddenFactKeys(forbidden []string, draft contract.AssistantAnswerDraftDTO) bool {
	if len(forbidden) == 0 {
		return true
	}
	if !checkForbiddenCitationFactKeys(forbidden, draft) {
		return false
	}
	return checkForbiddenKeyFactSources(forbidden, draft)
}

func stringSet(items []string) map[string]struct{} {
	out := make(map[string]struct{}, len(items))
	for _, key := range items {
		out[key] = struct{}{}
	}
	return out
}

func appendUnique(items []string, item string) []string {
	for _, existing := range items {
		if existing == item {
			return items
		}
	}
	return append(items, item)
}

// Failure classification constants.
const (
	FailureNetwork            = "network"
	FailureTimeout            = "timeout"
	FailureProvider           = "provider"
	FailureJSON               = "json"
	FailureDTO                = "model-dto"
	FailureSchema             = "model-schema"
	FailureFact               = "fact-invented"
	FailureFactSourceCompliance = "fact-source-compliance"
	FailureMapping            = "mapping"
	FailurePolicyProjection   = "policy-projection"
	FailureFinalValidator     = "final-validator"
	FailureManualReview       = "manual-review"

	FailureExplanationRiskCoverage    = "explanation-risk-coverage"
	FailureExplanationUnknownCoverage = "explanation-unknown-coverage"
	FailureExplanationCitation        = "explanation-citation" // legacy pre-B5E model citation failures
	FailureProvenanceAssembly         = "provenance-assembly"
	FailureRiskSourceFactUnavailable  = "risk-source-fact-unavailable"
	FailureExplanationUnsupportedRisk = "explanation-unsupported-risk"
	FailureExplanationUnsupportedUnknown = "explanation-unsupported-unknown"

	FailureNarrativeKnownNoDebt      = "narrative-known-no-debt"
	FailureNarrativeMissingData      = "narrative-missing-data"
	FailureNarrativeSafeMissing      = "narrative-safe-missing"
	FailureNarrativeSeverity         = "narrative-severity"
	FailureNarrativeUnsupportedRisk  = "narrative-unsupported-risk"

	FailureFactReference = "fact-reference"
	FailureForbiddenKeyFactSource = "forbidden-keyfact-source"
	FailureForbiddenCitationFact  = "forbidden-citation-fact"

	// Legacy P0-4.4 semantic classes (non-gating in v2).
	FailureSemanticRisk       = "semantic-risk"
	FailureSemanticAction     = "semantic-action"
	FailureSemanticUnknown    = "semantic-unknown"
	FailureSemanticForbidden  = "semantic-forbidden-claim"
	FailureSemanticConclusion = "semantic-conclusion"
)

// ContractStages holds stage pass/fail for classification.
type ContractStages struct {
	HTTPSuccess             bool
	UpstreamHTTP            string
	ContentJSONValid        bool
	GenericJSONObjectDecode string
	DraftDTODecode          string
	DTODecodeErrorKind      string
	AlignmentFailureCode    string
	GatewaySchemaValidation string
	FactValidation          string
	ExplanationAlignment    string
	ProvenanceAssembly      string
	RiskSourceFactAvailability      string
	RiskSourceFactAvailabilityFailureCode string
	ProvenanceAssemblyFailureCode string
	TimeoutStage            string

	RequestAttempted     bool
	HTTPResponseReceived bool
	HTTP2xxSuccess       bool
	ErrorCategory        string
	HTTPStatus           int
	ProviderErrorCode    string
	ProviderErrorMessage string
	SelectedProvider     string
	ModelResponseAssessed bool
}

// ClassifyContractFailure maps decode diagnostics to failure class.
func ClassifyContractFailure(diag ContractStages) string {
	return ClassifyContractFailureWithFactContext(diag, 0, 0)
}

// ClassifyFactValidationFailure maps fact validation diagnostics to eval failure classes.
func ClassifyFactValidationFailure(invalidKeyFactCount, inventedFacts int) string {
	if invalidKeyFactCount > 0 && inventedFacts == 0 {
		return FailureFactSourceCompliance
	}
	return FailureFact
}

// ClassifyContractFailureWithFactContext maps decode diagnostics including fact-validation context.
func ClassifyContractFailureWithFactContext(diag ContractStages, invalidKeyFactCount, inventedFacts int) string {
	if diag.TimeoutStage != "" {
		return FailureTimeout
	}
	if diag.RiskSourceFactAvailability == "fail" {
		return FailureRiskSourceFactUnavailable
	}
	if !contractHTTP2xx(diag) {
		transport := TransportStages{
			RequestAttempted:     diag.RequestAttempted,
			HTTPResponseReceived: diag.HTTPResponseReceived,
			HTTP2xxSuccess:       diag.HTTP2xxSuccess,
			ErrorCategory:        diag.ErrorCategory,
			HTTPStatus:           diag.HTTPStatus,
			ProviderErrorCode:    diag.ProviderErrorCode,
			ProviderErrorMessage: diag.ProviderErrorMessage,
			SelectedProvider:     diag.SelectedProvider,
		}
		if tc := ClassifyTransportFailure(transport, diag); tc != "" {
			return tc
		}
		return FailureConnection
	}
	if diag.UpstreamHTTP != "pass" {
		return FailureProvider
	}
	if !diag.ContentJSONValid || diag.GenericJSONObjectDecode != "pass" {
		return FailureJSON
	}
	if diag.DraftDTODecode != "pass" {
		if diag.DTODecodeErrorKind == "modelMapping" {
			return FailureMapping
		}
		return FailureDTO
	}
	if diag.ExplanationAlignment == "fail" {
		return ClassifyAlignmentFailure(diag.AlignmentFailureCode)
	}
	if diag.ProvenanceAssembly == "fail" {
		return ClassifyProvenanceAssemblyFailure(diag.ProvenanceAssemblyFailureCode)
	}
	if diag.GatewaySchemaValidation != "pass" {
		return FailureSchema
	}
	if diag.FactValidation != "pass" {
		return ClassifyFactValidationFailure(invalidKeyFactCount, inventedFacts)
	}
	return ""
}

func contractHTTP2xx(diag ContractStages) bool {
	if diag.HTTP2xxSuccess {
		return true
	}
	return diag.HTTPSuccess && diag.UpstreamHTTP == "pass"
}

// ClassifyAlignmentFailure maps provider alignment codes to eval failure classes.
func ClassifyAlignmentFailure(code string) string {
	switch code {
	case "riskExplanationCoverageMismatch":
		return FailureExplanationRiskCoverage
	case "riskExplanationReasonNotInAssessment":
		return FailureExplanationUnsupportedRisk
	case "unknownExplanationCoverageMismatch":
		return FailureExplanationUnknownCoverage
	case "unregistered riskExplanation citedFactKey", "riskExplanation citedFactKeyNotInSignalSources", "riskExplanation missingPrimarySource", "duplicate riskExplanation citedFactKey":
		return FailureExplanationCitation
	case "empty unknownExplanation reasonCode", "duplicate unknownExplanation reasonCode":
		return FailureExplanationUnknownCoverage
	default:
		if strings.Contains(code, "unknownExplanation") {
			return FailureExplanationUnknownCoverage
		}
		if strings.Contains(code, "citedFact") || strings.Contains(code, "PrimarySource") {
			return FailureExplanationCitation
		}
		if strings.Contains(code, "riskExplanation") {
			return FailureExplanationRiskCoverage
		}
		return FailureExplanationRiskCoverage
	}
}

func ClassifyProvenanceAssemblyFailure(code string) string {
	switch code {
	case "riskExplanationReasonNotInAssessment":
		return FailureProvenanceAssembly
	case "assembledRiskExplanationProvenanceMismatch", "unregistered riskExplanation citedFactKey", "empty riskExplanation citedFactKey":
		return FailureProvenanceAssembly
	default:
		return FailureProvenanceAssembly
	}
}
