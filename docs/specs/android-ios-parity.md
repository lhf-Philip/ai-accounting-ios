# Android / iOS Parity Source of Truth

## Goal
- iOS is the product source of truth.
- Android should match iOS page structure, wording, navigation rhythm, and core feature coverage.
- The only accepted platform-specific extension is the Android widget.


## Current Status
- Android is an active Compose implementation with Room persistence, core finance flows, and parity validation.
- iOS remains the source of truth for screen structure, copy, and flow semantics.
- Parity waves 1-8 established the app shell, top-level screens, deep editor polish, guide flow, report/account alignment, and safe bottom spacing.
- Remaining work should be tracked as specific parity deltas, not as a broad Android rewrite.

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
- Advance structural editing uses the same preview and confirmation sequence on both platforms for direction changes, case currency changes, split payment sources, and participant additions/removals.
- Both platforms rebuild linked bookkeeping atomically and reject partial edits of mutual offsets or manual settlements.

## Allowed Differences
- Android widget is Android-only.
- System pickers (date picker, file picker, permissions, media picker) may stay platform-native.
- Typeface may be a legal Android-native approximation, but hierarchy and spacing should remain aligned.

## Verification Matrix
- Overview / Ledger / Reports / Accounts / Settings title hierarchy matches iOS.
- Bottom tab and floating add button do not overlap hit targets.
- Add sheet routes match iOS ordering and wording.
- Receipt scan, debt entry, account detail all exist on Android.
- Android build and unit tests pass for parity-facing changes.
- iOS build passes after source-of-truth changes to protect parity stability.
- Documentation updates should distinguish completed parity waves from remaining deltas.


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

## Wave 5 Refinements
- Convert Android ledger and report range pickers from plain dialogs into parity-styled bottom sheets so filter selection feels closer to iOS.
- Add extra floating-action safe clearance and navigation-bar-aware bottom chrome to reduce crowding on devices like Samsung A53.
- Tighten Overview, Accounts, and Settings bottom rhythm so the final rows do not compete with the FAB or bottom tab hit area.
- Use section headers and denser utility grouping in Settings to better mirror the iOS information architecture.

## Wave 6 Refinements
- Bring deeper Android flows closer to iOS by reusing parity-style picker fields in debt entry and receipt scan review.
- Add floating-action safe clearance to account detail, debt, and receipt flows so deeper pages no longer feel tighter than the iOS source of truth.
- Tighten section hierarchy in debt entry, receipt scan, and account detail so the detailed flows match the same product voice as the top-level screens.

## Wave 7 Refinements
- Upgrade the Android user guide from a placeholder checklist to a full parity-style onboarding page with the same five-step structure and product emphasis as iOS.
- Keep first-launch and settings-entry guide flows aligned by using the same guide content with only the closing CTA label changing by context.

## Wave 8 Refinements
- Bring the highest-traffic Android editor flows closer to iOS by replacing plain section titles with parity section headers and adding the same floating-action safe clearance used elsewhere.
- Tighten transaction, transfer, and advance creation screens around parity segmented controls and parity picker fields so their form rhythm no longer falls back to generic Material defaults.
- Keep deep editing flows in the same product voice as the top-level parity screens, especially for mode switching, account/category picking, and bottom CTA spacing.

## Final Polish Checklist
- Overview: title, range controls, quick start card, period summary, feature entry rows, and empty-safe bottom spacing match the iOS rhythm.
- Ledger: pinned/unpinned controls, shortcut rail, search field, daily grouping, semantic edit/delete routing, and advance summary rows stay aligned.
- Reports: income/expense and category/tag controls remain on one level; chart empty states and drill-down sheets use parity components.
- Accounts: active-account asset summary, currency holdings, archived toggle, account-detail routing, and empty states are all present.
- Settings: beginner/help, preferences, data/tools, data safety, and debug sections keep the same information architecture as iOS.
- Deep editors: transaction, transfer, debt, advance, receipt review, and account detail use scrollable content with navigation-bar-safe bottom clearance.
- Remaining known difference: Android widget stays Android-only; platform-native pickers remain acceptable where they do not change app flow semantics.
