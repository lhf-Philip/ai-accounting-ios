#!/usr/bin/env bash

set +e

./gradlew :app:connectedDebugAndroidTest --no-daemon --console=plain --stacktrace
test_status=$?

if [ "$test_status" -ne 0 ]; then
  mkdir -p app/build/reports/androidTests/diagnostics
  adb logcat -d > app/build/reports/androidTests/diagnostics/logcat.txt || true
  adb exec-out screencap -p > app/build/reports/androidTests/diagnostics/failure.png || true
fi

exit "$test_status"
