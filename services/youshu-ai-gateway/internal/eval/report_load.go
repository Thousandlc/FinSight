package eval

import (
	"encoding/json"
	"fmt"
	"os"
)

// LoadReport reads an evaluation report from disk.
func LoadReport(path string) (EvaluationReport, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return EvaluationReport{}, fmt.Errorf("read report: %w", err)
	}
	var report EvaluationReport
	if err := json.Unmarshal(data, &report); err != nil {
		return EvaluationReport{}, fmt.Errorf("unmarshal report: %w", err)
	}
	return report, nil
}
