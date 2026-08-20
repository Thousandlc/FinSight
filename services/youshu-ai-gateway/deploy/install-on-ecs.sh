#!/usr/bin/env bash
set -euo pipefail

# Installs or upgrades FinSight AI Gateway on Alibaba Cloud ECS (systemd + local bind).
# Run on ECS with sudo. Does NOT write secrets.

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: sudo ./install-on-ecs.sh <release-version>" >&2
  exit 1
fi

SERVICE_NAME="finsight-ai-gateway"
INSTALL_ROOT="/opt/finsight-ai-gateway"
ENV_DIR="/etc/finsight-ai-gateway"
ENV_FILE="${ENV_DIR}/production.env"
RELEASE_DIR="${INSTALL_ROOT}/releases/${VERSION}"
CURRENT_LINK="${INSTALL_ROOT}/current"
UNIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/finsight-ai-gateway.service"
UNIT_DST="/etc/systemd/system/${SERVICE_NAME}.service"
STAGING_BIN="/tmp/finsight-ai-gateway-${VERSION}"

if [[ ! -f "$STAGING_BIN" ]]; then
  echo "missing staged binary: $STAGING_BIN" >&2
  exit 1
fi

if ! id -u finsight >/dev/null 2>&1; then
  useradd --system --home-dir "$INSTALL_ROOT" --shell /usr/sbin/nologin finsight
fi

install -d -m 0755 -o root -g root "$INSTALL_ROOT" "${INSTALL_ROOT}/releases"
install -d -m 0750 -o root -g root "$ENV_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  install -m 0600 -o root -g root \
    "$(dirname "$UNIT_SRC")/production.env.template" "$ENV_FILE"
  echo "created $ENV_FILE — edit secrets before starting the service"
fi

chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

update_build_version() {
  local version="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v version="$version" '
    BEGIN { updated = 0 }
    /^BUILD_VERSION=/ {
      print "BUILD_VERSION=" version
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print "BUILD_VERSION=" version
      }
    }
  ' "$ENV_FILE" > "$tmp"
  install -m 0600 -o root -g root "$tmp" "$ENV_FILE"
  rm -f "$tmp"
}

update_build_version "$VERSION"

install -d -m 0755 -o root -g root "$RELEASE_DIR"
install -m 0755 -o root -g root "$STAGING_BIN" "${RELEASE_DIR}/finsight-ai-gateway"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

install -m 0644 "$UNIT_SRC" "$UNIT_DST"
install -m 0644 "$(dirname "$UNIT_SRC")/README-deploy.txt" "${INSTALL_ROOT}/README-deploy.txt" || true
chown root:root "${INSTALL_ROOT}/README-deploy.txt" || true

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

if systemctl is-active --quiet "$SERVICE_NAME"; then
  systemctl restart "$SERVICE_NAME"
else
  systemctl start "$SERVICE_NAME"
fi

echo "installed release ${VERSION}"
echo "verify: curl -sS http://127.0.0.1:8080/health"
