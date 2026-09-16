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

## Reproduced failure and migration coverage

On main `2b829a5`, populated cases opened but crashed at `Category.kind` with
`Could not cast value of type Swift.Optional<Any> to AI_記帳.CategoryKind`.
Skipping raw repairs, then bypassing startup entirely with a direct container,
both reproduced the same getter crash. This establishes that startup repair is
not necessary for this particular failure; it does not prove those repairs are
harmless on other stores or identify a unique framework defect.

A two-schema custom migration could fill the new value for untouched v1.0.1
stores, but failed for a store previously opened by main's automatic migration:
that store already matched the current schema while its enum value was missing.
The candidate therefore keeps a nullable enum representation in schema V3,
maps it from the original `kind` name, and fills only nil values during migration.
The public `Category.kind` remains non-optional; valid persisted values survive.

The production-path regressions remain active and now test the candidate plan.
Additional tests generate unversioned V2 stores using frozen model definitions,
cover all thirteen model types and existing Expense/Income/Both values, reproduce
an earlier automatic open, verify edits/reopens, and check unknown-schema recovery.
These V2 test stores are generated at test time, not archived historical artifacts.
An independent prototype compiled from unchanged main model source also confirmed
that a real unversioned current store is recognized and preserves all three kinds.

Confirmed source baselines are v1.0.1 and main `2b829a5`. Intermediate manual or
TestFlight schemas remain unknown to the maintainer. A store whose schema is not
recognized by the explicit plan enters recovery with its pre-open snapshot;
there is no fallback to an empty ledger or an unplanned automatic migration.
This limitation requires review before release; successful tests are not proof
that every historically installed build is covered.

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
beyond the current advance/budget/recurring coverage. See the [migration plan](../../../docs/DATA_MIGRATION_AND_RECOVERY.md).
