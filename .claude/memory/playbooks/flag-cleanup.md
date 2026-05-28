---
name: flag-cleanup
description: Remove a feature flag from code after 100% rollout.
metadata:
  type: playbook
---

# Playbook: Feature flag cleanup

> A 100% flag still in code is debt. Cleanup is part of done.

## When to clean up

- Flag at 100% for ≥ `cleanup_after` (per spec; default 30-90 days)
- No incidents in the last 14 days mentioning this flag
- Spec is `shipped`
- No related flags depend on this one

## Process

```bash
flag_name="$1"

# 1. Verify eligibility
status=$(claude -p "Check flag $flag_name eligibility for cleanup" --bare)

# 2. Find all call sites
rg "flag.$flag_name|getBooleanValue\('$flag_name'\)|useFlag\('$flag_name'\)" --type ts --type tsx --type js

# 3. For each call site, inline the ON branch
#    (the implementer agent handles this with TDD discipline)

# 4. Update tests
#    - Remove tests exercising the OFF path
#    - Add tests for the now-default path (if not already covered)

# 5. Verify
bash .claude/scripts/verify.sh

# 6. Open PR
gh pr create --title "chore(flags): remove $flag_name — 100% since $(date)" \
   --body "<rationale + impact + call-site count>"

# 7. After merge: delete flag from provider
claude -p "Delete flag $flag_name from provider; archive its definition" --bare
```

## Hard rules

- **Single PR per flag.** Don't batch. Each diff stays reviewable.
- **Don't pre-delete the flag definition.** The provider entry is the safety net during PR review.
- **CI must stay green.** Coverage + integration tests stay green; removed tests have replacements.
- **Don't remove "old behavior" helpers** unless they have no callers outside this flag.

## Recurring scan

A nightly job runs:
```bash
bash .claude/scripts/scan-stale-flags.sh
```
which queries the flag provider for flags at 100% > `cleanup_after`, opens tasks in `tasks/TASKS.md` with `priority: cleanup` and `flag: <name>`.

These tasks are eligible for autopilot pickup (low-risk, well-defined).

## Anti-patterns

- "We might want to roll back" → 100% for 90 days means no rollback need. Trust the data.
- "Combine 5 flag cleanups in one PR" → 5 hard-to-review diffs in one PR. No.
- "Keep the conditional, just hardcode to true" → still debt. Inline the path.

## References

- `.claude/skills/flag-cleanup/SKILL.md` — the skill that drives this
- `.claude/scripts/scan-stale-flags.sh` — nightly scanner
