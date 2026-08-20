package provider



import (

	"encoding/json"

	"fmt"

	"time"



	"github.com/youshu/youshu-ai-gateway/internal/config"

	"github.com/youshu/youshu-ai-gateway/internal/prompt"

)



// NewUpstream selects MockUpstreamAIProvider or BailianProvider from gateway config.

func NewUpstream(cfg config.Config) (UpstreamAIProvider, error) {

	if err := cfg.ValidateUpstream(); err != nil {

		return nil, err

	}

	switch cfg.UpstreamAIProvider {

	case config.UpstreamMock:

		return NewMockUpstreamAIProvider(), nil

	case config.UpstreamBailian:

		mode := cfg.BailianStructuredOutputMode

		if mode == "" {

			mode = config.StructuredOutputJSONObject

		}

		var schema json.RawMessage

		if mode == config.StructuredOutputJSONSchemaStrict {

			loaded, err := prompt.LoadAssistantAnswerModelDraftSchema()

			if err != nil {

				return nil, err

			}

			schema = loaded

		}

		retry := DefaultRetryPolicy(cfg.UpstreamMaxRetries, cfg.RetryBaseDelayMS, cfg.RetryMaxDelayMS)

		return NewBailianProvider(BailianConfig{

			APIKey:               cfg.BailianAPIKey,

			BaseURL:              cfg.BailianBaseURL,

			Model:                cfg.BailianModel,

			Timeout:              time.Duration(cfg.BailianTimeoutSecond) * time.Second,

			StructuredOutputMode: mode,

			JSONSchema:           schema,

			RetryPolicy:          retry,

			Concurrency:          NewConcurrencyLimiter(cfg.UpstreamMaxConcurrency),

		}, nil), nil

	default:

		return nil, fmt.Errorf("unsupported upstream provider: %q", cfg.UpstreamAIProvider)

	}

}

