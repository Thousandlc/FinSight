package contract



import (

	"encoding/json"

	"fmt"

)



type KeyFactValue struct {

	Type         string   `json:"type"`

	Amount       *float64 `json:"amount,omitempty"`

	CurrencyCode *string  `json:"currencyCode,omitempty"`

	TextValue    *string  `json:"-"`

	PercentValue *float64 `json:"-"`

	Date         *string  `json:"date,omitempty"`

}



func (v KeyFactValue) MarshalJSON() ([]byte, error) {

	payload := map[string]any{"type": v.Type}

	switch v.Type {

	case "money":

		if v.Amount != nil {

			payload["amount"] = *v.Amount

		}

		if v.CurrencyCode != nil {

			payload["currencyCode"] = *v.CurrencyCode

		}

	case "text":

		if v.TextValue != nil {

			payload["value"] = *v.TextValue

		}

	case "percent":

		if v.PercentValue != nil {

			payload["value"] = *v.PercentValue

		}

	case "date":

		if v.Date != nil {

			payload["date"] = *v.Date

		}

	default:

		return nil, fmt.Errorf("unknown key fact value type: %s", v.Type)

	}

	return json.Marshal(payload)

}



func (v *KeyFactValue) UnmarshalJSON(data []byte) error {

	*v = KeyFactValue{}

	var probe struct {

		Type string `json:"type"`

	}

	if err := json.Unmarshal(data, &probe); err != nil {

		return err

	}

	v.Type = probe.Type

	switch probe.Type {

	case "money":

		var raw struct {

			Amount       *float64 `json:"amount"`

			CurrencyCode *string  `json:"currencyCode"`

		}

		if err := json.Unmarshal(data, &raw); err != nil {

			return err

		}

		v.Amount = raw.Amount

		v.CurrencyCode = raw.CurrencyCode

	case "text":

		var raw struct {

			Value *string `json:"value"`

		}

		if err := json.Unmarshal(data, &raw); err != nil {

			return err

		}

		v.TextValue = raw.Value

	case "percent":

		var raw struct {

			Value *float64 `json:"value"`

		}

		if err := json.Unmarshal(data, &raw); err != nil {

			return err

		}

		v.PercentValue = raw.Value

	case "date":

		var raw struct {

			Date *string `json:"date"`

		}

		if err := json.Unmarshal(data, &raw); err != nil {

			return err

		}

		v.Date = raw.Date

	default:

		return fmt.Errorf("unknown key fact value type: %s", probe.Type)

	}

	return nil

}



type KeyFact struct {

	Label  string       `json:"label"`

	Value  KeyFactValue `json:"value"`

	Kind   string       `json:"kind"`

	Source string       `json:"source"`

}



type Warning struct {

	Title    string `json:"title"`

	Message  string `json:"message"`

	Severity string `json:"severity"`

	Source   string `json:"source"`

}



type Action struct {

	Title       string `json:"title"`

	Destination string `json:"destination"`

}



type Reference struct {

	Key string `json:"key"`

}



// RiskExplanationDTO is a gateway-facing structured risk explanation with deterministic provenance.
type RiskExplanationDTO struct {
	ReasonCode    string   `json:"reasonCode"`
	Text          string   `json:"text"`
	CitedFactKeys []string `json:"citedFactKeys"`
}



type AssistantAnswerDraftDTO struct {

	Title          string      `json:"title"`

	Body           string      `json:"body"`

	Answer         string      `json:"answer"`

	CitedFactKeys  []string    `json:"citedFactKeys"`

	Disclaimer     *string     `json:"disclaimer,omitempty"`

	Unknowns       []string    `json:"unknowns"`

	Confidence     float64     `json:"confidence"`

	KeyFacts       []KeyFact   `json:"keyFacts"`

	Warnings       []Warning   `json:"warnings"`

	Actions        []Action    `json:"actions"`

	References       []Reference          `json:"references"`
	RiskExplanations []RiskExplanationDTO `json:"riskExplanations"`

}



type GatewayErrorBody struct {

	Code              string `json:"code"`

	Message           string `json:"message"`

	RetryAfterSeconds *int   `json:"retryAfterSeconds,omitempty"`

}



type SuccessEnvelope struct {

	SchemaVersion string                  `json:"schemaVersion"`

	RequestID     string                  `json:"requestId"`

	ModelAlias    string                  `json:"modelAlias"`

	Draft         AssistantAnswerDraftDTO `json:"draft"`

}



type ErrorEnvelope struct {

	SchemaVersion string           `json:"schemaVersion"`

	RequestID     string           `json:"requestId"`

	Error         GatewayErrorBody `json:"error"`

}



const (

	ErrInvalidRequest           = "invalidRequest"

	ErrUnauthorized             = "unauthorized"

	ErrRateLimited              = "rateLimited"

	ErrGatewayRateLimited       = "gatewayRateLimited"

	ErrProviderRateLimited      = "providerRateLimited"

	ErrProviderUnavailable      = "providerUnavailable"

	ErrProviderTimeout          = "providerTimeout"

	ErrInvalidProviderResponse  = "invalidProviderResponse"

	ErrUnsupportedSchemaVersion = "unsupportedSchemaVersion"

	ErrUnsupportedOperation     = "unsupportedOperation"

	ErrInternalError            = "internalError"

)


