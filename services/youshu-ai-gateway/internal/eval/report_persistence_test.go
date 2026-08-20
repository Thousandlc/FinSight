package eval_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/eval"
)

func TestResolveOutputDirUsesModuleRootNotPackageWD(t *testing.T) {
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(filepath.ToSlash(wd), "internal/eval") {
		t.Skip("run from internal/eval package wd to reproduce go test cwd")
	}
	dir, err := eval.ResolveOutputDir(eval.DefaultOutputDir)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(filepath.ToSlash(dir), "/internal/eval/.eval-output") {
		t.Fatalf("canonical dir must not be package-relative: %s", dir)
	}
	if !strings.HasSuffix(filepath.ToSlash(dir), "/youshu-ai-gateway/.eval-output") {
		t.Fatalf("unexpected canonical dir: %s", dir)
	}
}

func TestWriteReportTimestampedImmutableAfterLatestUpdate(t *testing.T) {
	dir := t.TempDir()
	report := samplePersistedReport(t)
	writeResult, err := eval.WriteReport(report, dir)
	if err != nil {
		t.Fatal(err)
	}
	if writeResult.TimestampedPath == "" || writeResult.LatestPath == "" {
		t.Fatal("expected both timestamped and latest paths")
	}
	tsBefore, err := os.ReadFile(writeResult.TimestampedPath)
	if err != nil {
		t.Fatal(err)
	}

	report2 := samplePersistedReport(t)
	report2.Metadata.FinishedAt = "2099-01-01T00:00:00Z"
	writeResult2, err := eval.WriteReport(report2, dir)
	if err != nil {
		t.Fatal(err)
	}
	if writeResult2.TimestampedPath == writeResult.TimestampedPath {
		t.Fatal("second write should create a new timestamped artifact")
	}

	tsAfter, err := os.ReadFile(writeResult.TimestampedPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(tsBefore, tsAfter) {
		t.Fatal("timestamped artifact content changed after later latest update")
	}
}

func TestWriteReportPersistsAfterFunctionReturn(t *testing.T) {
	dir := t.TempDir()
	report := samplePersistedReport(t)
	writeResult, err := eval.WriteReport(report, dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(writeResult.TimestampedPath); err != nil {
		t.Fatalf("timestamped missing after return: %v", err)
	}
	if _, err := os.Stat(writeResult.LatestPath); err != nil {
		t.Fatalf("latest missing after return: %v", err)
	}
}

func TestWriteReportDecodeRoundTripIdentity(t *testing.T) {
	dir := t.TempDir()
	report := samplePersistedReport(t)
	writeResult, err := eval.WriteReport(report, dir)
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(writeResult.TimestampedPath)
	if err != nil {
		t.Fatal(err)
	}
	var decoded eval.EvaluationReport
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.EvaluatorVersion != eval.EvaluatorVersionPostC2CB {
		t.Fatalf("evaluatorVersion=%q", decoded.EvaluatorVersion)
	}
	if decoded.RunPlan.Type != eval.RunPlanTypeFull {
		t.Fatalf("runPlan.type=%q", decoded.RunPlan.Type)
	}
	if len(decoded.Results) != 37 {
		t.Fatalf("results=%d want 37", len(decoded.Results))
	}
}

func TestWriteReportLatestFailurePreservesTimestamped(t *testing.T) {
	base := t.TempDir()
	report := samplePersistedReport(t)
	writeResult, err := eval.WriteReport(report, base)
	if err != nil {
		t.Fatal(err)
	}
	tsData, err := os.ReadFile(writeResult.TimestampedPath)
	if err != nil {
		t.Fatal(err)
	}

	if err := os.Chmod(writeResult.LatestPath, 0o444); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(writeResult.LatestPath, 0o644) })

	report2 := samplePersistedReport(t)
	report2.Metadata.FinishedAt = "2099-01-01T00:00:00Z"
	_, err = eval.WriteReport(report2, base)
	if err == nil {
		t.Fatal("expected latest write failure")
	}

	still, err := os.ReadFile(writeResult.TimestampedPath)
	if err != nil {
		t.Fatalf("timestamped removed on latest failure: %v", err)
	}
	if !bytes.Equal(tsData, still) {
		t.Fatal("timestamped content changed on latest failure")
	}
}

func TestC2DAPrimaryArtifactRecovery(t *testing.T) {
	legacyPath := filepath.Join(".eval-output", "full-v2-20260817-082419.json")
	if _, err := os.Stat(legacyPath); err != nil {
		t.Skip("primary C2D artifact not present at legacy package path")
	}
	legacyData, err := os.ReadFile(legacyPath)
	if err != nil {
		t.Fatal(err)
	}
	var legacy eval.EvaluationReport
	if err := json.Unmarshal(legacyData, &legacy); err != nil {
		t.Fatal(err)
	}
	if legacy.Metadata.StartedAt != "2026-08-17T08:18:01Z" {
		t.Fatalf("unexpected batch start: %s", legacy.Metadata.StartedAt)
	}
	if legacy.Metrics.EndToEndSuccessCount != 37 || len(legacy.Results) != 37 {
		t.Fatalf("unexpected completeness: e2e=%d runs=%d", legacy.Metrics.EndToEndSuccessCount, len(legacy.Results))
	}
	if legacy.EvaluatorVersion != eval.EvaluatorVersionPostC2CB {
		t.Fatalf("evaluatorVersion=%q", legacy.EvaluatorVersion)
	}

	canonicalDir, err := eval.ResolveOutputDir(eval.DefaultOutputDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(canonicalDir, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(canonicalDir, "full-v2-20260817-082419.json")
	if err := os.WriteFile(target, legacyData, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(canonicalDir, eval.LatestReportFile), legacyData, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Logf("recovered primary artifact to %s", target)
}

func samplePersistedReport(t *testing.T) eval.EvaluationReport {
	t.Helper()
	results := make([]eval.RunResult, 37)
	for i := range results {
		results[i] = eval.RunResult{CaseID: "A01_healthy_cashflow", RunIndex: 1, EndToEndPass: true}
	}
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 29, TotalRuns: 37, StartedAt: "2026-01-01T00:00:00Z", FinishedAt: "2026-01-01T00:01:00Z"},
		results,
		eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	report.RunPlan = eval.EvaluationRunPlan{Type: eval.RunPlanTypeFull, ArtifactPrefix: "full-v2", ExpectedCaseCount: 29, ExpectedRunCount: 37}
	report.RunStatus = eval.RunStatusExecuted
	return report
}
