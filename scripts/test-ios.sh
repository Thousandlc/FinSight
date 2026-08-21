#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null; then
  echo "Install XcodeGen: brew install xcodegen"
  exit 1
fi

xcodegen generate

DESTINATION="$(
  xcodebuild \
    -project Youshu.xcodeproj \
    -scheme Youshu \
    -showdestinations 2>/dev/null \
    | awk -F'[ ,]' '/platform:iOS Simulator/ && /OS:/ && /name:/ {print; exit}' \
    | sed -n 's/.*id:\([^,]*\).*/platform=iOS Simulator,id=\1/p'
)"

if [[ -z "${DESTINATION}" ]]; then
  echo "No available iOS Simulator destination found."
  xcodebuild -project Youshu.xcodeproj -scheme Youshu -showdestinations
  exit 1
fi

echo "Using destination: ${DESTINATION}"

XCODEBUILD_EXTRA=()
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  XCODEBUILD_EXTRA=(-quiet)
fi

xcodebuild \
  -project Youshu.xcodeproj \
  -scheme Youshu \
  -destination "${DESTINATION}" \
  "${XCODEBUILD_EXTRA[@]}" \
  test

echo "iOS build and Youshu scheme tests succeeded."
