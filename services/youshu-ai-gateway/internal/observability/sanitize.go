package observability

import "strings"

func SanitizeSchemaStage(raw string) string {
	switch raw {
	case "", SchemaRequestEnvelope, SchemaModelDraft, SchemaGatewayDraft, SchemaClientDraft, SchemaUnknown:
		return raw
	default:
		return SchemaUnknown
	}
}

func SanitizeProvider(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "":
		return ""
	case ProviderBailian:
		return ProviderBailian
	case ProviderMock:
		return ProviderMock
	default:
		return ProviderUnknown
	}
}

func SanitizeModel(raw string) string {
	s := strings.TrimSpace(raw)
	if s == "" {
		return ""
	}
	lower := strings.ToLower(s)
	if strings.Contains(s, "sk-") || strings.Contains(lower, "bearer") || strings.Contains(lower, "authorization") {
		return "redacted"
	}
	if len(s) > 64 {
		return s[:64]
	}
	return s
}

func SanitizeOperation(raw string) string {
	switch raw {
	case OperationMonthlySummary, OperationAsk, OperationInsight, OperationPurchaseScenario:
		return raw
	case "":
		return ""
	default:
		return OperationUnknown
	}
}
