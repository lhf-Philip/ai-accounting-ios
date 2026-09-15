# Historical SwiftData fixtures (#169)

These eight populated stores reproduce the distinct intermediate model structures
between v1.0.1 and frozen V2. They are synthetic stores generated on iOS 26.5 with
Xcode 26.5, not original device files or proof that these builds were deployed.
`eras.json` pins the exact original `DataModels.swift` source commits and the
producer feature flags. Every era's `.manifest.json` records model/generator
SHA-256, Xcode/runtime and the complete store/WAL/SHM hashes.

| Structure | Exact source commit | Internal schema version |
| --- | --- | --- |
| transfer | `227f2bb1d06cac848feb2e38d83f111409aa6231` | 1.1.0 |
| budget | `e29c0e44d04751bdae4e47ba5c2206266cdb6cf0` | 1.2.0 |
| advance | `7ee47caa342dd6e8efe622504dea27ff489d60ac` | 1.3.0 |
| advance_links | `664458e9c64f460741b1e22841a75853f5e09bde` | 1.4.0 |
| history | `fb2f437c1b981f46e8b1976df23b456bc7d47468` | 1.5.0 |
| settings | `f342461ab54a70d502ddf56d4a877f684185e429` | 1.6.0 |
| recurring | `b7e8dda0770400336a3f70ef665e483b6ed7c3aa` | 1.7.0 |
| pre_v2 | `abd3b2020d9416a6803f1a1081528c8dbac9defa` | 1.8.0 |

The model history from release `9063807` through main `2b829a5` was inspected.
`9012ed5` only changes whitespace in an enum switch, so it shares the advance-links
structure. Commit `0f5e5b6` makes advance tags optional and matches frozen V2.
Schema version numbers are internal identifiers, not historical app versions.

## Generation and provenance

On a Mac with Xcode and a booted iOS simulator, from the repository root:

```sh
python3 scripts/generate-historical-stores.py \
  --simulator YOUR_BOOTED_SIMULATOR_UUID \
  --output /tmp/new-historical-stores
```

The destination must not exist. The script reads pinned model bytes with `git show`
and compiles each producer as module `AI_記帳`, Swift 5, MainActor default isolation,
using SwiftData's public APIs. Only the generator seed data uses conditional flags;
the historical model source is unchanged. It waits for producer exit before hashing
and using the store family. Copy each generated `golden` family into this fixture
directory with the era prefix (`transfer.store`, `transfer.store-wal`, etc.) and its
manifest as `transfer.manifest.json`. Manifest file keys retain the production
`AI_Accounting_v3.store` name, which tests use for temporary migration copies.
Never regenerate fixtures as part of normal CI or open committed originals.

## Seed data and regression boundary

Every era contains two accounts, three distinct category kinds, a tag, shortcut,
expense, income and linked two-currency transfer. Fixed UUIDs and exact decimal
balances (`1114.41` HKD and `62.80` USD) detect data replacement or lost relationships.
Successive eras also contain a monthly budget; an advance with participant and
repayment; advance transaction/transfer links; budget history; carry-over settings;
a recurring rule with a confirmed occurrence; and explicit advance links plus
nonempty required tags. `HistoricalStoreMigrationTests` verifies those values and
relationships after migration and reopening, plus unchanged fixture/snapshot hashes.

The isolated red control used each store with production startup from old main
`2b829a5` and the pre-fix PR head `65d65bb`. All eight opened/reopened with old main
(core IDs/kinds/balances/relationships checked), while all eight entered recovery
under `65d65bb` with Core Data error 134504 (unknown model version). Their original
snapshots remained byte-identical. This proves a compatibility regression for
these recreated historical-source stores; it does not prove deployment history.

Local validation with Xcode 26.5 passed 21 focused migration/startup tests on iOS
26.5 and 17 migration tests on iOS 26.2 (reusing the compiled test bundle). Both
runs executed all eight historical fixture cases; the fixtures were produced on
26.5, so the second run is consumer-runtime coverage, not original-OS provenance.

The repaired production plan recognizes each source and retains the final V2-to-V3
nullable-kind migration. Earlier automatic migrations can leave newly introduced
required values missing, so intermediate stages never read those getters. Existing
V1 and previously automatically migrated V2 regression cases remain essential.

Original historical runtime/device artifacts and unknown local model edits remain
outside this evidence. Keep #169 open for those release checks and separate review
of the remaining raw compatibility repairs.
