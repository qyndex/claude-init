---
name: rollback
description: Playbook for rolling back a bad release.
metadata:
  type: playbook
status: established
created: 2026-05-28
last_verified: 2026-05-28
---

# Playbook: Rolling Back a Bad Release

Stay calm. Pull the lever you tested.

## Step 0 — IS THE FEATURE FLAG-GATED?

**Before anything else: if the suspect feature is behind a flag, the flip is your first move.**

```bash
grep -r 'flag.name' specs/active/ initiatives/active/
# If flag-gated:
/rollback-flag <name>     # ~60 seconds, no deploy
```

**Order of rollback preference:**
1. Flag flip — seconds, no deploy
2. Re-deploy previous binary — minutes
3. `git revert` + new deploy — 15-60 min (Step 1+ below)
4. Database rollback — last resort

Always try 1 first. See `.claude/memory/playbooks/flag-kill.md` for the flip flow.

---

## Decision tree (for non-flag-gated changes)

```
Is the bug user-affecting NOW?
├── YES → roll back immediately, then RCA
└── NO  → assess (severity, blast radius, fix complexity)
    ├── Fix < 30 min → roll forward with hotfix
    └── Fix ≥ 30 min OR risky → roll back, fix later
```

## Step 1 — Communicate

- Status channel: incident open, severity, what's affected.
- Stop new deploys (`gh workflow disable deploy.yml`).
- Pin oncall.

## Step 2 — Revert the code

```
# Find the offending commit
gh pr list --state merged --limit 5

# Revert via PR (preferred — leaves a paper trail)
gh pr create --title "revert: <conventional title>" --body @<(cat <<EOF
Reverts <PR url>

## Why
<one line — what broke>

## Tested
<how the revert was verified>
EOF
)

# Or, if the situation demands it, revert directly on main with full team awareness:
git revert -m 1 <merge-sha>
git push origin main
```

## Step 3 — Revert migrations (if any)

Database migrations need a reverse migration, not just a code revert.

```
# If using Alembic
uv run alembic downgrade -1

# If using Prisma
pnpm prisma migrate resolve --rolled-back <name>

# If using Drizzle
pnpm drizzle-kit drop
```

For destructive migrations (DROP COLUMN, etc.), data may be lost. If a backup exists, restore from backup; otherwise document the data loss in the incident.

## Step 4 — Deploy the revert

- Trigger the deploy pipeline.
- Watch the healthcheck.
- Verify the original user-facing symptom is gone.
- Capture screenshots / log lines as evidence that rollback worked.

## Step 5 — Stand down

- Status channel: incident resolved.
- Re-enable deploys when appropriate.
- Schedule postmortem within 24h.

## Step 6 — Postmortem

Open `.claude/memory/incidents/<date>-<slug>.md` from the template. Fill it in honestly. Action items must have an owner and a date.

## Anti-patterns

- **`git reset --hard`** on main. Never. You lose history.
- **Force-push to main.** Never.
- **Skipping the migration revert.** Data state will drift from code.
- **Skipping the postmortem.** The cost was paid; extract the lesson.
- **Blame.** Postmortems are blameless. The system failed; people did their best.
