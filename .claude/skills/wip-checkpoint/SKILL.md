---
name: wip-checkpoint
description: Continuous WIP-commit discipline for long features. Auto-commit at every decision point so the work survives crashes, terminal closes, and context compaction. Filter-squashed at PR time so history stays clean. From garrytan/gstack.
when_to_use: A feature is >2 hours of work. A long /loop run is starting. Inside any --bg background session. User says "checkpoint", "save progress".
model: inherit
---

# WIP Checkpoint

A crash 6 hours into a feature destroys 6 hours. WIP checkpoints make that recoverable in seconds.

## The pattern

After every meaningful decision (file structure choice, dependency added, test scaffold landed, refactor step done):

```bash
git add -A
git commit -m "WIP: <decision in 6 words>

[gstack-context]
state: <one line: where we are>
next: <one line: what's next>
why: <one line: rationale>

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## When to checkpoint

| Trigger | Example WIP message |
|---|---|
| Scaffolded new module | `WIP: scaffold auth module structure` |
| Added dependency | `WIP: add bcrypt for password hashing` |
| Wrote failing test (TDD red phase) | `WIP: failing test for login endpoint` |
| Passed test (TDD green phase) | `WIP: login endpoint returns 200` |
| Refactored | `WIP: extract validation to middleware` |
| Stuck, exploring | `WIP: explore: 3 approaches to session storage` |

Aim for one WIP commit every 5-15 minutes of work.

## Filter-squash at PR time

Before opening the PR, squash WIP commits into one (or a few) clean commits:

```bash
# Interactive rebase from the base branch, squash all WIP into one
git rebase -i origin/main
# Mark all "WIP:" commits as `squash`, keep only the final commit with a Conventional Commits message
# OR use the helper:
bash .claude/scripts/squash-wip.sh
```

The PR ends up with 1-3 clean commits; the WIP scaffold history is preserved in your local reflog and the squashed commit's body if you want to keep it.

## Hard rules

- **Always WIP-prefix.** Filter relies on the literal `WIP:` prefix.
- **Don't push WIP to shared branches.** WIPs stay on the feature branch until squashed.
- **Don't squash if rolling back.** If a WIP captured "what went wrong," it's valuable in incidents — let the postmortem reference it.
- **Auto-commit safe.** Never `git add` `.env`, `*.key`, or anything matched by the pre-write-secret-scan hook (which still runs).

## Crash recovery

After a crash or session loss:

```bash
git log --oneline --grep '^WIP:' -20    # last 20 checkpoints
git log -1 --format='%B' <wip-sha>      # full body of one checkpoint
```

The `state:` / `next:` / `why:` lines tell you where to resume. Pair with `/context-restore` to rebuild session context from WIP commit bodies.

## References

- garrytan/gstack (source — continuous checkpoint mode)
- ccg-workflow/templates/hooks/workflow-state.js (loop detection — if same `next:` appears 3 turns in a row, warn)
