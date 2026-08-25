# Private Real Transaction Recognition Corpus

This directory defines the only v1 operator interface for the private real-screenshot
baseline. Raw screenshots, populated manifests, split membership, and detailed
evaluation evidence stay outside Git. The committed template remains empty, so normal
CI reports `REAL BASELINE CORPUS NOT AVAILABLE` and never fabricates metrics.

## Candidate freeze

The first untouched baseline is frozen to recognition candidate
`0a039e98efff5562e9bbd518ae2e1ee0cd35ad9d`. Documentation-only commits may advance
the branch HEAD, but `REAL_RECOGNITION_CANDIDATE_COMMIT` must continue to name this
recognition implementation candidate for the initial run.

The frozen production identity is provider `apple-vision-transaction-v1` with engine
`vision-accurate-zh-Hans-en-US-v1`.

Before inspecting any sample-level failure, record the candidate commit, corpus
version, corpus digest, split membership, Apple/Xcode environment, and aggregate
report. Do not tune the parser or relabel samples before that record is complete.

## Private directory layout

Use an operator-controlled directory outside the repository:

```text
<PRIVATE_CORPUS_DIRECTORY>/
  manifest.json
  assets/
    rq-<LOWERCASE_HEX>.<IMAGE_EXTENSION>
```

The asset path in the manifest is relative to the corpus directory. It must resolve
to a non-empty file, and cannot be absolute, contain a drive prefix, or traverse with
`..`. Sample IDs must be `rq-` followed by 12 through 64 lowercase hexadecimal
characters. Filenames and IDs must remain opaque: never include merchant names,
amounts, user names, order numbers, account hints, or other financial details.

The repository-level `.recognition-quality-private/` ignore is a fail-safe only. The
primary control is keeping the entire populated corpus outside Git. Generated local
reports belong under ignored `.eval-output/` unless they have been privacy-reviewed.

## Manifest contract

Start from `manifest.template.json` and keep the schema version exactly
`RealTransactionRecognitionCorpusV1`. The top-level fields are:

- `schemaVersion`: the exact schema version above;
- `corpusVersion`: an operator-assigned opaque frozen version;
- `timeZone`: the IANA time zone used to interpret private date labels;
- `samples`: the private sample array.

Each sample contains `id`, `asset`, `sourceKind`, `platform`, `family`,
`screenshotQualities`, `expectedOutcome`, and optionally `transaction`.

Accepted labels are:

- `sourceKind`: `privateRealScreenshot` or `privateRepresentativeScreenshot`;
- `platform`: `weChat`, `alipay`, or `other`;
- `family`: `expensePayment`, `incomeReceived`, `refund`, `transfer`,
  `readableUnsupported`, or `unreadable`;
- `screenshotQualities`: a non-empty array drawn from `fullScreenshot`, `crop`,
  `light`, `dark`, and `other`;
- `expectedOutcome`: `recognized`, `unsupported`, or `unreadable`.

The outcome contract is strict. A `recognized` sample requires `transaction` and a
non-negative family. `unsupported` requires no transaction and family
`readableUnsupported`. `unreadable` requires no transaction and family `unreadable`.

Private transaction labels are `amount`, `direction`, `occurredAt`,
`occurredAtPrecision`, `merchant`, `paymentAccountHint`, and `category`. Every
optional fact uses one of these shapes:

```text
{ "presence": "unknown" }
{ "presence": "known", "value": <PRIVATE_VALUE> }
```

Amounts must be positive decimals. Direction uses a repository `TransactionType`
raw value: `expense`, `income`, `transfer`, `refund`, `reimbursement`, `borrowing`,
`repayment`, `investmentBuy`, `investmentSell`. Labels must describe the visible
transaction and the v1 recognition semantics; do not invent a label merely to fill a
field.

For an unknown date, omit `occurredAtPrecision`. A known date requires precision
`day` with `YYYY-MM-DD`, or `minute` with `YYYY-MM-DDTHH:mm`; the corpus time zone is
used for interpretation.

## Collection and coverage plan

Collect independently sourced real or representative private screenshots. Preserve
their original pixels except for privacy handling performed before inclusion, and do
not create duplicate samples solely to meet a count. Cover both platforms, supported
transaction families, readable unsupported layouts, unreadable inputs, full and
cropped screenshots, light and dark appearances, and varied amount/date/layout
presentations.

One frozen corpus is `ESTABLISHED` only when it contains all of:

- at least 100 supported transaction screenshots;
- at least 20 readable-unsupported negative screenshots;
- at least 20 WeChat screenshots and 20 Alipay screenshots;
- at least 50 expense, 10 income, and 10 refund screenshots.

A smaller non-empty corpus is `PROVISIONAL`; thresholds are never lowered. Record
gaps explicitly and continue collection rather than padding a category.

## Development and validation split

The schema intentionally has no split field. Represent the split with separately
versioned private manifests/directories outside Git, without changing the schema.

Freeze membership before viewing recognition output. Within private strata formed by
platform, family, and expected outcome, sort opaque IDs and assign every fifth sample
to validation and the remainder to development. For a rare stratum with fewer than
five samples, predeclare at least one validation member and record that exception in
private operator notes. Aim for at least 20% validation while preserving negative and
supported-family coverage in both partitions.

The initial untouched aggregate may be measured over the full frozen corpus. After
that, inspect and iterate only against the development partition. Keep validation
assets and detailed results sealed until a new candidate is frozen, then run validation
once. Never overwrite the original baseline report or silently move samples between
partitions.

## Validation and baseline run

Run on an Apple host where the Vision-backed recognizer is available. Prepare the
ignored report directory first because the runner does not create its parent:

```sh
mkdir -p .eval-output/recognition-quality-real
export REAL_RECOGNITION_CORPUS="<PRIVATE_CORPUS_DIRECTORY>"
export REAL_RECOGNITION_CANDIDATE_COMMIT="0a039e98efff5562e9bbd518ae2e1ee0cd35ad9d"
export REAL_RECOGNITION_ENVIRONMENT="<GENERIC_APPLE_ENVIRONMENT_LABEL>"
export REAL_RECOGNITION_REPORT=".eval-output/recognition-quality-real/aggregate.json"
swift test --filter RealTransactionRecognitionBaselineRunTests
```

The configured run loads and validates the private manifest, path safety, assets,
enum values, outcome contract, and ground-truth representation before recognition.
There is no separate command that validates a populated private manifest without
running the baseline. `swift test --filter RealTransactionRecognitionCorpusLoaderTests`
tests the loader contract itself, not the contents of an operator's private corpus.

If `REAL_RECOGNITION_CORPUS` is absent, the runner prints
`REAL BASELINE CORPUS NOT AVAILABLE` and succeeds. A configured private corpus on a
non-Apple host is an error rather than a synthetic baseline.

## Digest, reports, and evidence boundary

After validation, samples are sorted by opaque ID. The corpus digest is SHA-256 over
canonical schema/version/time-zone data, private labels, sorted quality labels, and
the SHA-256 fingerprint of every referenced image's full bytes. Asset filenames are
not part of the canonical object. Any pixel or label change therefore creates a new
digest, while moving an unchanged asset does not.

The runner prints aggregate JSON and atomically writes the same report when
`REAL_RECOGNITION_REPORT` is set. Aggregate reports omit sample IDs, filenames, OCR
text, and ground-truth values. The optional environment label is operator supplied,
so keep it generic and free of machine or user names. Privacy-review every aggregate
artifact before committing it.

Populated manifests, screenshots, split membership, individual predictions,
failure images, OCR text, and sample-level comparisons are private evidence. Keep
them outside Git and outside ordinary CI artifacts. The aggregate report, frozen
candidate commit, corpus version, digest, environment class, and pass/fail metrics are
the shareable evidence boundary after review.
