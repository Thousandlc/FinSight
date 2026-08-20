package provider

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
)

const (
	StagePass = "pass"
	StageFail = "fail"
	StageSkip = "skip"
)

const TimeoutStageUpstreamHTTP = "upstreamHTTP"

var requiredModelDraftKeys = []string{
	"title",
	"body",
	"answer",
	"citedFactKeys",
	"confidence",
	"keyFacts",
	"references",
	"riskExplanations",
	"unknownExplanations",
}

// DecodeDiagnostics records stage-by-stage Bailian response processing.
// It never includes prompt, API key, or model content values.
type DecodeDiagnostics struct {
	UpstreamHTTP            string
	OpenAIEnvelopeDecode    string
	ContentPresent          string
	ContentJSONSyntax       string
	GenericJSONObjectDecode string
	DraftDTODecode          string
	ExplanationAlignment    string
	ProvenanceAssembly      string
	ProvenanceAssemblyFailureCode string
	AlignmentFailureCode    string
	GatewaySchemaValidation string
	FactValidation          string

	HTTPStatus  int
	HTTPSuccess bool
	Latency     time.Duration
	TimeoutStage string

	ContentJSONValid bool
	ContentLength    int
	TopLevelKeys     []string

	DTODecodeErrorKind string
	DTODecodeErrorPath string
	ExpectedType       string
	ActualJSONType     string
	MissingKey         string
	UnexpectedTopLevelKeys []string

	// Populated when model draft decodes; retained even when explanation alignment fails.
	ActualRiskExplanationReasons    []string
	ActualUnknownExplanationReasons []string
	ActualModelCitedFactKeys        []string
	AssembledCitedFactKeys          []string
	RiskExplanationDiagnostics      []RiskExplanationDiagnostic
	UnknownExplanationDiagnostics   []UnknownExplanationDiagnostic

	PromptTokens     int
	CompletionTokens int
	TotalTokens      int

	TitleValid       bool
	BodyValid        bool
	AnswerValid      bool
	ArraysValid      bool
	EnumValid        bool
	KeyFactKindValid         bool
	KeyFactValueValid        bool
	WarningSeverityValid     bool
	ActionDestinationValid   bool
	InvalidEnumField         string
	InvalidEnumValue         string
	KeyFactKinds             []string
	KeyFactValueTypes        []string
	WarningSeverities        []string
	ActionDestinations       []string
	ConfiguredModel          string
	UpstreamModel            string
	SchemaFailedRule string
	InventedFacts    int
	InvalidReferences int
	InvalidActions   int

	AmountFactsValid       bool
	CitedFactKeysValid     bool
	KeyFactSourcesValid    bool
	KeyFactValuesValid     bool
	ReferencesValid        bool
	ActionsValid           bool
	WarningSourcesValid    bool
	PercentFactsValid      bool
	DateFactsValid         bool
	InvalidCitedKeyCount   int
	InvalidKeyFactCount    int
	InvalidWarningSources  int
	FactFailureRules       []string
	InvalidFactRule        string
	InvalidFactKey         string
	InvalidFactSource      string
	ExpectedFactKey        string
	ActualFactKey          string

	FailingKeyFactIndex    int
	FailingKeyFactKind     string
	KeyFactValueJSONType   string
	KeyFactValueKeys       []string
	KeyFactValueFieldTypes []string
	KeyFactValueSchemaMeta string

	RequestBuilt            bool
	TransportPerformStarted bool
	HTTPResponseReceived    bool
	HTTP2xxSuccess          bool
	RequestURLScheme        string
	RequestURLHost          string
	RequestURLPath          string
	ErrorCategory           string
	ProviderErrorCode       string
	ProviderErrorMessage    string
	SelectedProvider        string

	ProviderAttemptCount int
	ProviderTotalMs      time.Duration
	BackoffMs            time.Duration
}

// RiskExplanationDiagnostic holds synthetic-eval-safe structured risk explanation fields.
type RiskExplanationDiagnostic struct {
	ReasonCode    string   `json:"reasonCode"`
	CitedFactKeys []string `json:"citedFactKeys,omitempty"`
	Text          string   `json:"text,omitempty"`
}

// UnknownExplanationDiagnostic holds synthetic-eval-safe structured unknown explanation fields.
type UnknownExplanationDiagnostic struct {
	ReasonCode string `json:"reasonCode"`
	Text       string `json:"text,omitempty"`
}

func (d DecodeDiagnostics) EndToEndSuccess() bool {
	alignmentOK := d.ExplanationAlignment == StagePass || d.ExplanationAlignment == StageSkip
	provenanceOK := d.ProvenanceAssembly == StagePass || d.ProvenanceAssembly == StageSkip
	return d.UpstreamHTTP == StagePass &&
		d.OpenAIEnvelopeDecode == StagePass &&
		d.ContentPresent == StagePass &&
		d.ContentJSONSyntax == StagePass &&
		d.GenericJSONObjectDecode == StagePass &&
		d.DraftDTODecode == StagePass &&
		alignmentOK &&
		provenanceOK &&
		d.GatewaySchemaValidation == StagePass &&
		d.FactValidation == StagePass
}

// AnalyzeContent inspects model message.content without logging the content.
// When assessment and facts are provided, explanation alignment is validated before mapping.
func AnalyzeContent(
	content string,
	assessment *contract.FinancialRiskAssessmentDTO,
	facts *contract.MonthlySummaryFactsDTO,
) (contract.AssistantAnswerDraftDTO, DecodeDiagnostics) {
	diag := DecodeDiagnostics{
		ContentPresent:          StageSkip,
		ContentJSONSyntax:       StageSkip,
		GenericJSONObjectDecode: StageSkip,
		DraftDTODecode:          StageSkip,
		GatewaySchemaValidation: StageSkip,
		FactValidation:          StageSkip,
	}
	trimmed := strings.TrimSpace(content)
	diag.ContentLength = len(trimmed)
	if trimmed == "" {
		diag.ContentPresent = StageFail
		diag.DTODecodeErrorKind = "emptyContent"
		return contract.AssistantAnswerDraftDTO{}, diag
	}
	diag.ContentPresent = StagePass

	diag.ContentJSONValid = json.Valid([]byte(trimmed))
	if !diag.ContentJSONValid {
		diag.ContentJSONSyntax = StageFail
		diag.DTODecodeErrorKind = "syntax"
		return contract.AssistantAnswerDraftDTO{}, diag
	}
	diag.ContentJSONSyntax = StagePass

	var generic map[string]any
	if err := json.Unmarshal([]byte(trimmed), &generic); err != nil || generic == nil {
		diag.GenericJSONObjectDecode = StageFail
		diag.ActualJSONType = jsonTokenType(trimmed)
	} else {
		diag.GenericJSONObjectDecode = StagePass
		keys := make([]string, 0, len(generic))
		for k := range generic {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		diag.TopLevelKeys = keys
		for _, key := range keys {
			if !prompt.IsAllowedModelDraftTopLevelKey(key) {
				diag.UnexpectedTopLevelKeys = append(diag.UnexpectedTopLevelKeys, key)
			}
		}
		if missing := missingRequiredKeys(generic); len(missing) > 0 {
			diag.MissingKey = strings.Join(missing, ",")
		}
		if hasForbiddenModelKeyFactValueField(generic) {
			diag.DraftDTODecode = StageFail
			diag.DTODecodeErrorKind = "modelValidation"
			diag.DTODecodeErrorPath = "keyFacts.value"
			diagnoseKeyFactValueFailure(generic, &diag)
			return contract.AssistantAnswerDraftDTO{}, diag
		}
	}

	var model contract.ModelAssistantAnswerDraftDTO
	if err := json.Unmarshal([]byte(trimmed), &model); err != nil {
		diag.DraftDTODecode = StageFail
		fillDTODecodeError(&diag, err)
		if generic != nil {
			diagnoseKeyFactValueFailure(generic, &diag)
		}
		return contract.AssistantAnswerDraftDTO{}, diag
	}
	if err := ValidateModelDraft(model); err != nil {
		diag.DraftDTODecode = StageFail
		diag.DTODecodeErrorKind = "modelValidation"
		diag.DTODecodeErrorPath = "keyFacts"
		return contract.AssistantAnswerDraftDTO{}, diag
	}
	diag.DraftDTODecode = StagePass
	populateModelExplanationDiagnostics(&diag, model)
	if assessment != nil && facts != nil {
		keySets := factpack.BuildKeySetsForRequest(facts, assessment)
		if err := ValidateKeyFactSelection(model, keySets); err != nil {
			diag.DraftDTODecode = StageFail
			diag.DTODecodeErrorKind = "keyFactSelection"
			diag.DTODecodeErrorPath = "keyFacts.source"
			diag.AlignmentFailureCode = KeyFactSelectionFailureCode
			return contract.AssistantAnswerDraftDTO{}, diag
		}
		if err := ValidateExplanationAlignment(model, assessment, keySets); err != nil {
			diag.ExplanationAlignment = StageFail
			diag.DTODecodeErrorKind = "explanationAlignment"
			diag.AlignmentFailureCode = ParseAlignmentFailureCode(err)
			return contract.AssistantAnswerDraftDTO{}, diag
		}
		diag.ExplanationAlignment = StagePass

		draft, err := MapModelDraftToGateway(model, assessment, facts)
		if err != nil {
			diag.ProvenanceAssembly = StageFail
			diag.DTODecodeErrorKind = "provenanceAssembly"
			diag.ProvenanceAssemblyFailureCode = ParseProvenanceAssemblyFailureCode(err)
			return contract.AssistantAnswerDraftDTO{}, diag
		}
		if err := ValidateAssembledRiskExplanationProvenance(draft.RiskExplanations, assessment, keySets); err != nil {
			diag.ProvenanceAssembly = StageFail
			diag.DTODecodeErrorKind = "provenanceAssembly"
			diag.ProvenanceAssemblyFailureCode = ParseProvenanceAssemblyFailureCode(err)
			return contract.AssistantAnswerDraftDTO{}, diag
		}
		diag.ProvenanceAssembly = StagePass
		populateAssembledExplanationDiagnostics(&diag, draft)
		return draft, diag
	}
	diag.ExplanationAlignment = StageSkip
	diag.ProvenanceAssembly = StageSkip
	return contract.AssistantAnswerDraftDTO{}, diag
}

// mergeContentDiagnostics copies AnalyzeContent stage results into transport-level diagnostics.
// Provider/transport fields already set on dst are preserved.
func mergeContentDiagnostics(dst *DecodeDiagnostics, src DecodeDiagnostics) {
	dst.ContentPresent = src.ContentPresent
	dst.ContentJSONSyntax = src.ContentJSONSyntax
	dst.GenericJSONObjectDecode = src.GenericJSONObjectDecode
	dst.DraftDTODecode = src.DraftDTODecode
	dst.ExplanationAlignment = src.ExplanationAlignment
	dst.ProvenanceAssembly = src.ProvenanceAssembly
	dst.ProvenanceAssemblyFailureCode = src.ProvenanceAssemblyFailureCode
	dst.AlignmentFailureCode = src.AlignmentFailureCode
	dst.ContentJSONValid = src.ContentJSONValid
	dst.ContentLength = src.ContentLength
	dst.TopLevelKeys = src.TopLevelKeys
	dst.UnexpectedTopLevelKeys = src.UnexpectedTopLevelKeys
	dst.DTODecodeErrorKind = src.DTODecodeErrorKind
	dst.DTODecodeErrorPath = src.DTODecodeErrorPath
	dst.ExpectedType = src.ExpectedType
	dst.ActualJSONType = src.ActualJSONType
	dst.MissingKey = src.MissingKey
	dst.FailingKeyFactIndex = src.FailingKeyFactIndex
	dst.FailingKeyFactKind = src.FailingKeyFactKind
	dst.KeyFactValueJSONType = src.KeyFactValueJSONType
	dst.KeyFactValueKeys = src.KeyFactValueKeys
	dst.KeyFactValueFieldTypes = src.KeyFactValueFieldTypes
	dst.ActualRiskExplanationReasons = src.ActualRiskExplanationReasons
	dst.ActualUnknownExplanationReasons = src.ActualUnknownExplanationReasons
	dst.ActualModelCitedFactKeys = src.ActualModelCitedFactKeys
	dst.AssembledCitedFactKeys = src.AssembledCitedFactKeys
	dst.RiskExplanationDiagnostics = src.RiskExplanationDiagnostics
	dst.UnknownExplanationDiagnostics = src.UnknownExplanationDiagnostics
}

func populateModelExplanationDiagnostics(diag *DecodeDiagnostics, model contract.ModelAssistantAnswerDraftDTO) {
	for _, exp := range model.RiskExplanations {
		if exp.ReasonCode != "" {
			diag.ActualRiskExplanationReasons = append(diag.ActualRiskExplanationReasons, exp.ReasonCode)
		}
		diag.RiskExplanationDiagnostics = append(diag.RiskExplanationDiagnostics, RiskExplanationDiagnostic{
			ReasonCode: strings.TrimSpace(exp.ReasonCode),
			Text:       sanitizeDiagnosticText(exp.Text),
		})
	}
	sort.Strings(diag.ActualRiskExplanationReasons)
	for _, exp := range model.UnknownExplanations {
		if exp.ReasonCode != "" {
			diag.ActualUnknownExplanationReasons = append(diag.ActualUnknownExplanationReasons, exp.ReasonCode)
		}
		diag.UnknownExplanationDiagnostics = append(diag.UnknownExplanationDiagnostics, UnknownExplanationDiagnostic{
			ReasonCode: strings.TrimSpace(exp.ReasonCode),
			Text:       sanitizeDiagnosticText(exp.Text),
		})
	}
	sort.Strings(diag.ActualUnknownExplanationReasons)
	if len(model.CitedFactKeys) > 0 {
		diag.ActualModelCitedFactKeys = append([]string(nil), model.CitedFactKeys...)
		sort.Strings(diag.ActualModelCitedFactKeys)
	}
}

func sanitizeDiagnosticText(text string) string {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return ""
	}
	const maxLen = 240
	if len(trimmed) > maxLen {
		return trimmed[:maxLen] + "…"
	}
	return trimmed
}

func populateAssembledExplanationDiagnostics(diag *DecodeDiagnostics, draft contract.AssistantAnswerDraftDTO) {
	diag.RiskExplanationDiagnostics = diag.RiskExplanationDiagnostics[:0]
	for _, exp := range draft.RiskExplanations {
		diag.RiskExplanationDiagnostics = append(diag.RiskExplanationDiagnostics, RiskExplanationDiagnostic{
			ReasonCode:    strings.TrimSpace(exp.ReasonCode),
			CitedFactKeys: cloneStringSlicePreserveOrder(exp.CitedFactKeys),
			Text:          sanitizeDiagnosticText(exp.Text),
		})
		for _, key := range exp.CitedFactKeys {
			diag.AssembledCitedFactKeys = append(diag.AssembledCitedFactKeys, key)
		}
	}
}

func cloneStringSlicePreserveOrder(items []string) []string {
	if len(items) == 0 {
		return nil
	}
	out := append([]string(nil), items...)
	return out
}

func cloneStringSlice(items []string) []string {
	if len(items) == 0 {
		return nil
	}
	out := append([]string(nil), items...)
	sort.Strings(out)
	return out
}

func fillDTODecodeError(diag *DecodeDiagnostics, err error) {
	diag.FailingKeyFactIndex = -1
	var ute *json.UnmarshalTypeError
	if errors.As(err, &ute) {
		diag.DTODecodeErrorKind = "typeMismatch"
		diag.DTODecodeErrorPath = ute.Field
		if ute.Type != nil {
			diag.ExpectedType = ute.Type.String()
		}
		diag.ActualJSONType = ute.Value
		return
	}
	var se *json.SyntaxError
	if errors.As(err, &se) {
		diag.DTODecodeErrorKind = "syntax"
		return
	}
	diag.DTODecodeErrorKind = "dataCorrupted"
}

func diagnoseKeyFactValueFailure(generic map[string]any, diag *DecodeDiagnostics) {
	keyFacts, ok := generic["keyFacts"].([]any)
	if !ok {
		return
	}
	for i, item := range keyFacts {
		factObj, ok := item.(map[string]any)
		if !ok {
			setKeyFactValueDiagnostics(diag, i, "", "non-object", nil)
			return
		}
		kind, _ := factObj["kind"].(string)
		if _, exists := factObj["value"]; exists {
			valueRaw := factObj["value"]
			valueType := jsonTokenTypeFromValue(valueRaw)
			valueObj, _ := valueRaw.(map[string]any)
			setKeyFactValueDiagnostics(diag, i, kind, valueType, valueObj)
			return
		}
	}
}

func setKeyFactValueDiagnostics(
	diag *DecodeDiagnostics,
	index int,
	kind string,
	valueJSONType string,
	valueObj map[string]any,
) {
	diag.FailingKeyFactIndex = index
	diag.FailingKeyFactKind = kind
	diag.KeyFactValueJSONType = valueJSONType
	if valueObj == nil {
		return
	}
	keys := make([]string, 0, len(valueObj))
	for key := range valueObj {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	diag.KeyFactValueKeys = keys
	fieldTypes := make([]string, 0, len(keys))
	for _, key := range keys {
		fieldTypes = append(fieldTypes, key+":"+jsonTokenTypeFromValue(valueObj[key]))
	}
	diag.KeyFactValueFieldTypes = fieldTypes
}

func missingRequiredKeys(obj map[string]any) []string {
	var missing []string
	for _, key := range requiredModelDraftKeys {
		if _, ok := obj[key]; !ok {
			missing = append(missing, key)
		}
	}
	return missing
}

func hasForbiddenModelKeyFactValueField(generic map[string]any) bool {
	keyFacts, ok := generic["keyFacts"].([]any)
	if !ok {
		return false
	}
	for _, item := range keyFacts {
		factObj, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if _, exists := factObj["value"]; exists {
			return true
		}
	}
	return false
}

func jsonTokenTypeFromValue(doc any) string {
	switch doc.(type) {
	case map[string]any:
		return "object"
	case []any:
		return "array"
	case string:
		return "string"
	case float64:
		return "number"
	case bool:
		return "bool"
	case nil:
		return "null"
	default:
		return "unknown"
	}
}

func jsonTokenType(raw string) string {
	var probe any
	if err := json.Unmarshal([]byte(raw), &probe); err != nil {
		return "invalid"
	}
	switch probe.(type) {
	case map[string]any:
		return "object"
	case []any:
		return "array"
	case string:
		return "string"
	case float64:
		return "number"
	case bool:
		return "bool"
	case nil:
		return "null"
	default:
		return "unknown"
	}
}

func maybeDumpRawContent(requestID, content string) {
	if strings.EqualFold(strings.TrimSpace(os.Getenv("YOUSHU_ENV")), config.EnvProduction) {
		return
	}
	if os.Getenv("YOUSHU_SMOKE_DUMP_RAW") != "1" {
		return
	}
	if strings.TrimSpace(content) == "" {
		return
	}
	_ = os.MkdirAll(".smoke-output", 0o700)
	name := sanitizeDumpName(requestID) + ".json"
	_ = os.WriteFile(filepath.Join(".smoke-output", name), []byte(content), 0o600)
}

func sanitizeDumpName(requestID string) string {
	cleaned := strings.Map(func(r rune) rune {
		if r == '/' || r == '\\' || r == ':' || r == ' ' {
			return '-'
		}
		return r
	}, requestID)
	if cleaned == "" {
		return "unknown"
	}
	return cleaned
}

func httpSuccessStatus(status int) bool {
	return status >= 200 && status <= 299
}
