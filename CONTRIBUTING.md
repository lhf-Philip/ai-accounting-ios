# Contributing

Language: **English** | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)

## Workflow

1. Fork this repository.
2. Create a branch (`feature/...` or `fix/...`).
3. Commit your changes with validation notes.
4. Open a Pull Request.

## Before Submitting

- Project builds successfully in Xcode.
- Core flows are manually verified: add transaction, transfer, reports, backup/restore.
- If UI/IA is changed, update in-app guide and README/docs in the same PR.
- No sensitive data is committed (API keys, tokens, personal data, real backup files).

## Recommended Commit Prefixes

- `feat: ...`
- `fix: ...`
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
