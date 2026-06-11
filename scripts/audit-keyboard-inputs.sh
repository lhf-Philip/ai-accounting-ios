#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

echo "iOS files with input controls but no standard keyboard exit:"
while IFS= read -r file; do
    if ! rg -q \
        'standardKeyboardBehavior|keyboardDoneToolbar|ToolbarItemGroup\(placement: \.keyboard\)' \
        "$file"; then
        echo "  $file"
        status=1
    fi
done < <(
    rg -l 'TextField\(|TextEditor\(|SecureField\(|\.searchable\(' \
        'AI 記帳' --glob '*.swift' | sort
)

echo "Android input screens without IME avoidance:"
while IFS= read -r file; do
    if [[ "$file" == *"/ui/components/"* ]]; then
        continue
    fi
    if ! rg -q 'imePadding\(' "$file"; then
        echo "  $file"
        status=1
    fi
done < <(
    rg -l 'OutlinedTextField\(|BasicTextField\(|TextField\(' \
        android/app/src/main/java --glob '*.kt' | sort
)

echo "Android input screens without a Done/focus-clear action:"
while IFS= read -r file; do
    if [[ "$file" == *"/ui/components/"* ]]; then
        continue
    fi
    if ! rg -q 'keyboardDoneActions|clearFocus\(|ImeAction\.Done' "$file"; then
        echo "  $file"
        status=1
    fi
done < <(
    rg -l 'OutlinedTextField\(|BasicTextField\(|TextField\(' \
        android/app/src/main/java --glob '*.kt' | sort
)

exit "$status"
