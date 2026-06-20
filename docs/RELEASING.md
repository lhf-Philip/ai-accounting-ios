# Releasing

Status: Active
Last reviewed: 2026-06-20
Applies to: iOS, Android, GitHub releases
Sources of truth: [Testing Guide](./TESTING.md), [Data Migration And Recovery](./DATA_MIGRATION_AND_RECOVERY.md), [Deployment Guide](./DEPLOYMENT.md), [Changelog](../CHANGELOG.md)

This runbook covers a coordinated product release. Local Personal Team installs and debug APKs remain development deployments, not public releases.

## Version Policy

Use [Semantic Versioning](https://semver.org/):

- `MAJOR`: incompatible product or backup/data contract change requiring explicit migration expectations.
- `MINOR`: backward-compatible user-facing capability.
- `PATCH`: backward-compatible bug fix, safety improvement, or documentation-only release when a tag is needed.

The Git tag is `vMAJOR.MINOR.PATCH`.

Platform build identifiers are separate:

- iOS: `MARKETING_VERSION` is the product version; `CURRENT_PROJECT_VERSION` is the monotonically increasing build.
- Android: `versionName` is the product version; `versionCode` is the monotonically increasing build.

Current platform versions are not yet aligned. Before the next coordinated release, set iOS `MARKETING_VERSION` and Android `versionName` to the same product version, then increment both platform build numbers.

## Changelog Policy

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

- Add user-visible and compatibility-relevant changes under `Unreleased`.
- Use `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, and `Security` headings as needed.
- Do not copy commit history verbatim.
- Call out schema, backup, migration, and rollback implications explicitly.
- At release time, move entries to a dated version section and update comparison links.

## Release Preconditions

- Worktree is clean except intentional release changes.
- Release starts from up-to-date `main`.
- Open PR count is zero or every remaining PR is explicitly excluded.
- Required GitHub checks are green.
- `python3 scripts/check-docs.py` passes.
- Changelog is complete.
- Version/build numbers are correct.
- No local paths, secrets, signing identities, real backups, or personal data are staged.

## Compatibility Decision

Every release note must state:

- SwiftData compatibility: unchanged, additive-compatible, or migration required.
- Room schema transition and registered migration range.
- Backup JSON version and oldest supported import fixture.
- Whether downgrade to the previous app version is safe.
- Recovery action if migration or restore fails.

If compatibility is uncertain, stop the release. Validate against a copied store or generated legacy fixture first.

## Required Validation

### Automated

Run the commands in [Testing Guide](./TESTING.md):

- iOS simulator build and unit tests;
- focused iOS UI automation;
- Android unit tests and debug assembly;
- Android instrumentation;
- documentation checks.

### Backup roundtrip

1. Use a synthetic fixture representing the previous supported release.
2. Import it on both platforms.
3. Exercise one income/expense, transfer, advance/repayment, and report drill-down.
4. Export the result.
5. Import the new export again.
6. Verify IDs, balances, currencies, relationships, and health-check output.

### Physical-device smoke

- Install over an existing iPhone dataset; do not uninstall first.
- Relaunch at least twice after any persistence change.
- Install the Android release candidate on Samsung A53 or a comparable device.
- Verify onboarding/landing, ledger, report, account detail, settings, backup, and an editable advance case.
- Confirm keyboard dismissal and bottom actions on representative editors.

## Prepare The Release

1. Create a release branch:

```bash
git switch main
git pull --ff-only origin main
git switch -c codex/release-vX.Y.Z
```

2. Update:
   - iOS product/build versions;
   - Android product/build versions;
   - `CHANGELOG.md`;
   - compatibility statement and any release-specific docs.
3. Run all release validation.
4. Open a focused PR titled `Release vX.Y.Z`.
5. Merge only after required checks and review evidence are complete.

## Tag And Publish

After the release PR is on `main`:

```bash
git switch main
git pull --ff-only origin main
git tag -a vX.Y.Z -m "AI Accounting vX.Y.Z"
git push origin vX.Y.Z
```

Create the GitHub release from the tag. Use the curated changelog section, not an unreviewed generated commit list.

Attach artifacts only when they are intentionally distributable:

- never attach a debug APK as a production release;
- never attach signing files, provisioning profiles, keystores, or user backups;
- include checksums when distributing a signed APK outside a store.

## Platform Distribution

### iOS

Follow [Deployment Guide](./DEPLOYMENT.md#ios-deployment).

- Personal Team `Cmd + R` installs are temporary local development builds.
- TestFlight/App Store requires Apple Developer Program membership and App Store Connect setup.
- Archive the exact commit tagged for release.

### Android

Follow [Deployment Guide](./DEPLOYMENT.md#android-deployment).

- Debug APK is for local testing.
- Play distribution uses a signed release bundle and an upload key stored outside Git.
- Promote the same tested artifact through internal/closed/production tracks.

## Post-Release Checks

- Install or update from the chosen distribution channel.
- Confirm the displayed version/build.
- Run a short smoke on both platforms.
- Check GitHub Actions and user-reported startup/import failures.
- Keep the previous compatible release artifact and recovery instructions available.
- Move remaining `Unreleased` items forward rather than editing a published version silently.

## Rollback And Hotfix

- Prefer a forward hotfix over downgrading a migrated database.
- Do not publish an older binary unless its readers are confirmed compatible with the current store and backup schema.
- Preserve the affected store/backup before any recovery.
- Revert code only when the revert also preserves data compatibility.
- For a hotfix, branch from `main`, add a regression test, update the changelog, and increment the patch/build versions.
- If data recovery is required, follow [Data Migration And Recovery](./DATA_MIGRATION_AND_RECOVERY.md) and require user confirmation before replace restore.

## Release Evidence

Record in the release PR:

- commands and CI runs;
- physical devices and OS versions;
- previous fixture/store versions tested;
- backup roundtrip result;
- compatibility and rollback statement;
- final tag and distribution artifact identifiers.
