# FinSight AI Gateway

Stateless HTTP gateway for FinSight Financial Assistant.

## Environment modes

| `YOUSHU_ENV` | Behavior |
|---|---|
| `development` (default) | `UPSTREAM_AI_PROVIDER` may default to `mock` |
| `test` | Same as development for automated tests |
| `production` | **Must** set `UPSTREAM_AI_PROVIDER=bailian`, Bailian credentials, and `GATEWAY_CLIENT_TOKEN`. Mock and `YOUSHU_SMOKE_DUMP_RAW` are rejected at startup. |

## Upstream providers

| `UPSTREAM_AI_PROVIDER` | Description |
|---|---|
| `mock` (development/test default) | Local structured JSON from request facts |
| `bailian` (production required) | Alibaba Cloud Model Studio (OpenAI-compatible Chat Completions) |
When `UPSTREAM_AI_PROVIDER=bailian`, set:

- `BAILIAN_API_KEY`
- `BAILIAN_BASE_URL` (region endpoint, e.g. `https://dashscope.aliyuncs.com/compatible-mode/v1`)
- `BAILIAN_MODEL` (e.g. `qwen-plus`; experiment may use `qwen3.7-plus`)
- `BAILIAN_TIMEOUT_SECONDS` (optional, default 25)
- `BAILIAN_STRUCTURED_OUTPUT_MODE` (`json_object` default, or `json_schema_strict` experiment)

Default production behavior remains `json_object`. Do not change the default until the experiment is accepted.

Gateway does **not** fallback to mock when Bailian fails.

## Health & readiness

| Endpoint | Purpose |
|---|---|
| `GET /health` | Process liveness (`status=ok`). Does not call Bailian. |
| `GET /ready` | Configuration readiness (provider credentials loaded). Does not call Bailian. |

Health/readiness bypass the AI inbound rate limiter.

## Production deployment (P0-5B)

Deploy behind HTTPS (managed reverse proxy recommended). The Go process listens on `PORT` (default `8080`) over plain HTTP.

Set `BIND_ADDR=127.0.0.1` when the gateway must not accept public connections (ECS internal phase / Nginx reverse proxy).

**Required env (production):**

- `YOUSHU_ENV=production`
- `UPSTREAM_AI_PROVIDER=bailian`
- `BAILIAN_API_KEY`, `BAILIAN_BASE_URL`, `BAILIAN_MODEL`
- `GATEWAY_CLIENT_TOKEN`
- `BUILD_VERSION` (optional metadata)
- `BIND_ADDR=127.0.0.1` (recommended on ECS until public HTTPS is enabled)

**Reliability tunables:** see `.env.example` (`UPSTREAM_MAX_RETRIES`, `UPSTREAM_MAX_CONCURRENCY`, `RATE_LIMIT_REQUESTS`, `RATE_LIMIT_WINDOW_SECONDS`, HTTP timeouts).

## ECS internal deployment (P0-5B1A)

ICP pending: Gateway runs on ECS **localhost only**. No public `:8080`, no DNS go-live, no live Bailian smoke in this phase.

| Path | Purpose |
|---|---|
| `/opt/finsight-ai-gateway/current/finsight-ai-gateway` | Active binary (symlink, root-managed) |
| `/opt/finsight-ai-gateway/releases/<version>/` | Versioned releases / rollback (`root:root`) |
| `/etc/finsight-ai-gateway/production.env` | Production env (`root:root`, `chmod 600`, secrets injected manually) |
| `deploy/finsight-ai-gateway.service` | systemd unit (`User=finsight`) |

**Deploy from Windows (OpenSSH):**

```powershell
# Recommended: configure ~/.ssh/config Host finsight-ecs (see deploy/ssh-config.snippet)
.\scripts\deploy-ecs.ps1 -SshAlias finsight-ecs -GoArch amd64

# Or explicit host:
.\scripts\deploy-ecs.ps1 -EcsHost <ecs-host> -GoArch amd64
```

Then on ECS, edit `/etc/finsight-ai-gateway/production.env` (never commit secrets), restart, and run:

```bash
bash /tmp/smoke-localhost.sh
journalctl -u finsight-ai-gateway -f
```

**SSH tunnel (dev machine health check):**

```bash
ssh -L 18080:127.0.0.1:8080 finsight-ecs
curl http://127.0.0.1:18080/health
```

**Rollback:**

```bash
sudo ./deploy/rollback-ecs.sh <previous-version>
```

**Nginx HTTPS template (enable after ICP — P0-5B1B):** `deploy/nginx-api.conf.template`

See `deploy/README-deploy.txt` for paths, logs, and security notes.

**Docker:**

```bash
docker build -t youshu-ai-gateway .
docker run --rm -p 8080:8080 --env-file .env youshu-ai-gateway
```

Production image runs as non-root user and excludes eval artifacts.

**Post-deploy smoke (manual, not run in CI here):**

1. `GET /health` → 200
2. `GET /ready` → 200
3. One authenticated `POST /v1/ai/financial-assistant` monthlySummary against live Bailian

## Run locally
```bash
cd services/youshu-ai-gateway
go run ./cmd/server
```

Optional `.env` values — see `.env.example`.

## Endpoint

`POST /v1/ai/financial-assistant`

Supported operation: `monthlySummary` only.

### Request contract (`schemaVersion: v1`)

| Field | Required when | Notes |
|---|---|---|
| `schemaVersion` | always | Must be `v1` |
| `requestId` | always | Client-generated correlation id |
| `operation` | always | `monthlySummary` only (other operations rejected) |
| `assistantRequest` | always | Financial context DTO (includes `meta.asOf`) |
| `monthlySummaryFacts` | `monthlySummary` | Registered fact pack for summary |
| `financialRiskAssessment` | `monthlySummary` | **Required** deterministic risk transport from iOS Domain |

`financialRiskAssessment` includes explicit `debtDataState` (`knownNoDebt|knownDebt|partial|missing`), policy `signals`, and `dataCompleteness`. Gateway validates structure and transport invariants only; it does **not** recompute risk policy.

`financialRiskAssessment.evaluatedAt` is **not** sent; assessment time lives in Domain audit only. Request date context uses `assistantRequest.context.meta.asOf`.

Non-`monthlySummary` requests must omit `financialRiskAssessment`.

**Version strategy:** Wire format remains `schemaVersion: v1`. Semantic contract for `monthlySummary` now requires `financialRiskAssessment`. Client and gateway are developed/deployed lockstep; no legacy client compatibility shim for missing assessment.

**Consent (iOS):** Remote transmission of financial context, monthly summary facts, and risk assessment is gated by `AIDataConsent.allowFinancialContextToAI` at the Domain service layer before any gateway request is serialized.

## Tests

```bash
go test ./...
```

P0-4.3D experiment (synthetic facts only):

```bash
BAILIAN_API_KEY=... BAILIAN_BASE_URL=... BAILIAN_MODEL=qwen3.7-plus BAILIAN_STRUCTURED_OUTPUT_MODE=json_schema_strict go test ./internal/smoke -run TestBailianLiveAcceptance -v
```

Never commit real API keys.

## P0-4.4 Evaluation Framework

Live evaluation is **explicit trigger only** — it does not run during `go test ./...`.

```bash
BAILIAN_API_KEY=... BAILIAN_BASE_URL=... BAILIAN_MODEL=qwen3.7-plus \
BAILIAN_STRUCTURED_OUTPUT_MODE=json_schema_strict \
go test ./internal/eval -run TestLiveEvaluation -v -count=1
```

Optional filters:

| Env var | Purpose |
|---|---|
| `YOUSHU_EVAL_CASE=<id>` | Run single case (e.g. `A01_healthy_cashflow`) |
| `YOUSHU_EVAL_CATEGORY=<category>` | Run category (e.g. `debt`) |
| `YOUSHU_EVAL_REPEAT=<n>` | Override repeat count |
| `YOUSHU_EVAL_PILOT=1` | Pilot mode (7 representative cases, 15 total runs) |

Report output: `.eval-output/latest.json` (gitignored).

Dataset: 29 synthetic scenarios across 6 categories, 37 total runs (4 core cases × 3 repeats + 25 × 1).

Full evaluation (no filter env vars):

```bash
BAILIAN_API_KEY=... BAILIAN_BASE_URL=... BAILIAN_MODEL=qwen3.7-plus \
BAILIAN_STRUCTURED_OUTPUT_MODE=json_schema_strict \
go test ./internal/eval -run TestLiveEvaluation -v -count=1
```

Pilot subset: 7 cases, 15 runs — A01×3, B01×3, C03×3, D02×1, E01_partial×3, E05_missing×1, F06×1.


Server-side prompts live under `prompts/financial-assistant/v1/`. iOS clients never receive system prompts. Structured JSON Schema lives in `assistant-answer-draft.schema.json`.

## Security notes

- Provider API keys belong on the server only.
- Logs must not include financial context JSON, prompts, or draft body.
- Bearer `GATEWAY_CLIENT_TOKEN` is optional for local dev; **required in production**.
- Inbound rate limit uses a fixed time window (`RATE_LIMIT_REQUESTS` / `RATE_LIMIT_WINDOW_SECONDS`).
- Gateway ingress 429 returns `gatewayRateLimited`; upstream Bailian 429 returns `providerRateLimited`.
- Structured logs include requestId, duration, provider attempts, token counts — never request bodies or financial context.