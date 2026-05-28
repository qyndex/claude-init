# Deprecation Registry

> Central log of all deprecated APIs, dependencies, internal patterns, and config keys. **Every deprecation has a sunset date and an owner.** Nothing deprecates forever.

## How to add an entry

Run `/deprecate <kind> <thing>` or edit this file directly. New entries go at the top.

## Active deprecations

### API endpoints

| Endpoint | Announced | Sunset | Successor | Callers remaining | Owner |
|---|---|---|---|---|---|
| (none yet) | | | | | |

### Dependencies

| Dependency | Reason | Sunset | Replacement | Call sites | Owner |
|---|---|---|---|---|---|
| (example) `node-fetch` | Native `fetch` in Node 22+ | 2027-Q1 | global `fetch` | 47 | @platform |

### Internal patterns

| Pattern | Reason | Sunset | Replacement | Affected files | Owner |
|---|---|---|---|---|---|
| (example) `getUserSync` | blocking; not safe for serverless | 2027-Q2 | `await getUser()` | 23 | @platform |

### Config keys

| Key | Reason | Sunset | Replacement | Owner |
|---|---|---|---|---|
| (none yet) | | | | |

### Feature flags

| Flag | At 100% since | Cleanup due | Owner |
|---|---|---|---|
| (none yet) | | | |

## Archived

(Move shipped/closed deprecations here once done, keeping a 1-year window.)

## How to enforce

- `/deprecate <kind> <thing>` adds the row + opens a tracking task with `priority: deprecation`
- Nightly autopilot scans for deprecations past their sunset → opens cleanup tasks
- Security agent in `/review` checks for usage of deprecated dependencies in the diff
- `/audit-trail` includes deprecation status in the chain
- `/dependency-audit` (license-check workflow) flags deprecated deps in CI

## Lifecycle

```
proposed → announced → migration window → reduced traffic → final warning → sunset → archived
```

## Hard rules

- **Every entry has an owner and a sunset.** Unowned deprecations stall. Open-ended deprecations never finish.
- **Don't deprecate without a replacement.** "We'll figure out what's next" is not a plan.
- **Track call sites by count, decrementing over time.** Anything stalled for 60+ days needs escalation.
- **Archive when done.** Move to `Archived` section after sunset + 90 days.

## References

- `.claude/skills/api-versioning/SKILL.md`
- `.claude/skills/codemod/SKILL.md`
- `.claude/commands/deprecate-api.md`
- `.claude/commands/upgrade.md`
- `.claude/commands/sunset.md`
