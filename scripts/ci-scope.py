#!/usr/bin/env python3
"""Select platform work; unknown paths run both platforms, invalid diffs fail CI."""

import json
import os
from pathlib import Path
import subprocess
import sys


def platforms(path):
    if path.startswith("docs/specs/"):
        return {"ios", "android"}
    if path.startswith("android/") or path in {
        ".github/workflows/android-ci.yml",
        ".github/scripts/run-android-instrumentation.sh",
        "scripts/run-android-regression.sh",
    }:
        return {"android"}
    if path.startswith(("AI 記帳/", "AI 記帳Tests/", "AI 記帳UITests/", "AI 記帳.xcodeproj/")) or path in {
        "Localizable.xcstrings", ".github/workflows/ios-ci.yml",
        "scripts/select-ios-simulator.py", "scripts/run-ios-regression.sh",
        "scripts/check-money-fixtures.py", "scripts/audit-keyboard-inputs.sh",
    }:
        return {"ios"}
    if path.startswith("docs/") or path in {
        "README.md", "README.zh-Hant.md", "SECURITY.md", "SECURITY.zh-Hant.md",
        "LICENSE", "AGENTS.md", "CONTEXT.md", "scripts/check-docs.py",
        ".github/workflows/docs-ci.yml",
    }:
        return set()
    return {"ios", "android"}


def changed_paths(event, git):
    if "pull_request" in event:
        base = event["pull_request"]["base"]["sha"]
        head = event["pull_request"]["head"]["sha"]
        base = git("merge-base", base, head).decode().strip()
    else:
        base, head = event["before"], event["after"]
        if not base.strip("0"):
            return None  # New branch: run everything.
    # Disabling rename detection includes both the old and new paths.
    data = git("diff", "--name-only", "--no-renames", "-z", base, head, "--")
    return data.decode().rstrip("\0").split("\0") if data else []


def main():
    platform = sys.argv[1]
    if platform not in {"ios", "android"}:
        raise ValueError("expected ios or android")
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    paths = changed_paths(event, lambda *args: subprocess.check_output(["git", *args]))
    selected = paths is None or any(platform in platforms(p) for p in paths)
    decision = f"run={str(selected).lower()}\n"
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(decision)
    summary = f"{platform}: {'run full build/tests' if selected else 'not affected; build/tests intentionally skipped'}\n"
    print(summary, end="")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
        output.write(summary)


if __name__ == "__main__":
    main()
