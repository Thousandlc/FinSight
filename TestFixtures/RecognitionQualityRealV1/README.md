# Private real Transaction Recognition corpus v1

This directory documents the private-corpus extension of the existing Recognition Quality harness. It contains no screenshots or ground truth.

Run an Apple Vision baseline from the repository root with a private directory outside Git:

```text
REAL_RECOGNITION_CORPUS=/private/corpus/directory
REAL_RECOGNITION_CANDIDATE_COMMIT=<40-character-commit>
swift test --filter RealTransactionRecognitionBaselineRunTests
```

The private directory must contain `manifest.json` plus the referenced image assets. Use opaque IDs and opaque asset filenames. The loader accepts only schema `RealTransactionRecognitionCorpusV1`, rejects duplicate/non-opaque IDs, path traversal, malformed labels, invalid amounts/dates, and missing assets, and computes a deterministic SHA-256 digest over canonical private labels plus ordered image fingerprints.

If `REAL_RECOGNITION_CORPUS` is absent, the runner prints exactly:

```text
REAL BASELINE CORPUS NOT AVAILABLE
```

Normal CI never substitutes synthetic or Mock fixtures for this run. Optional aggregate output can be written to a local ignored path with `REAL_RECOGNITION_REPORT`. The aggregate schema intentionally has no sample IDs, asset paths, raw OCR, ground-truth values, or recognized field values.

Official `ESTABLISHED` coverage requires at least 100 supported screenshots, 20 readable unsupported screenshots, 20 WeChat samples, 20 Alipay samples, 50 expense/payment samples, 10 income/received samples, and 10 refund samples. A smaller real corpus is `PROVISIONAL`; these requirements are not relaxed to obtain a pass.

`manifest.template.json` is an empty schema template only. Never add private entries to the tracked copy.
