# Project Structure

Status: Active
Last reviewed: 2026-07-10
Applies to: iOS, Android

This document describes the current file layout for `AI 記帳`.

## iOS Source

- `AI 記帳/AI___App.swift`: app entry point and SwiftData container setup.
- `AI 記帳/ContentView.swift`: root tab shell (`Overview/Ledger/Reports/Accounts/Settings`).
- `AI 記帳/Models/`: SwiftData models.
- `AI 記帳/Services/`: domain services (backup, budget, currency, health check, advances).
- `AI 記帳/Services/Advances/`: cohesive advance semantics and maintenance modules; lifecycle and settlement extraction follows ADR 0005.
- `AI 記帳/Extensions/`: shared extensions.

## iOS Views

- `AI 記帳/Views/Home/`: home dashboard and quick entry views.
- `AI 記帳/Views/Onboarding/`: in-app user guide and onboarding UI.
- `AI 記帳/Views/Transactions/`: transaction list and add/edit/scan/transfer/debt flows.
- `AI 記帳/Views/Charts/`: reporting and drill-down charts.
- `AI 記帳/Views/Accounts/`: account list/detail/add/edit.
- `AI 記帳/Views/Advances/`: advance tracking and repayment flows.
- `AI 記帳/Views/Budgets/`: monthly budgets and alerts.
- `AI 記帳/Views/Categories/`: category management.
- `AI 記帳/Views/Tags/`: tag management (`TagsView`, `EditTagView`).
- `AI 記帳/Views/Tools/`: data health check and repair tools.
- `AI 記帳/Views/Settings/`: settings, data safety, and tool entry points.
- `AI 記帳/Views/Common/`: shared cross-feature UI (`DateFilterView`, title helpers).
- `AI 記帳/Views/Shortcuts/`: quick-entry shortcut editor.

## Android Source

- `android/settings.gradle.kts`: Android project settings.
- `android/build.gradle.kts`: plugin declarations.
- `android/app/build.gradle.kts`: app module config.
- `android/app/src/main/java/.../MainActivity.kt`: Compose entry activity.
- `android/app/src/main/java/.../core/`: Android domain models and pure parity logic.
- `android/app/src/main/java/.../core/advance/`: persistence-free advance semantics shared by repository and UI callers.
- `android/app/src/main/java/.../data/`: Room database, repositories, import/export, secure settings, and WebDAV support.
- `android/app/src/main/java/.../data/advance/`: transaction-owning advance maintenance operations.
- `android/app/src/main/java/.../ui/`: Compose screens, navigation, and parity UI components.
- `android/app/src/main/java/.../widget/`: Android-only summary widget provider.
- `android/app/src/test/`: Android unit tests and parity fixtures.
- `android/README.md`: Android build, test, and local setup notes.

## CI and Automation

- `.github/workflows/ios-ci.yml`: iOS build and string catalog validation.
- `.github/workflows/android-ci.yml`: Android build and unit tests.
- `.github/pull_request_template.md`: PR quality and compatibility checklist.

## Repository Docs

- Root: `README*.md`, `CONTRIBUTING*.md`, `SECURITY*.md`, `LICENSE`.
- `CONTEXT.md`: shared domain glossary and accounting semantics entry point.
- `docs/adr/`: accepted architecture decision records for ledger and report semantics.
- `docs/CI_CHECKLIST.md`: CI/release quality gate checklist.
- `docs/README.md`: developer documentation index.
- `docs/ARCHITECTURE.md`: system boundaries, data flow, and cross-platform architecture.
- `docs/DEVELOPMENT_GUIDE.md`: standard workflow for features, semantics, storage, and UI changes.
- `docs/DATA_MIGRATION_AND_RECOVERY.md`: store/backup migration and failure recovery runbook.
- `docs/TESTING.md`: automated/manual test responsibilities, commands, fixtures, and evidence.
- `docs/TROUBLESHOOTING.md`: safe failure diagnosis and recovery-oriented runbooks.
- `docs/RELEASING.md`: versioning, compatibility, release validation, tagging, and rollback.
- `docs/specs/data-model.md`: cross-platform data contract.
- `docs/specs/parity-test-vectors.md`: deterministic parity vectors.
- `CHANGELOG.md`: user-visible and compatibility-relevant release history.
- `scripts/check-docs.py`: read-only developer-document validation.
- `scripts/select-ios-simulator.py`: selects an installed iPhone Simulator for portable local test commands.
- `scripts/`: other repository maintenance scripts.

## Documentation Rule

When UI/IA changes affect user flow, update:

- in-app user guide (`Views/Onboarding/`)
- README (all maintained languages)
- relevant docs in `docs/`

When data model or JSON compatibility changes, update:

- `docs/specs/data-model.md`
- `docs/specs/parity-test-vectors.md`
- `.github/pull_request_template.md` compatibility section

in the same PR.
