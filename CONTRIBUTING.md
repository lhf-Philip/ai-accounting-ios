# Contributing

Language: **English** | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)

## Workflow

1. Create a branch (`codex/<topic>` preferred).
2. Keep each PR focused on one change set.
3. Commit with validation notes.
4. Open a Pull Request to `main`.

## Before Submitting

- iOS changes: Xcode build passes.
- Android changes: Android CI command set passes.
- Core flows are manually verified when behavior changes.
- If UI/IA changes, update in-app guide and README/docs in the same PR.
- If data model or backup behavior changes, update:
  - `docs/specs/data-model.md`
  - `docs/specs/parity-test-vectors.md`
  - PR compatibility section in `.github/pull_request_template.md`
- No sensitive data is committed (API keys, tokens, personal data, real backup files).

## Recommended Commit Prefixes

- `feat: ...`
- `fix: ...`
- `refactor: ...`
- `docs: ...`
- `chore: ...`

## Reporting Issues

- For bugs, use the GitHub issue template with reproducible steps.
- For security concerns, follow [SECURITY.md](./SECURITY.md).

## Maintainer Admin-Bypass Merge

For repository maintainers (admin role), use the helper script:

```bash
scripts/gh-admin-merge.sh <pr-number>
```

Notes:

- Default merge method is `squash`.
- The script waits for checks before merge; use `--skip-checks` only if you intentionally bypass.
- Equivalent core command is `gh pr merge <pr> --admin`.
