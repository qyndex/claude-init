---
description: Manage feature flags — register, status, ramp, kill, cleanup, list. Wired to OpenFeature / PostHog / LaunchDarkly / Unleash. Delegates to flag-rollout and flag-cleanup skills.
argument-hint: "[register <name>] | [status <name>] | [ramp <name> <pct>] | [kill <name>] | [cleanup <name>] | [list]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite, WebFetch
disable-model-invocation: true
---

# /flag — Feature flag management

## Sub-commands

### `/flag list`
Show all flags in the provider with: name, namespace (init prefix), current %, age, owner, stale-marker (>90 days at 100% = stale).

### `/flag register <name>`
Create a flag in the provider. Interview:
- Flag type: rollout | kill-switch | permission | experiment
- Default value
- Namespace (initiative_XXX_*)
- Owner
- Success metric + threshold
- Auto-rollback threshold
- Cleanup deadline

Writes flag definition to provider; updates `.claude/memory/flags/REGISTRY.md`.

### `/flag status <name>`
Show: current %, history of ramp events, monitoring metrics, age at current stage, next scheduled ramp action.

### `/flag ramp <name> <next-pct>`
Delegate to flag-rollout skill. Verifies current stage's exit gate is met before bumping to next %.

### `/flag kill <name>`
Emergency rollback. Flip to 0% immediately. Don't ask for confirmation in incident mode. See `/rollback-flag`.

### `/flag cleanup <name>`
Delegate to flag-cleanup skill. Inline the ON branch, remove conditionals, delete flag from provider, open PR.

## Hard rules

- **Always register the flag in the provider before merging code that reads it.** A flag-reading code path with no flag definition is undefined behavior.
- **Always namespace by initiative.** `init_042_*` prefix. Cross-initiative flag collisions are bug-prone.
- **Always set a cleanup deadline.** No "permanent" flags — even kill-switches get a renewal review every 6 months.
- **Always set auto_rollback thresholds.** Bare-flags-no-thresholds is shipping blind.

## Output

```
$ /flag list
Active flags (12):
  init_042_checkout_v2_db     100%  (89 days at 100% — CLEANUP READY)
  init_042_checkout_v2_api    50%   (4 days at 50%, target 100% in 3d)
  init_042_checkout_v2_ui     1%    (24h canary, error rate +0.02pp)
  killswitch_payments         100%  (always-on; review due 2026-12-01)
  ...
```

$ARGUMENTS
