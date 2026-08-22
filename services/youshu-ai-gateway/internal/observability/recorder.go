package observability

import (
	"context"
	"sync"
)

type contextKey int

const (
	recorderKey  contextKey = 1
	requestIDKey contextKey = 2
)

// Recorder accumulates one canonical AI request completion event.
// Metadata (provider/tokens/retries) may be set after a failure is recorded.
type Recorder struct {
	mu               sync.Mutex
	operation        string
	outcome          string
	failureStage     string
	errorCode        string
	failureClass     string
	retryability     string
	provider         string
	model            string
	providerStatus   string
	schemaStage      string
	promptTokens     *int
	completionTokens *int
	totalTokens      *int
	retryCount       *int
	terminal         bool
}

func NewRecorder() *Recorder {
	return &Recorder{retryCount: Int(0)}
}

func WithRecorder(ctx context.Context, rec *Recorder) context.Context {
	return context.WithValue(ctx, recorderKey, rec)
}

func FromContext(ctx context.Context) *Recorder {
	rec, _ := ctx.Value(recorderKey).(*Recorder)
	return rec
}

func WithRequestID(ctx context.Context, requestID string) context.Context {
	return context.WithValue(ctx, requestIDKey, requestID)
}

func RequestIDFromContext(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey).(string)
	return id
}

func (r *Recorder) SetOperation(operation string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if op := SanitizeOperation(operation); op != "" {
		r.operation = op
	}
}

func (r *Recorder) SetProvider(provider, model string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if provider != "" {
		r.provider = SanitizeProvider(provider)
	}
	if model != "" {
		r.model = SanitizeModel(model)
	}
}

func (r *Recorder) SetProviderStatus(status string) {
	if r == nil || status == "" {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.providerStatus = status
}

func (r *Recorder) SetSchemaStage(stage string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.schemaStage = SanitizeSchemaStage(stage)
}

func (r *Recorder) SetRetryCount(retryCount int) {
	if r == nil {
		return
	}
	if retryCount < 0 {
		retryCount = 0
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.retryCount = Int(retryCount)
}

func (r *Recorder) SetTokens(prompt, completion, total *int) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if prompt != nil {
		r.promptTokens = prompt
	}
	if completion != nil {
		r.completionTokens = completion
	}
	if total != nil {
		r.totalTokens = total
	}
}

func (r *Recorder) Success() {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.terminal {
		return
	}
	r.outcome = OutcomeSuccess
	r.failureStage = ""
	r.errorCode = ""
	r.failureClass = ""
	r.retryability = ""
	r.schemaStage = ""
	r.terminal = true
}

func (r *Recorder) Fail(class Classification) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.terminal {
		return
	}
	r.outcome = OutcomeFailed
	r.failureStage = class.Stage
	r.errorCode = class.ErrorCode
	r.failureClass = class.FailureClass
	r.retryability = class.Retryability
	r.terminal = true
}

func (r *Recorder) HasOutcome() bool {
	if r == nil {
		return false
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.outcome != ""
}

func (r *Recorder) Snapshot() (operation, outcome, failureStage, errorCode, failureClass, retryability, provider, model, providerStatus, schemaStage string, prompt, completion, total, retry *int) {
	if r == nil {
		return "", "", "", "", "", "", "", "", "", "", nil, nil, nil, Int(0)
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	retryCount := r.retryCount
	if retryCount == nil {
		retryCount = Int(0)
	}
	return r.operation, r.outcome, r.failureStage, r.errorCode, r.failureClass, r.retryability,
		r.provider, r.model, r.providerStatus, r.schemaStage,
		r.promptTokens, r.completionTokens, r.totalTokens, retryCount
}
