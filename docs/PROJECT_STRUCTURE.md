# Project Structure

This document describes the current file layout for `AI 記帳` after cleanup.

## App Source

- `AI 記帳/AI___App.swift`: app entry point and SwiftData container setup.
- `AI 記帳/ContentView.swift`: main tab shell and global add-flow entry.
- `AI 記帳/Models/`: SwiftData models.
- `AI 記帳/Services/`: domain services (backup, budget, currency, health check, advances).
- `AI 記帳/Extensions/`: shared extensions.

## Views

- `AI 記帳/Views/Transactions/`: transaction list and add/edit/scan/transfer/debt flows.
- `AI 記帳/Views/Charts/`: reporting and drill-down charts.
- `AI 記帳/Views/Accounts/`: account list/detail/add/edit.
- `AI 記帳/Views/Advances/`: advance tracking and repayment flows.
- `AI 記帳/Views/Budgets/`: monthly budgets and alerts.
- `AI 記帳/Views/Categories/`: category management.
- `AI 記帳/Views/Tags/`: tag management (`TagsView`, `EditTagView`).
- `AI 記帳/Views/Tools/`: data health check and repair tools.
- `AI 記帳/Views/Settings/`: settings screen.
- `AI 記帳/Views/Common/`: shared cross-feature UI (`DateFilterView`).
- `AI 記帳/Views/Shortcuts/`: quick-entry shortcut editor.

## Repository Docs

- Root: `README*.md`, `CONTRIBUTING*.md`, `SECURITY*.md`, `LICENSE`.
- `docs/`: implementation/roadmap and project-internal docs.
- `scripts/`: repository maintenance scripts.

## Cleanup Notes

- Removed unused `AI 記帳/Item.swift` (template leftover, not referenced).
- Removed unused `AI 記帳/Views/TagReportView.swift` (functionality already covered by `Views/Charts/ChartsView.swift` tag mode).
- Moved view files from `AI 記帳/Views/` root into feature folders to reduce flat-file sprawl.

