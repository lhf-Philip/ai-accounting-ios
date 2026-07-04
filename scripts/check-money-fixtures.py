#!/usr/bin/env python3
"""Reject non-integer floating-point money fixtures in iOS tests.

Swift `Decimal` values created from floating literals can differ across compiler
and SDK versions because the literal is first represented as binary floating
point. Money fixtures with fractional values must be string-backed instead.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST_ROOT = ROOT / "AI 記帳Tests"

FRACTIONAL_NUMBER = r"[+-]?(?:\d+_?)*\d+\.\d+(?:[eE][+-]?\d+)?"
MONEY_FIELD_NAMES = (
    "amount",
    "budgetAmount",
    "spentAmount",
    "remainingAmount",
    "ownAccountDelta",
    "debtBalanceDelta",
    "expenseReduction",
    "reportNetExpenseDelta",
    "incomeContribution",
    "settlementOnlyAmount",
)
MONEY_FIELD_PATTERN = "|".join(MONEY_FIELD_NAMES)

PATTERNS = (
    (
        "fractional money field literal",
        re.compile(rf"\b({MONEY_FIELD_PATTERN})\s*:\s*({FRACTIONAL_NUMBER})\b"),
    ),
    (
        "Decimal from fractional literal",
        re.compile(rf"\bDecimal\s*\(\s*({FRACTIONAL_NUMBER})\s*\)"),
    ),
)
ALLOW_LINE_MARKER = "money-fixture: allow-float-literal"


def scan_file(path: Path) -> list[str]:
    errors: list[str] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if ALLOW_LINE_MARKER in line:
            continue
        for label, pattern in PATTERNS:
            for match in pattern.finditer(line):
                errors.append(
                    f"{path.relative_to(ROOT)}:{line_number}: {label} {match.group(match.lastindex)} "
                    "must use exactDecimal(\"...\") or Decimal(string: \"...\")"
                )
    return errors


def main() -> int:
    if not TEST_ROOT.is_dir():
        print(f"missing iOS test directory: {TEST_ROOT.relative_to(ROOT)}", file=sys.stderr)
        return 1

    errors: list[str] = []
    for path in sorted(TEST_ROOT.rglob("*.swift")):
        errors.extend(scan_file(path))

    if errors:
        print("Money fixture checks failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Money fixture checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
