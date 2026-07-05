#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARTIFACT_DIR="${REGRESSION_ARTIFACT_DIR:-$ROOT_DIR/build/regression/ios-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$ARTIFACT_DIR"

PROJECT="AI 記帳.xcodeproj"
APP_SCHEME="AI 記帳"
UI_SCHEME="AI 記帳 UI Automation"
APP_BUNDLE_ID="org.duckdns.lhfser.AIMoney"
UI_RUNNER_BUNDLE_ID="org.duckdns.lhfser.AIMoneyUITests.xctrunner"
SIMULATOR_ID="${IOS_SIMULATOR_ID:-$(python3 scripts/select-ios-simulator.py)}"

echo "Artifacts: $ARTIFACT_DIR"
echo "Simulator: $SIMULATOR_ID"

run_logged() {
  local name="$1"
  shift
  echo "==> $name"
  "$@" 2>&1 | tee "$ARTIFACT_DIR/$name.log"
  local status=${PIPESTATUS[0]}
  if [[ $status -ne 0 ]]; then
    echo "Command failed: $name (exit $status)" >&2
    return "$status"
  fi
}

cleanup_ui_runner() {
  xcrun simctl terminate "$SIMULATOR_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl terminate "$SIMULATOR_ID" "$UI_RUNNER_BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$SIMULATOR_ID" "$UI_RUNNER_BUNDLE_ID" >/dev/null 2>&1 || true
}

run_logged docs python3 scripts/check-docs.py
run_logged money-fixtures python3 scripts/check-money-fixtures.py

run_logged ios-build \
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$APP_SCHEME" \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    CODE_SIGNING_ALLOWED=NO \
    build

run_logged ios-unit \
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$APP_SCHEME" \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -resultBundlePath "$ARTIFACT_DIR/ios-unit.xcresult" \
    CODE_SIGNING_ALLOWED=NO \
    test

run_ui_once() {
  local label="$1"
  cleanup_ui_runner
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$UI_SCHEME" \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -only-testing:"AI 記帳UITests/AdvanceStructuralEditingUITests" \
    -resultBundlePath "$ARTIFACT_DIR/$label.xcresult" \
    test 2>&1 | tee "$ARTIFACT_DIR/$label.log"
  return "${PIPESTATUS[0]}"
}

echo "==> ios-ui"
set +e
run_ui_once ios-ui
ui_status=$?
set -e

if [[ $ui_status -ne 0 ]] && grep -Eq "Application failed preflight checks|SBMainWorkspace.*Busy|xctrunner" "$ARTIFACT_DIR/ios-ui.log"; then
  echo "iOS UI runner launch looked environment-blocked; retrying once after cleanup."
  sleep 10
  set +e
  run_ui_once ios-ui-retry
  retry_status=$?
  set -e
  if [[ $retry_status -ne 0 ]] && grep -Eq "Application failed preflight checks|SBMainWorkspace.*Busy|xctrunner" "$ARTIFACT_DIR/ios-ui-retry.log"; then
    echo "iOS UI automation environment-blocked after retry. See $ARTIFACT_DIR/ios-ui-retry.log" >&2
    exit 69
  fi
  exit "$retry_status"
fi

exit "$ui_status"
