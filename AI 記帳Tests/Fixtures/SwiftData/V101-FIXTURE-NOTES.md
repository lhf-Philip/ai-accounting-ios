# v1.0.1 SwiftData baseline fixtures

These are synthetic stores created by SwiftData from the **unchanged**
`AI 記帳/Models/DataModels.swift` at release `v1.0.1`, commit
`9063807944d1b46e2125711338c73acfa20f32e9`. `V101Models.swift.source` is the exact Git
blob. The generator verifies that identity and compiles it in a separate process
using the release app module name `AI_記帳`. Its `.source` extension prevents the
frozen model declarations from being compiled into the current app/test target.

The committed manifest records the model/generator SHA-256 hashes, compiler,
SDK, Simulator runtime, and hashes of each quiescent store/WAL/SHM file. The
producer exits before its files are copied. Generation never creates or updates
private SQLite tables; it uses `ModelContainer`, model initializers and `save()`.
Tests only open temporary copies; do not open these originals in Xcode or SQLite.

| Family | Source data |
| --- | --- |
| empty | Five-model schema, no records |
| populated | Two HKD/USD accounts, expense, income, two linked cross-currency transfer legs, one category, one tag and one shortcut |

Every ID, date, amount and label is synthetic and specified in the generator.
Amounts use exact decimal strings. The HKD account ends at 1114.41 and the USD
account at 62.80; transfer values are recorded amounts, not inferred FX estimates.
The fixtures do not contain advanced/budget/recurring models absent from v1.0.1.

## Regeneration

Use an installed, booted iOS Simulator and run from the repository root:

```bash
python3 'AI 記帳Tests/Fixtures/SwiftData/generate-v101.py' \
  --simulator <SIMULATOR_UDID> \
  --output /private/tmp/v101-new-fixtures
```

The output directory must not exist. No credentials, network fetch, production
app container or real user backup is needed. The target deployment version is
26.2; the **actual producer runtime** is recorded separately in the manifest.
Copy reviewed output into this directory only when deliberately regenerating.
Framework-generated store UUIDs mean byte hashes may change between runs; the
semantic assertions must stay stable. Do not update fixture hashes to hide a
migration failure.

## Current result: populated migration is blocked

On main `2b829a5`, the empty-family and provenance tests pass, but both populated
cases crash when reading `Category.kind`: `Could not cast value of type
Swift.Optional<Any> to AI_記帳.CategoryKind`. The container opens successfully;
reading the newly added non-optional enum exposes the failure. Earlier smoke
checks that read transaction amounts without `Category.kind` missed this.

A one-variable experiment skipped all raw repairs in the test's open helper; the
same populated fixture still crashed at that getter. Thus removing raw SQL alone
is not a demonstrated fix. Missing enum-value migration/backfill is the leading
hypothesis; the exact framework/storage mechanism and historical-runtime impact
remain unproven. Both crashes are product behavior on these recreated fixtures,
not an environment-blocked run. The failing regressions are intentionally kept
active; this draft must not merge until they pass with a reviewed migration fix.

No production repair, schema or migration plan is changed. v1.0.1 is the only
confirmed source baseline; the maintainer is unsure which intermediate manual
or TestFlight builds held persistent data. Do not infer support coverage from
the release tag alone.

## Assertions required before migration is considered safe

`LegacyStoreMigrationBaselineTests` verifies the frozen inputs; opens empty and
populated stores through the real backup/repair/open sequence twice; compares
IDs, exact balances, transaction types/currencies and model relationships; and
exports/imports JSON into a current-schema disk store and reopens it. An injected
open failure after real repairs verifies that the pre-repair snapshot matches
the original bytes and can recover the same data through two further opens.

These are release **source** fixtures generated on iOS 26.5, not preserved stores
from the OS shipped with that release. They do not prove all intermediate
TestFlight/manual-install versions are supported, or validate removing the
legacy repair bridge. Future coverage must add those source/runtime combinations
and current advance/budget/recurring fixtures before production versioned-schema
changes. See the [migration plan](../../../docs/DATA_MIGRATION_AND_RECOVERY.md).
