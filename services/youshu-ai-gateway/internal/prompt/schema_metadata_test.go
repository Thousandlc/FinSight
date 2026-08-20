package prompt_test

import (
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func TestDescribeKeyFactValueSchemaCaseCMetadata(t *testing.T) {
	caseC := smoke.AllCases()[2].Envelope.MonthlySummaryFacts
	base, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	bound, err := prompt.BuildAssistantAnswerSchema(base, factpack.BuildKeySets(caseC), prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	meta, err := prompt.DescribeKeyFactValueSchema(bound)
	if err != nil {
		t.Fatal(err)
	}
	if meta.SchemaMode != prompt.KeyFactValueSchemaModeApplicationMaterialized {
		t.Fatalf("mode=%q", meta.SchemaMode)
	}
	summary := meta.Summary()
	if !strings.Contains(summary, "applicationMaterialized") {
		t.Fatalf("summary=%s", summary)
	}
}
