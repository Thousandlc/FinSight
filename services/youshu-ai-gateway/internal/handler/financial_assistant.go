package handler

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

type FinancialAssistantHandler struct {
	SchemaVersion string
	ModelAlias    string
	Upstream      provider.UpstreamAIProvider
}

func (h *FinancialAssistantHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		h.writeError(w, http.StatusMethodNotAllowed, "", contract.ErrInvalidRequest, "仅支持 POST 请求。", nil)
		return
	}

	var req contract.RequestEnvelope
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.writeError(w, http.StatusBadRequest, "", contract.ErrInvalidRequest, "请求格式无效。", nil)
		return
	}

	requestID := strings.TrimSpace(req.RequestID)
	if requestID == "" {
		h.writeError(w, http.StatusBadRequest, "", contract.ErrInvalidRequest, "缺少 requestId。", nil)
		return
	}

	if req.SchemaVersion != h.SchemaVersion {
		h.writeError(w, http.StatusBadRequest, requestID, contract.ErrUnsupportedSchemaVersion, "不支持的 schema 版本。", nil)
		return
	}

	switch req.Operation {
	case contract.OperationMonthlySummary:
		h.handleMonthlySummary(w, r, req, requestID)
	default:
		h.writeError(w, http.StatusBadRequest, requestID, contract.ErrUnsupportedOperation, "当前不支持该操作。", nil)
	}
}

func (h *FinancialAssistantHandler) handleMonthlySummary(
	w http.ResponseWriter,
	r *http.Request,
	req contract.RequestEnvelope,
	requestID string,
) {
	if req.MonthlySummaryFacts == nil {
		h.writeError(w, http.StatusBadRequest, requestID, contract.ErrInvalidRequest, "monthlySummary 缺少 monthlySummaryFacts。", nil)
		return
	}
	if err := ValidateRequestEnvelope(req); err != nil {
		h.writeError(w, http.StatusBadRequest, requestID, contract.ErrInvalidRequest, formatRiskValidationError(err), nil)
		return
	}

	draft, err := h.Upstream.CompleteMonthlySummary(r.Context(), req)
	if err != nil {
		status, code, message, retryAfter := mapUpstreamError(err)
		h.writeError(w, status, requestID, code, message, retryAfter)
		return
	}

	if err := ValidateDraft(draft); err != nil {
		h.writeError(w, http.StatusBadGateway, requestID, contract.ErrInvalidProviderResponse, "上游响应未通过 schema 校验。", nil)
		return
	}

	resp := contract.SuccessEnvelope{
		SchemaVersion: h.SchemaVersion,
		RequestID:     requestID,
		ModelAlias:    h.ModelAlias,
		Draft:         draft,
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func ValidateDraft(d contract.AssistantAnswerDraftDTO) error {
	if strings.TrimSpace(d.Title) == "" {
		return errValidation("empty title")
	}
	if strings.TrimSpace(d.Body) == "" {
		return errValidation("empty body")
	}
	if strings.TrimSpace(d.Answer) == "" {
		return errValidation("empty answer")
	}
	if d.KeyFacts == nil {
		return errValidation("nil keyFacts")
	}
	if d.Warnings == nil {
		return errValidation("nil warnings")
	}
	if d.Actions == nil {
		return errValidation("nil actions")
	}
	if d.References == nil {
		return errValidation("nil references")
	}
	if d.CitedFactKeys == nil {
		return errValidation("nil citedFactKeys")
	}
	if d.Unknowns == nil {
		return errValidation("nil unknowns")
	}
	for _, fact := range d.KeyFacts {
		if !isValidKind(fact.Kind) {
			return errValidation("invalid keyFact kind")
		}
		if !isValidKeyFactValue(fact.Value) {
			return errValidation("invalid keyFact value")
		}
	}
	for _, warning := range d.Warnings {
		if !isValidSeverity(warning.Severity) {
			return errValidation("invalid warning severity")
		}
	}
	for _, action := range d.Actions {
		if !isValidDestination(action.Destination) {
			return errValidation("invalid action destination")
		}
	}
	return nil
}

type validationError struct{ msg string }

func (e validationError) Error() string { return e.msg }

func errValidation(msg string) error { return validationError{msg: msg} }

func isValidKind(kind string) bool {
	switch kind {
	case "balance", "income", "expense", "debt", "cashFlow", "savings", "purchase", "other":
		return true
	default:
		return false
	}
}

func isValidSeverity(severity string) bool {
	switch severity {
	case "safe", "warning", "risk":
		return true
	default:
		return false
	}
}

func isValidDestination(dest string) bool {
	switch dest {
	case "cashFlow", "debt", "transactions", "accounts":
		return true
	default:
		return false
	}
}

func isValidKeyFactValue(v contract.KeyFactValue) bool {
	switch v.Type {
	case "money":
		return v.Amount != nil && v.CurrencyCode != nil && strings.TrimSpace(*v.CurrencyCode) != ""
	case "text":
		return v.TextValue != nil && strings.TrimSpace(*v.TextValue) != ""
	case "percent":
		return v.PercentValue != nil
	case "date":
		return v.Date != nil && strings.TrimSpace(*v.Date) != ""
	default:
		return false
	}
}

func (h *FinancialAssistantHandler) writeError(
	w http.ResponseWriter,
	status int,
	requestID string,
	code string,
	message string,
	retryAfter *int,
) {
	resp := contract.ErrorEnvelope{
		SchemaVersion: h.SchemaVersion,
		RequestID:     requestID,
		Error: contract.GatewayErrorBody{
			Code:              code,
			Message:           message,
			RetryAfterSeconds: retryAfter,
		},
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(resp)
}
