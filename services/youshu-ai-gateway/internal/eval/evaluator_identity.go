package eval

const (
	// EvaluatorVersionPostC2CB identifies post-C2C-B citation/keyFact scope hygiene.
	EvaluatorVersionPostC2CB = "post-c2cb"
	// EvaluatorFingerprintPostC2CB fingerprints the split forbidden-scope evaluator contract.
	EvaluatorFingerprintPostC2CB = "c2cb-forbidden-scope-v1"
)

// EvaluatorIdentity records evaluator semantics version for replay artifacts.
type EvaluatorIdentity struct {
	EvaluatorVersion     string `json:"evaluatorVersion"`
	EvaluatorFingerprint string `json:"evaluatorFingerprint"`
}

// CurrentEvaluatorIdentity returns the active evaluator identity.
func CurrentEvaluatorIdentity() EvaluatorIdentity {
	return EvaluatorIdentity{
		EvaluatorVersion:     EvaluatorVersionPostC2CB,
		EvaluatorFingerprint: EvaluatorFingerprintPostC2CB,
	}
}
