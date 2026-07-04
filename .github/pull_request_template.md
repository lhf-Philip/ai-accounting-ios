## Summary

-

## Scope

- [ ] iOS app
- [ ] Android app
- [ ] Widget (iOS)
- [ ] Widget (Android)
- [ ] Docs only

## Data Model / Backup Compatibility

- [ ] No data-model change
- [ ] Data-model change (completed all fields below)

If data-model changed:

- Contract doc updated: `docs/specs/data-model.md`
- Source store/schema version:
- Target store/schema version:
- Backup version decision: `unchanged` / `from -> to`
- Backward compatibility:
- Migration strategy:
- Rollback / recovery strategy:
- Old store or JSON fixtures tested:
- First and second launch verified:
- Export -> import -> export roundtrip verified:
- Risk if user imports old JSON backup:

- [ ] No destructive fallback, silent clear failure, or automatic empty-store recovery

## Validation

### Automated
- [ ] iOS CI passed
- [ ] Android CI passed (or N/A if Android not in this PR)
- [ ] String catalog validation passed
- [ ] Money fixture validation passed (if iOS tests changed)

### Manual
- [ ] Core bookkeeping flow checked (income/expense/transfer)
- [ ] Reports checked
- [ ] Backup export/import checked
- [ ] Advance tracking checked (if impacted)

## Security and Privacy

- [ ] No secrets added
- [ ] No personal backup data committed

## Documentation

- [ ] README/docs updated (if behavior/UI changed)
- [ ] In-app guide updated (if user flow changed)

## Related Issues

- Closes #
