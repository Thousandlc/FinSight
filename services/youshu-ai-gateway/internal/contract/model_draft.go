package contract

// ModelKeyFactValueDTO is the fixed-shape provider transport value for Bailian structured output.
// It is not part of the iOS-facing Gateway response contract.
type ModelKeyFactValueDTO struct {
	Type         string   `json:"type"`
	Amount       *float64 `json:"amount"`
	CurrencyCode *string  `json:"currencyCode"`
	TextValue    *string  `json:"textValue"`
	PercentValue *float64 `json:"percentValue"`
	DateValue    *string  `json:"dateValue"`
}

// ModelKeyFactDTO is a provider transport key fact row.
// Canonical value ownership belongs to the application materializer; the model selects source/label/kind only.
type ModelKeyFactDTO struct {
	Label  string `json:"label"`
	Kind   string `json:"kind"`
	Source string `json:"source"`
}

// ModelRiskExplanationDTO is provider transport for model-authored risk explanation text.
// Provenance citations are assembled deterministically at the gateway mapping boundary.
type ModelRiskExplanationDTO struct {
	ReasonCode string `json:"reasonCode"`
	Text       string `json:"text"`
}

// ModelUnknownExplanationDTO is provider transport for required unknown acknowledgment.
type ModelUnknownExplanationDTO struct {
	ReasonCode string `json:"reasonCode"`
	Text       string `json:"text"`
}

// ModelAssistantAnswerDraftDTO is the Bailian structured-output transport envelope.
// Warnings/actions are policy-owned and omitted from model output.
type ModelAssistantAnswerDraftDTO struct {
	Title               string                       `json:"title"`
	Body                string                       `json:"body"`
	Answer              string                       `json:"answer"`
	CitedFactKeys       []string                     `json:"citedFactKeys"`
	Disclaimer          *string                      `json:"disclaimer,omitempty"`
	Confidence          float64                      `json:"confidence"`
	KeyFacts            []ModelKeyFactDTO            `json:"keyFacts"`
	References          []Reference                  `json:"references"`
	RiskExplanations    []ModelRiskExplanationDTO    `json:"riskExplanations"`
	UnknownExplanations []ModelUnknownExplanationDTO `json:"unknownExplanations"`
}
