# Recognition Quality Corpus v1

Offline evaluation fixtures for Transaction screenshot recognition and Debt screenshot recognition.

## What this is

A versioned, privacy-safe **evaluation contract and fixture harness**.

```text
Fixture Corpus + Ground Truth
        ↓
Recognizer Observation
        ↓
Deterministic Evaluator
        ↓
Machine-readable Quality Report
```

It exists so a future pixel-reading recognizer can be scored without changing evaluation semantics.

## What this is not

- Not a measured production recognition-quality baseline
- Not OCR / Vision / Bailian / Gateway image-recognition
- Not a release threshold (no 90% / 95% gates)
- Not production observability, consent, or financial persistence

The committed PNG assets are **minimal synthetic placeholders**. They prove the corpus references real file bytes. They do **not** validate OCR quality.

## Source / privacy

Every committed v1 fixture must be:

```text
sourceKind = synthetic | explicitly-deidentified-test-fixture
containsRealUserData = false
```

Do not add actual user screenshots. The loader rejects `containsRealUserData = true` for the committed corpus.

Use fixture-local IDs only. Never use production financial UUIDs.

## How to add a fixture

1. Add a synthetic PNG (or other bytes) under `assets/`. Fictional labels only.
2. Add an entry to `corpus.json` with a unique `id`.
3. Encode every scored field as either `{ "presence": "known", "value": ... }` or `{ "presence": "unknown" }`.
4. For money, store canonical decimal **strings** (`"2300.00"`), not formatted currency text.
5. For dates, store `YYYY-MM-DD`. Comparison precision is corpus-level `day` in `UTC`.
6. Run `YoushuAITests` Recognition Quality suites.

## Scored fields

**Transaction:** amount, currency, transaction type, date, merchant, category.

Suggested account is not scored.

**Debt (per matched candidate):** lender, product name, debt type, outstanding balance, current due, minimum due, installment amount, due date, interest rate.

`currentDue` is never treated as `outstandingBalance`.

## Unknown / invented

| Expected | Observed | Outcome |
| -------- | -------- | ------- |
| known, same | value | correct |
| known | nil | missing |
| known, different | value | incorrect |
| unknown | nil | correctlyUnknown |
| unknown | value | invented |

Invented fields fail whole-record exactness. Guessing unknown fields cannot improve the score.

## Debt candidate matching (v1)

Order-independent. Does not use Provider order or production UUID.

Match key = normalized known `lender` + `productName` + `debtType`.

Same-key leftovers pair by a lexicographic tie-break of canonical money/date encodings.

Unmatched expected = missed candidate. Unmatched observed = extra candidate.

Keep fixture match keys unique unless you are deliberately testing same-key pairing.

## How to run

From the repository root, after Windows Swift env is set:

```text
swift test --filter RecognitionQuality
```

Or the full Windows gate:

```text
scripts/test-windows.bat
```

## MockAIProvider

A Mock integration run may prove:

```text
fixture loading works
adapter works
evaluator works
report generation works
```

It is **not baseline eligible**:

```text
baselineEligible = false
reasons: mockRecognizer, recognizerDoesNotInspectPixels
```

Mock scores are **not** a real recognition accuracy baseline. Mock does not inspect image pixels.
