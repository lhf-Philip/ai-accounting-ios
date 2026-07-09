#!/usr/bin/env bash

set +e

diagnostics_dir="app/build/reports/androidTests/diagnostics"
mkdir -p "$diagnostics_dir"

capture_diagnostics() {
  adb logcat -d > "$diagnostics_dir/logcat.txt" || true
  adb shell dumpsys activity activities > "$diagnostics_dir/activity.txt" || true
  adb shell dumpsys window > "$diagnostics_dir/window.txt" || true
  adb exec-out screencap -p > "$diagnostics_dir/failure.png" || true
  adb exec-out uiautomator dump /dev/tty > "$diagnostics_dir/uiautomator.xml" || true
}

settle_launcher() {
  adb shell settings put global device_provisioned 1 >/dev/null 2>&1 || true
  adb shell settings put secure user_setup_complete 1 >/dev/null 2>&1 || true
  adb shell settings put global setup_wizard_has_run 1 >/dev/null 2>&1 || true

  # Fresh Google API images can briefly foreground setup components after boot,
  # stealing focus from ActivityScenario-based instrumentation tests.
  for package_name in \
    com.google.android.googlesdksetup \
    com.google.android.setupwizard \
    com.android.provision
  do
    adb shell am force-stop "$package_name" >/dev/null 2>&1 || true
  done

  adb shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    if adb shell dumpsys activity activities 2>/dev/null \
      | grep -Eq "ResumedActivity:.*(launcher|Launcher|FallbackHome)"; then
      return 0
    fi
    sleep 1
  done
  echo "Launcher did not settle before instrumentation; continuing with diagnostics." >&2
  adb shell dumpsys activity activities > "$diagnostics_dir/activity-before-tests.txt" || true
  return 0
}

wait_for_emulator_ready() {
  adb wait-for-device
  boot_completed=""
  for _ in $(seq 1 90); do
    boot_completed="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [ "$boot_completed" = "1" ]; then
      break
    fi
    sleep 2
  done
  if [ "$boot_completed" != "1" ]; then
    echo "Android emulator did not report sys.boot_completed=1." >&2
    capture_diagnostics
    return 69
  fi

  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
  adb shell settings put global window_animation_scale 0 >/dev/null 2>&1 || true
  adb shell settings put global transition_animation_scale 0 >/dev/null 2>&1 || true
  adb shell settings put global animator_duration_scale 0 >/dev/null 2>&1 || true
  settle_launcher
  adb shell dumpsys activity activities > "$diagnostics_dir/activity-before-tests.txt" || true
  return 0
}

wait_for_emulator_ready
ready_status=$?
if [ "$ready_status" -ne 0 ]; then
  exit "$ready_status"
fi

./gradlew :app:connectedDebugAndroidTest --no-daemon --console=plain --stacktrace
test_status=$?

if [ "$test_status" -ne 0 ]; then
  capture_diagnostics
fi

exit "$test_status"
