#!/usr/bin/env bash
set -euo pipefail

# ECS localhost smoke (P0-5B1A). No Bailian calls. Run on ECS after service start.

BASE_URL="${1:-http://127.0.0.1:8080}"

echo "== GET /health =="
curl -sS -o /tmp/gw-health.json -w "HTTP %{http_code}\n" "${BASE_URL}/health"
cat /tmp/gw-health.json
echo

echo "== GET /ready =="
curl -sS -o /tmp/gw-ready.json -w "HTTP %{http_code}\n" "${BASE_URL}/ready"
cat /tmp/gw-ready.json
echo

echo "== POST unauthorized =="
curl -sS -o /tmp/gw-unauth.json -w "HTTP %{http_code}\n" \
  -X POST "${BASE_URL}/v1/ai/financial-assistant" \
  -H "Content-Type: application/json" \
  -d '{"schemaVersion":"v1","requestId":"00000000-0000-4000-8000-000000000001","operation":"monthlySummary","assistantRequest":{"context":{"meta":{"asOf":"2026-08-18"}}}}'
cat /tmp/gw-unauth.json
echo

echo "smoke-localhost complete (no authenticated Bailian request)"
