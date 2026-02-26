#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/gh-admin-merge.sh <pr-number> [--repo owner/name] [--method squash|merge|rebase] [--skip-checks]

Examples:
  scripts/gh-admin-merge.sh 30
  scripts/gh-admin-merge.sh 31 --method merge
  scripts/gh-admin-merge.sh 32 --repo lhf-Philip/ai-accounting-ios --skip-checks
USAGE
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

PR_NUMBER="$1"
shift

if [[ ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: <pr-number> must be numeric." >&2
  exit 1
fi

REPO=""
METHOD="squash"
SKIP_CHECKS="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --method)
      METHOD="${2:-}"
      shift 2
      ;;
    --skip-checks)
      SKIP_CHECKS="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$METHOD" in
  squash|merge|rebase)
    ;;
  *)
    echo "Error: --method must be one of: squash, merge, rebase" >&2
    exit 1
    ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI is required." >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

echo "Repo: $REPO"
echo "PR: #$PR_NUMBER"
echo "Method: $METHOD"

if [[ "$SKIP_CHECKS" != "true" ]]; then
  echo "Waiting for required checks..."
  gh pr checks "$PR_NUMBER" --repo "$REPO" --watch
fi

echo "Merging with admin bypass..."
if ! gh pr merge "$PR_NUMBER" --repo "$REPO" --"$METHOD" --delete-branch --admin; then
  echo "Merge failed. If auth is required, run: gh auth login -h github.com" >&2
  exit 1
fi

echo "Done."
