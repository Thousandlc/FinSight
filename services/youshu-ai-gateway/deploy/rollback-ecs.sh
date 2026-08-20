#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="finsight-ai-gateway"
CURRENT_LINK="/opt/finsight-ai-gateway/current"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "usage: sudo ./rollback-ecs.sh <release-version>" >&2
  echo "available releases:" >&2
  ls -1 /opt/finsight-ai-gateway/releases >&2 || true
  exit 1
fi

RELEASE="/opt/finsight-ai-gateway/releases/${TARGET}"
if [[ ! -x "${RELEASE}/finsight-ai-gateway" ]]; then
  echo "release not found: ${RELEASE}" >&2
  exit 1
fi

ln -sfn "$RELEASE" "$CURRENT_LINK"
systemctl restart "$SERVICE_NAME"
echo "rolled back to ${TARGET}"
