package eval

// UnknownExpectation defines evaluation-only unknowns behavior.
type UnknownExpectation string

const (
	UnknownNotRequired UnknownExpectation = "notRequired" // unknowns may be empty or present
	UnknownRequired    UnknownExpectation = "required"    // must express missing information
	UnknownForbidden   UnknownExpectation = "forbidden"   // facts are complete; must not claim unknown
)

// StructuredConclusionExpectation defines deterministic structured conclusion checks.
type StructuredConclusionExpectation struct {
	RequiredFactKeys          []string `json:"requiredFactKeys,omitempty"`
	RequiredAnyWarningSources []string `json:"requiredAnyWarningSources,omitempty"`
	RequiredAnyReferenceKeys  []string `json:"requiredAnyReferenceKeys,omitempty"`
	RequireWarning            bool     `json:"requireWarning,omitempty"`
}

func (e StructuredConclusionExpectation) IsZero() bool {
	return len(e.RequiredFactKeys) == 0 &&
		len(e.RequiredAnyWarningSources) == 0 &&
		len(e.RequiredAnyReferenceKeys) == 0 &&
		!e.RequireWarning
}

// CheckUnknownExpectation validates unknowns array against expectation.
func CheckUnknownExpectation(expectation UnknownExpectation, unknowns []string) (passed bool, detail string) {
	switch expectation {
	case "", UnknownNotRequired:
		return true, ""
	case UnknownRequired:
		if len(unknowns) == 0 {
			return false, "unknowns must be non-empty when debt/data is genuinely missing"
		}
		return true, ""
	case UnknownForbidden:
		if len(unknowns) > 0 {
			return false, "unknowns must be empty when facts are complete"
		}
		return true, ""
	default:
		return true, ""
	}
}

// ResolveUnknownExpectation returns the effective expectation for a case.
func ResolveUnknownExpectation(c EvaluationCase) UnknownExpectation {
	if c.UnknownExpectation != "" {
		return c.UnknownExpectation
	}
	if c.RequiredUnknowns {
		return UnknownRequired
	}
	return UnknownNotRequired
}
