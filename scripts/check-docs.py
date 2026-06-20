#!/usr/bin/env python3
"""Read-only developer documentation checks."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_PARTS = {
    ".git",
    ".codex",
    ".gradle",
    ".idea",
    "DerivedData",
    "build",
    "node_modules",
}

REQUIRED_DOCUMENTS = (
    "docs/README.md",
    "docs/ARCHITECTURE.md",
    "docs/DEVELOPMENT_GUIDE.md",
    "docs/DATA_MIGRATION_AND_RECOVERY.md",
    "docs/TESTING.md",
    "docs/TROUBLESHOOTING.md",
    "docs/RELEASING.md",
    "docs/PROJECT_STRUCTURE.md",
    "docs/specs/data-model.md",
    "docs/specs/parity-test-vectors.md",
    "CHANGELOG.md",
)

METADATA_DOCUMENTS = (
    "CHANGELOG.md",
    "docs/README.md",
    "docs/ARCHITECTURE.md",
    "docs/DEVELOPMENT_GUIDE.md",
    "docs/DATA_MIGRATION_AND_RECOVERY.md",
    "docs/TESTING.md",
    "docs/TROUBLESHOOTING.md",
    "docs/RELEASING.md",
    "docs/PROJECT_STRUCTURE.md",
    "docs/specs/data-model.md",
)

INLINE_LINK = re.compile(r"!?\[[^\]]*]\(([^)]+)\)")
REFERENCE_LINK = re.compile(r"^\s*\[[^\]]+]:\s*(\S+)", re.MULTILINE)
ADR_FILENAME = re.compile(r"^(\d{4})-[a-z0-9][a-z0-9-]*\.md$")

SENSITIVE_PATTERNS = (
    (
        "macOS absolute user path",
        re.compile(r"/Users/(?!<your-user>|<user>|USERNAME)([^/\s`]+)"),
    ),
    (
        "Windows absolute user path",
        re.compile(r"[A-Za-z]:\\Users\\(?!<your-user>|<user>|USERNAME)([^\\\s`]+)"),
    ),
    (
        "GitHub token",
        re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    ),
    (
        "Google API key",
        re.compile(r"\bAIza[0-9A-Za-z_-]{20,}\b"),
    ),
    (
        "assigned Apple development team",
        re.compile(r"\bDEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\b"),
    ),
    (
        "Apple signing identity",
        re.compile(r"\bApple Development:\s+[^<\n][^\n]*"),
    ),
)


def is_included(path: Path) -> bool:
    try:
        relative = path.relative_to(ROOT)
    except ValueError:
        return False
    return not any(part in EXCLUDED_PARTS for part in relative.parts)


def markdown_files() -> list[Path]:
    return sorted(
        path
        for pattern in ("*.md", "*.markdown")
        for path in ROOT.rglob(pattern)
        if path.is_file() and is_included(path)
    )


def display(path: Path) -> str:
    return str(path.relative_to(ROOT))


def parse_link_target(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and ">" in target:
        return target[1 : target.index(">")]
    # Markdown permits an optional title after a whitespace-separated target.
    if " " in target and not target.startswith(("http://", "https://")):
        target = target.split(maxsplit=1)[0]
    return target


def check_required(errors: list[str]) -> None:
    for relative in REQUIRED_DOCUMENTS:
        if not (ROOT / relative).is_file():
            errors.append(f"missing required document: {relative}")


def check_metadata(errors: list[str]) -> None:
    required_fields = ("Status:", "Last reviewed:", "Applies to:")
    for relative in METADATA_DOCUMENTS:
        path = ROOT / relative
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for field in required_fields:
            if field not in text:
                errors.append(f"{relative}: missing metadata field '{field}'")


def check_links(files: list[Path], errors: list[str]) -> None:
    for path in files:
        text = path.read_text(encoding="utf-8")
        raw_targets = INLINE_LINK.findall(text) + REFERENCE_LINK.findall(text)
        for raw_target in raw_targets:
            target = parse_link_target(raw_target)
            if not target or target.startswith(("#", "mailto:", "tel:", "data:")):
                continue

            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                continue

            decoded_path = unquote(parsed.path)
            if not decoded_path:
                continue

            resolved = (path.parent / decoded_path).resolve()
            if not resolved.exists():
                errors.append(
                    f"{display(path)}: broken local link '{target}' "
                    f"(expected {resolved.relative_to(ROOT) if ROOT in resolved.parents else resolved})"
                )


def check_adr_numbers(errors: list[str]) -> None:
    adr_dir = ROOT / "docs" / "adr"
    seen: dict[str, Path] = {}
    if not adr_dir.is_dir():
        errors.append("missing ADR directory: docs/adr")
        return

    for path in sorted(adr_dir.glob("*.md")):
        match = ADR_FILENAME.match(path.name)
        if not match:
            errors.append(
                f"{display(path)}: ADR filename must match NNNN-lowercase-kebab-case.md"
            )
            continue
        number = match.group(1)
        if number in seen:
            errors.append(
                f"duplicate ADR number {number}: {display(seen[number])}, {display(path)}"
            )
        else:
            seen[number] = path


def check_sensitive_content(files: list[Path], errors: list[str]) -> None:
    for path in files:
        text = path.read_text(encoding="utf-8")
        for label, pattern in SENSITIVE_PATTERNS:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{display(path)}:{line}: possible {label}")

    allowed_fixture_roots = (
        ROOT / "AI 記帳Tests" / "Fixtures",
        ROOT / "android" / "app" / "src" / "test" / "resources" / "fixtures",
    )
    for path in ROOT.rglob("*.json"):
        if not path.is_file() or not is_included(path):
            continue
        lower_name = path.name.lower()
        if "backup" not in lower_name and "autobackup" not in lower_name:
            continue
        if any(root == path.parent or root in path.parents for root in allowed_fixture_roots):
            continue
        errors.append(f"{display(path)}: backup-like JSON must not be committed")


def main() -> int:
    errors: list[str] = []
    files = markdown_files()

    check_required(errors)
    check_metadata(errors)
    check_links(files, errors)
    check_adr_numbers(errors)
    check_sensitive_content(files, errors)

    if errors:
        print("Documentation checks failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(
        "Documentation checks passed: "
        f"{len(files)} Markdown files, "
        f"{len(REQUIRED_DOCUMENTS)} required documents."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
