---
name: flag-cleanup
description: Remove a feature flag from code after it's been 100% for the cleanup_after window. Greps call sites, replaces `if (flags.X)` branches with the new path, deletes the flag from the provider, archives the spec/initiative reference.
when_to_use: A flag has been default-ON at 100% for ≥ cleanup_after (default 30-90 days). User says "/flag cleanup <name>". Nightly autopilot scans for cleanup-ready flags.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite
model: sonnet
disable-model-invocation: true
---

# Flag Cleanup

A 100% flag still in code is debt. This skill inlines the new path and removes the conditional.

## Eligibility

A flag is cleanup-ready when ALL of:
- Provider shows 100% for ≥ `cleanup_after` (per spec's Rollout section; default 30 days)
- No related flags depend on this one
- No incidents in the last 14 days mentioning this flag's namespace
- Spec status is `shipped`

## Process

1. **Verify eligibility** (above checks).
2. **Find all call sites** — grep for `flag.name`, `useFlag('X')`, `getBooleanValue('X')`, `if(features.X)`, etc.
3. **For each call site**:
   - Inline the ON path (the new behavior)
   - Remove the OFF path (the old behavior) if it has no other reference
   - Delete any "old behavior" helper functions made dead by removal
4. **Update tests** — remove tests that exercise the OFF path
5. **Update the flag provider** — delete the flag definition or mark archived
6. **Update spec** — append cleanup note; final-status the rollout
7. **Open a PR** with title `chore(flags): remove flag.X — 100% since YYYY-MM-DD`
8. **CI must pass** — coverage and integration tests must stay green
9. **Single PR per flag.** Don't batch — the diff stays reviewable.

## Hard rules

- **Don't auto-delete the flag definition** before the PR merges. The flag-provider entry is the safety net during PR review.
- **Don't remove "old behavior" code** unless it has no callers outside this flag. Search broadly.
- **Don't merge if any test is removed.** Each removed test must have a replacement that exercises the now-default path.
- **Don't combine cleanups.** Each flag is a separate PR.

## Output

```
.claude/memory/playbooks/flag-cleanup-log.md  (appended per flag)
PR: chore(flags): remove flag.checkout_v2 — 100% since 2026-09-15
```

## Recurring scan

A nightly cron (or `/cleanup` extension) scans the flag-provider for flags that have been 100% for > cleanup_after, then opens cleanup tasks. Tasks are eligible for autopilot pickup.

## References

- Martin Fowler "Feature Toggles" — cleanup is part of the lifecycle, not optional
- Charity Majors on flag debt (https://www.honeycomb.io/blog/feature-flags)
