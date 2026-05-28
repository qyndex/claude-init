---
description: Seed pre-built design patterns for popular stacks into .claude/memory/patterns/. Each pattern has a problem statement, canonical example, anti-pattern, and last_verified date. Round 9 E.
argument-hint: "<stack> [--force]   # stack: nextjs | react-vite | node-api | flask | fastapi | cross | all | auto"
allowed-tools: Bash, Read
disable-model-invocation: true
---

# /seed-patterns — Pre-built design patterns

```bash
exec bash .claude/scripts/seed-patterns.sh "$@"
```

## Stacks available

| Stack | Patterns seeded |
|---|---|
| `nextjs` | server-vs-client-components |
| `react-vite` | lazy-suspense-route-split |
| `node-api` | layered-architecture |
| `flask` | application-factory |
| `fastapi` | lifespan-context-manager |
| `cross` | repository-pattern, result-type, domain-events |
| `all` | all of the above |
| `auto` | detected via `detect-stacks.sh` |

## Examples

```bash
# Seed only for your detected stacks
/seed-patterns auto

# Seed for a specific stack
/seed-patterns nextjs

# Seed cross-cutting patterns
/seed-patterns cross

# Overwrite existing pattern files
/seed-patterns all --force
```

## What each pattern includes

- `name`, `description`, `slug`, `Owner`, `last_verified`, `verified_in_commits`
- Problem statement (when to use)
- Canonical code shape
- Anti-pattern (what NOT to do)
- "When NOT to use" exit clause

## Maintenance

Run `/review-patterns` annually (or after a major framework release) to bump `last_verified` and refresh examples. The reviewer agent auto-bumps `verified_in_commits` and `last_verified` whenever a pattern is observed clean in a diff (Round 5 C).

$ARGUMENTS
