# Project Structure

This document describes the current file layout for `AI 記帳` after the 2026-03 UI refactor.

## App Source

- `AI 記帳/AI___App.swift`: app entry point and SwiftData container setup.
- `AI 記帳/ContentView.swift`: root tab shell (`Home/Ledger/Reports/Accounts/Settings`), global quick-add action, first-launch onboarding sheet.
- `AI 記帳/Models/`: SwiftData models.
- `AI 記帳/Services/`: domain services (backup, budget, currency, health check, advances).
- `AI 記帳/Extensions/`: shared extensions.

## Views

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
- `AI 記帳/Views/Common/`: shared cross-feature UI (`DateFilterView`).
- `AI 記帳/Views/Shortcuts/`: quick-entry shortcut editor.

## Repository Docs

- Root: `README*.md`, `CONTRIBUTING*.md`, `SECURITY*.md`, `LICENSE`.
- `docs/`: project-internal docs (structure, roadmap, implementation notes).
- `scripts/`: repository maintenance scripts.

## Documentation Rule

When UI/IA changes affect user flow, update:

- in-app user guide (`Views/Onboarding/`)
- README (all maintained languages)
- relevant docs in `docs/`

in the same PR.
