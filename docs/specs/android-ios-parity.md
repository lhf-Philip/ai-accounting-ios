# Android / iOS Parity Source of Truth

## Goal
- iOS is the product source of truth.
- Android should match iOS page structure, wording, navigation rhythm, and core feature coverage.
- The only accepted platform-specific extension is the Android widget.

## Top-Level Screens

### Overview
- Large in-page title section, not a shared global top app bar.
- Date filter near the top.
- Quick start panel.
- Period summary cards.
- Entry points to ledger, reports, accounts, and guide.

### Ledger
- Large in-page title section.
- Fixed date filter row.
- Shortcut rail.
- Search field.
- Daily section headers.
- Initial advance creation is collapsed into one advance summary row.

### Reports
- Large in-page title section.
- Date filter near the top.
- Income/expense and category/tag controls on the same level.
- Donut / pie chart with drill-down path.

### Accounts
- Large in-page title section.
- Total estimated assets.
- Holdings by currency.
- Account list opens account detail before editing.
- Archived visibility is controlled from the page.

### Settings
- Large in-page title section.
- Beginner/help section.
- Preferences section.
- Tools section.
- Backup/import section.

## Required Flow Parity
- Add action sheet order:
  1. Transaction
  2. Scan receipt (AI)
  3. Transfer
  4. Debt (borrow / repay)
  5. Advance case
- Receipt scanning flow: pick image -> AI analyze -> user review -> save expense transaction.
- Debt flow: create transfer pair(s) matching iOS notes and entry modes.
- Account detail flow: account list -> account detail -> edit transaction / transfer / account.
- First-launch guide behavior stays aligned with iOS.

## Allowed Differences
- Android widget is Android-only.
- System pickers (date picker, file picker, permissions, media picker) may stay platform-native.
- Typeface may be a legal Android-native approximation, but hierarchy and spacing should remain aligned.

## Verification Matrix
- Overview / Ledger / Reports / Accounts / Settings title hierarchy matches iOS.
- Bottom tab and floating add button do not overlap hit targets.
- Add sheet routes match iOS ordering and wording.
- Receipt scan, debt entry, account detail all exist on Android.
- Android build and unit tests pass after each parity wave.
- iOS build passes after each parity wave to protect source-of-truth stability.


## Wave 2 Refinements
- Replace ad-hoc filter/search controls with shared parity capsules and segmented controls.
- Keep ledger filter, shortcut rail, and search field visually distinct but rhythmically aligned with iOS.
- Use parity-styled add sheet rows with supporting descriptions instead of bare text buttons.
- Tighten Reports chart card, list rows, and Settings section density toward the iOS source of truth.

## Wave 3 Refinements
- Add shared parity empty states and compact status pills so empty/list/detail views no longer fall back to plain text.
- Tighten Accounts and Account Detail rhythm toward iOS with clearer summary hierarchy, archived badges, and softer disclosure emphasis.
- Refine Reports drill-down sheets and budget alert cards so bottom-sheet detail and empty states feel closer to the iOS information density.
- Keep Ledger rows visually lightweight while improving empty-state guidance and advance-summary labeling.

## Wave 4 Refinements
- Tighten microinteractions with softer spring press feedback, clearer sheet handles, and more polished add-sheet presentation.
- Refine Overview entry rows and Floating Add Button emphasis so primary actions feel closer to iOS weight and disclosure rhythm.
- Improve Reports chart legibility with a softer track ring, clearer totals, rounded progress bars, and parity-styled drill-down sheets.
