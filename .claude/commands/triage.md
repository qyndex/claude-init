---
description: Re-rank pending tasks by priority. Reads tasks/TASKS.md, surfaces stale items, suggests next 5-10 unblocked tasks based on priority + age + spec health.
argument-hint: "[--limit N]"
allowed-tools: Read, Glob, Grep, Bash
disable-model-invocation: true
---

# /triage — Backlog re-rank

```bash
limit="${1:-10}"

echo "# Triage — next $limit unblocked tasks"
echo

# Pending tasks (status [ ]), with priority + age
awk '
  /^- \[ \]/ {
    task = $0
    sub(/^- \[ \] /, "", task)
    getline next1
    getline next2
    # Extract priority, created
    pri = match(next1 next2, /priority: ([a-z_-]+)/) ? substr(next1 next2, RSTART+10, RLENGTH-10) : "normal"
    created = match(next1 next2, /created: ([0-9-]+)/) ? substr(next1 next2, RSTART+9, RLENGTH-9) : "unknown"
    print pri " | " created " | " task
  }
' tasks/TASKS.md | sort | head -n "$limit"

echo
echo "## Stale (>30 days, no recent activity)"
cutoff=$(date -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || date -v -30d '+%Y-%m-%d')
awk -v cutoff="$cutoff" '
  /^- \[ \]/ {
    task = $0
    getline next1; getline next2
    if (match(next1 next2, /created: ([0-9-]+)/) && substr(next1 next2, RSTART+9, 10) < cutoff)
      print task
  }
' tasks/TASKS.md | head -10

echo
echo "## Failed ([!]) — exhausted self-heal, awaiting a requeue decision"
# Round 13 Fix 3: [!] tasks were invisible (this list used to be [ ]-only), so failed
# work rotted. Surface them here; re-open one deliberately after fixing the root cause.
grep -E '^- \[!\]' tasks/TASKS.md | sed 's/^- \[!\] /  - /' | head -10
[ "$(grep -cE '^- \[!\]' tasks/TASKS.md)" -gt 0 ] && \
  echo "  → retry one: bash .claude/scripts/requeue-failed.sh --reset <T-id>"

echo
echo "## Recommendation"
echo "Priority order: hotfix > incident-followup > security > P1-spec > debt > normal > cleanup"
echo "Run /implement T-<id> to start the next item"
```

## Priority taxonomy

| Priority | Source | Triage cadence |
|---|---|---|
| hotfix | live prod alert (Sentry/SLO/synthetic) — Round 12 | **NOW — pre-empts everything** |
| incident-followup | postmortem action item | this sprint |
| security | security review | this sprint |
| P1-spec | spec marked priority:P1 | this sprint |
| debt | aged `[!]` items | next sprint |
| normal | most planner tasks | when bandwidth |
| cleanup | flag cleanup, dep upgrades | when bandwidth |
| deprecation | sunset / migration | quarter-bounded |

(Ordering matches the recommendation echo + `tasks/TASKS.md` taxonomy + `findings-to-tasks.sh`.)

$ARGUMENTS
