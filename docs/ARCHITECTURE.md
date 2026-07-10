# Architecture

Status: Active
Last reviewed: 2026-07-10
Applies to: iOS, Android
Source of truth: current application entry points, persistence models, services/repository, [`CONTEXT.md`](../CONTEXT.md), and accepted [`adr/`](./adr/)

AI Accounting is an offline-first personal ledger with separate native iOS and Android implementations. iOS defines product flow and user-facing semantics; both platforms share the accounting contract, backup format, and deterministic parity vectors.

## System Context

```mermaid
flowchart LR
    User["User"]
    IOS["iOS app<br/>SwiftUI + SwiftData"]
    Android["Android app<br/>Compose + Room"]
    Files["Local JSON / CSV files"]
    WebDAV["User-configured WebDAV"]
    FX["Exchange-rate provider"]
    Gemini["Google Gemini API"]
    Widget["Android home-screen widget"]

    User --> IOS
    User --> Android
    IOS <--> Files
    Android <--> Files
    IOS <--> WebDAV
    Android <--> WebDAV
    IOS --> FX
    Android --> FX
    IOS --> Gemini
    Android --> Gemini
    Android --> Widget
```

The app has no project-owned backend and no live cross-device synchronisation. WebDAV is deliberate backup and restore, not database replication.

## Platform Layers

```mermaid
flowchart TB
    subgraph iOS
        IRoot["AI___App / ContentView"]
        IViews["SwiftUI Views"]
        IServices["Domain and application services"]
        IModels["SwiftData models"]
        IStore["AI_Accounting_v3.store"]

        IRoot --> IViews
        IViews --> IServices
        IViews --> IModels
        IServices --> IModels
        IModels --> IStore
    end

    subgraph Android
        ARoot["AIAccountingApp / MainActivity / AIAccountingRoot"]
        AScreens["Compose screens"]
        ACore["Pure core calculators and semantics"]
        ARepo["AccountingRepository"]
        ADAO["Room DAOs and entities"]
        AStore["ai_accounting.db"]

        ARoot --> AScreens
        AScreens --> ACore
        AScreens --> ARepo
        ARepo --> ACore
        ARepo --> ADAO
        ADAO --> AStore
    end

    Contract["Shared contract<br/>CONTEXT + ADRs + data model + parity vectors"]
    Contract -. constrains .-> IServices
    Contract -. constrains .-> ACore
    Contract -. constrains .-> ARepo
```

### iOS responsibilities

- `AI___App.swift` owns store startup, pre-migration safety, and `ModelContainer`.
- `ContentView.swift` owns the top-level tabs and global add flows.
- `Views/` owns presentation state, navigation, input, and rendering.
- `Services/` owns accounting semantics, multi-record edits, reports, backup, repair, and external integrations.
- `DataModels.swift` owns persisted SwiftData entities and raw-value adapters.
- Complex writes use service APIs and `ModelContext.rollback()` on failure. Views must not recreate multi-record accounting logic.

### Android responsibilities

- `AIAccountingApp` creates `AppContainer`; `MainActivity` provides repository, currency, and UI preferences to Compose.
- `AIAccountingRoot` owns navigation and top-level app chrome.
- `ui/screens/` owns presentation state and user interaction.
- `core/` contains platform-independent calculations, enum contracts, report semantics, and security helpers.
- `AccountingRepository` is the application/persistence boundary for multi-record operations.
- `data/db/` owns Room entities, DAOs, relations, converters, and explicit migrations.
- Related writes use `RoomDatabase.withTransaction`. Screens must not write directly to DAOs.

## Advance Domain Modules

```mermaid
flowchart LR
    UI["SwiftUI / Compose advance flows"]
    Lifecycle["AdvanceCaseLifecycle<br/>create, edit, repay, delete"]
    Semantics["AdvanceSemantics<br/>pure direction and balance rules"]
    Settlement["AdvanceSettlement<br/>offset and manual settlement"]
    Maintenance["AdvanceMaintenance<br/>legacy repair and reconciliation"]
    Persistence["SwiftData ModelContext / Room DAOs"]
    Budget["Budget history"]

    UI --> Lifecycle
    UI --> Settlement
    Lifecycle --> Semantics
    Settlement --> Semantics
    Maintenance --> Semantics
    Lifecycle --> Persistence
    Settlement --> Persistence
    Maintenance --> Persistence
    Lifecycle --> Budget
```

- `AdvanceSemantics` is pure and cannot read or write persistence.
- `AdvanceCaseLifecycle` owns ordinary case mutations and keeps linked bookkeeping and budget history atomic.
- `AdvanceSettlement` owns grouped ledger-only settlement operations and grouped rollback.
- `AdvanceMaintenance` owns explicit repair/backfill operations; it is not part of normal user-entry flow.
- Modules use concrete implementations until a second real adapter justifies an interface.
- UI-facing drafts use IDs and scalar values rather than transporting SwiftData or Room entities across the module boundary.

Current extraction status:

- `AdvanceSemantics` and `AdvanceMaintenance` are concrete modules on both platforms.
- iOS implementations live in `AI 記帳/Services/Advances/`; Android implementations live in `core/advance/` and `data/advance/`.
- `AdvanceService`, `AdvanceCaseEditingService`, and Android `AccountingRepository` remain compatibility seams for lifecycle and settlement operations until the later ADR 0005 slices migrate their callers.
- The diagram above is the accepted target boundary, not a claim that every extraction slice is already complete.

The staged extraction and compatibility rules are recorded in [`adr/0005-advance-domain-modules.md`](./adr/0005-advance-domain-modules.md).

## Source-Of-Truth Hierarchy

When sources disagree, resolve them in this order:

1. Accepted ADR for accounting meaning.
2. [`CONTEXT.md`](../CONTEXT.md) vocabulary and invariants.
3. [`specs/data-model.md`](./specs/data-model.md) persisted and backup contract.
4. [`specs/parity-test-vectors.md`](./specs/parity-test-vectors.md) deterministic behaviour.
5. Current tested domain service/core implementation.
6. UI copy and README descriptions.

iOS is the source of truth for information architecture and flow. It is not allowed to override shared accounting semantics without updating the contract and Android.

## Ledger Write Flow

```mermaid
sequenceDiagram
    actor User
    participant UI as Editor UI
    participant Domain as Edit/semantic service
    participant Store as SwiftData or Room
    participant Derived as Budget/report derived data

    User->>UI: Enter and confirm values
    UI->>Domain: Submit typed draft
    Domain->>Domain: Validate account, sign, currency, links
    Domain->>Store: Atomically insert/replace all related rows
    alt validation or persistence failure
        Store-->>Domain: Error
        Domain->>Store: Roll back
        Domain-->>UI: Actionable error
    else success
        Domain->>Derived: Refresh affected budget/history state
        Domain-->>UI: Success
    end
```

- Ordinary income/expense may be a single row.
- Transfers, debt flows, advances, repayments, refunds, and grouped edits can affect several rows and must use a domain operation.
- A UI success state is shown only after persistence succeeds.

## Advance Structural Edit Flow

```mermaid
sequenceDiagram
    actor User
    participant Editor as Advance editor
    participant Service as Advance editing service/repository
    participant Store as Persistence

    User->>Editor: Change direction, currency, legs, people, or repayments
    Editor->>Service: Build explicit draft
    Service->>Service: Validate ownership and settlement invariants
    Service-->>Editor: Impact preview and warnings
    User->>Editor: Confirm
    Editor->>Service: Apply confirmed draft
    Service->>Store: Rebuild linked bookkeeping atomically
    alt failure
        Service->>Store: Roll back all changes
        Service-->>Editor: Preserve original case
    else success
        Service-->>Editor: Updated case
    end
```

Special settlement groups such as mutual offsets and manual cross-currency settlements are rolled back as a group before structural editing. They are not edited as ordinary repayments.

## Report Read Flow

```mermaid
flowchart LR
    Store["Persisted transactions and advance links"]
    Snapshot["Semantic snapshots"]
    Rules["Transaction / refund semantics"]
    Aggregate["ReportAggregation"]
    FX["Currency conversion estimates"]
    UI["Charts and drill-down"]

    Store --> Snapshot
    Snapshot --> Rules
    Rules --> Aggregate
    FX --> Aggregate
    Aggregate --> UI
```

Reports use transaction currency, not account currency. Transfers and settlement-only records are excluded. Main-currency values are estimates using the current rate service; original-currency totals remain available for audit.

## Backup And Restore Flow

```mermaid
sequenceDiagram
    participant UI as Settings / WebDAV UI
    participant Codec as Backup codec
    participant App as Backup manager/repository
    participant Store as Persistence

    UI->>Codec: Select and decode JSON
    Codec-->>UI: Validated backup preview
    alt merge
        UI->>App: Merge import
        App->>Store: Insert/update supported non-conflicting records
    else replace
        UI->>App: Replace import
        App->>App: Capture recovery state
        App->>Store: Clear and restore
        alt restore failure
            App->>Store: Restore recovery state / rollback transaction
        end
    end
```

Detailed migration and recovery rules are in [`DATA_MIGRATION_AND_RECOVERY.md`](./DATA_MIGRATION_AND_RECOVERY.md).

## Cross-Platform Parity

```mermaid
flowchart LR
    Product["iOS product flow change"]
    Semantics["Shared semantics decision"]
    Docs["CONTEXT / ADR / data contract"]
    IOS["iOS implementation + tests"]
    Android["Android implementation + tests"]
    Vectors["Parity vectors"]

    Product --> Semantics
    Semantics --> Docs
    Docs --> IOS
    Docs --> Android
    IOS --> Vectors
    Android --> Vectors
```

A shared feature is complete only when affected semantics, backup compatibility, tests, and documentation agree on both platforms. The Android widget and platform-native system pickers are the currently accepted platform differences.

## External Boundaries

- **Gemini**: optional user-provided API key; outputs are suggestions that require user review.
- **Exchange rates**: live rates with cached fallback; estimates are not historical FX facts.
- **WebDAV**: user credentials and optional backup passphrase; manual upload/restore only.
- **Files**: JSON is the recovery contract; CSV is a report export, not an import or lossless backup.
- **Secure storage**: iOS Keychain and Android Keystore-backed storage hold secrets. Secrets do not belong in SwiftData, Room, JSON backup, logs, or fixtures.

## Architecture Change Rules

Create or update an ADR when a change:

- changes report inclusion or accounting meaning;
- changes ownership of records or transaction grouping;
- introduces a new persistence/external-system boundary;
- is difficult to reverse;
- changes how iOS and Android divide responsibility.

Update this document when layer boundaries, entry points, data flow, or external integrations change.
