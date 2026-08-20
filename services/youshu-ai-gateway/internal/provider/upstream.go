package provider

import (
	"context"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// UpstreamAIProvider calls an upstream LLM. P0-4.2 uses MockUpstreamAIProvider only.
type UpstreamAIProvider interface {
	CompleteMonthlySummary(
		ctx context.Context,
		req contract.RequestEnvelope,
	) (contract.AssistantAnswerDraftDTO, error)
}
