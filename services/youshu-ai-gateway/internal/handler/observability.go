package handler

import (
	"errors"
	"net/http"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/observability"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func observeSuccess(r *http.Request) {
	if rec := observability.FromContext(r.Context()); rec != nil {
		rec.Success()
	}
}

func observeFailure(r *http.Request, class observability.Classification, schemaStage string) {
	rec := observability.FromContext(r.Context())
	if rec == nil {
		return
	}
	if schemaStage != "" {
		rec.SetSchemaStage(schemaStage)
	}
	rec.Fail(class)
}

func observeValidationFailure(r *http.Request, code string) {
	stage := observability.StageGatewayRequestValidation
	schemaStage := ""
	switch code {
	case contract.ErrUnsupportedSchemaVersion:
		schemaStage = observability.SchemaRequestEnvelope
	case contract.ErrInvalidRequest:
		schemaStage = observability.SchemaRequestEnvelope
	}
	observeFailure(r, observability.Classify(code, stage), schemaStage)
}

func observeUpstreamFailure(r *http.Request, err error, httpCode string) {
	class, schemaStage := classifyUpstreamForTelemetry(err, httpCode)
	observeFailure(r, class, schemaStage)
	if rec := observability.FromContext(r.Context()); rec != nil {
		var upstream *provider.UpstreamError
		if errors.As(err, &upstream) && upstream.ProviderStatus != "" {
			rec.SetProviderStatus(upstream.ProviderStatus)
		}
	}
}

func classifyUpstreamForTelemetry(err error, httpCode string) (observability.Classification, string) {
	var mat *factpack.MaterializationError
	if errors.As(err, &mat) {
		code := mat.Code
		if code == "" {
			code = observability.CodeMaterializationFailure
		}
		return observability.Classify(code, observability.StageFactMaterialization), ""
	}
	var upstream *provider.UpstreamError
	if errors.As(err, &upstream) {
		code := upstream.TelemetryCode()
		stage := upstream.Stage
		if stage == "" {
			stage = observability.StageUnknown
		}
		return observability.Classify(code, stage), upstream.SchemaStage
	}
	if httpCode == "" {
		httpCode = observability.CodeInvalidProviderResponse
	}
	return observability.Classify(httpCode, observability.StageUnknown), ""
}

func observeEncodingFailure(r *http.Request) {
	observeFailure(r, observability.Classify(observability.CodeSerializationFailure, observability.StageGatewayResponseEncoding), observability.SchemaGatewayDraft)
}

func observeDraftValidationFailure(r *http.Request) {
	observeFailure(r, observability.Classify(observability.CodeInvalidProviderResponse, observability.StageGatewayResponseEncoding), observability.SchemaGatewayDraft)
}

func setOperation(r *http.Request, operation string) {
	if rec := observability.FromContext(r.Context()); rec != nil {
		rec.SetOperation(operation)
	}
}
