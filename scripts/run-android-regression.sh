#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="${ADB:-$SDK_ROOT/platform-tools/adb}"
EMULATOR="${EMULATOR:-$SDK_ROOT/emulator/emulator}"
AVD_NAME="${ANDROID_AVD_NAME:-Medium_Phone_API_36.1}"
ARTIFACT_DIR="${REGRESSION_ARTIFACT_DIR:-$ROOT_DIR/build/regression/android-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$ARTIFACT_DIR"

cd "$ROOT_DIR"
echo "Artifacts: $ARTIFACT_DIR"

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

first_device() {
  "$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }'
}

wait_for_boot() {
  "$ADB" wait-for-device
  until [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    sleep 2
  done
}

started_emulator=0
cleanup() {
  if [[ "$started_emulator" == "1" ]]; then
    "$ADB" -s emulator-5554 emu kill >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

run_logged docs python3 scripts/check-docs.py
run_logged money-fixtures python3 scripts/check-money-fixtures.py

cd "$ANDROID_DIR"
run_logged android-unit-build ./gradlew :app:testDebugUnitTest :app:assembleDebug --no-daemon --console=plain --stacktrace

serial="$(first_device || true)"
if [[ -z "$serial" ]]; then
  if [[ "${START_ANDROID_EMULATOR:-0}" != "1" ]]; then
    echo "No Android device is connected. Re-run with START_ANDROID_EMULATOR=1 to launch AVD '$AVD_NAME'." >&2
    exit 69
  fi
  if [[ ! -x "$EMULATOR" ]]; then
    echo "Android emulator not found at $EMULATOR" >&2
    exit 69
  fi
  echo "==> start-emulator $AVD_NAME"
  "$EMULATOR" -avd "$AVD_NAME" -no-snapshot-load -no-audio -no-boot-anim >"$ARTIFACT_DIR/emulator.log" 2>&1 &
  started_emulator=1
  wait_for_boot
  serial="$(first_device || true)"
fi

if [[ -z "$serial" ]]; then
  echo "No Android device became available for instrumentation." >&2
  exit 69
fi

echo "Android device: $serial"
"$ADB" -s "$serial" logcat -c || true
run_logged android-instrumentation ./gradlew :app:connectedDebugAndroidTest --no-daemon --console=plain --stacktrace
"$ADB" -s "$serial" logcat -d > "$ARTIFACT_DIR/logcat-after-instrumentation.txt" || true
