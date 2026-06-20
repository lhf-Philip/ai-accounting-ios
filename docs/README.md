# Developer Documentation

Status: Active
Last reviewed: 2026-06-20
Applies to: repository contributors and maintainers
Source of truth: the current `main` implementation and automated tests

This is the entry point for engineering documentation. Code and tests win when an older document disagrees; update the document in the same corrective PR.

## Start Here

1. [Project Structure](./PROJECT_STRUCTURE.md)
2. [Architecture](./ARCHITECTURE.md)
3. [Development Guide](./DEVELOPMENT_GUIDE.md)
4. [Testing Guide](./TESTING.md)
5. [Troubleshooting](./TROUBLESHOOTING.md)

## Domain And Data

- [Domain context and glossary](../CONTEXT.md)
- [Cross-platform data model](./specs/data-model.md)
- [Data migration and recovery](./DATA_MIGRATION_AND_RECOVERY.md)
- [Ledger classification ADR](./adr/0001-ledger-classification.md)
- [Advance and debt settlement ADR](./adr/0002-advance-and-debt-settlement.md)
- [Report currency estimates ADR](./adr/0003-report-currency-estimates.md)
- [Refund semantics ADR](./adr/0004-refund-semantics.md)

## Cross-Platform Parity

- [Android/iOS parity status](./specs/android-ios-parity.md)
- [Parity test vectors](./specs/parity-test-vectors.md)
- [Validation matrix](./VALIDATION_MATRIX.md)

## Operations

- [CI checklist](./CI_CHECKLIST.md)
- [Releasing](./RELEASING.md)
- [Deployment](./DEPLOYMENT.md)
- [Android APK build](./ANDROID_APK_BUILD.md)
- [WebDAV remote backup](./REMOTE_BACKUP.md)
- [Changelog](../CHANGELOG.md)

## Historical Material

- [Transfer, budget, and health-check roadmap](./ROADMAP_transfer_budget_healthcheck.md)

Historical documents provide design context but are not a promise that every described item remains current. Check active specs, code, and tests.

## Documentation Rules

- New or changed financial semantics require an ADR or an update to an accepted ADR.
- Persisted-data changes require data-contract, migration, rollback, and fixture updates.
- Shared functionality requires iOS/Android parity documentation and tests.
- Commands in active docs must be runnable from a documented working directory.
- Use synthetic examples. Never include real user backups, account numbers, names, secrets, signing identities, or machine-specific paths.
- Run `python3 scripts/check-docs.py` before opening a PR.
