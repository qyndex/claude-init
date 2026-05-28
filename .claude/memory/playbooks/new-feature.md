---
name: new-feature
description: End-to-end playbook for shipping a new feature from idea to deploy.
metadata:
  type: playbook
---

# Playbook: New Feature, End-to-End

The full eight-phase flow. ~3-5 days of work for a medium feature.

## Phase 1 — Constitution (one-time per project)

`/constitution` (if not already done). Done once when the project is first set up.

## Phase 2 — Specify

```
/specify <one-line feature idea>
```

Architect agent drafts `specs/active/<id>-<slug>.md`. You answer 1-4 open questions.

## Phase 3 — Plan

```
/plan <spec-id>
```

Architect agent drafts `plans/active/<id>-<slug>.md`. Reviewer checks coverage of spec criteria.

## Phase 4 — Tasks

```
/tasks <plan-id>
```

Planner agent appends N tasks to `tasks/TASKS.md` with `[P]` markers and `accept:` commands.

## Phase 4.5 — Analyze (consistency check)

```
/analyze <feature-id>
```

Catches dependency cycles, uncovered criteria, missing install tasks.

## Phase 5 — Implement

```
/implement next        # one task
/implement all         # walk the DAG until all done
```

Implementer agent runs strict TDD per task. Each task = one commit.

## Phase 6 — Verify

```
/verify <feature-id>
```

Verifier agent boots the app, walks the user journey, captures evidence into `verify/<date>-<feature>/`.

## Phase 7 — Review

```
/review              # code review
/review --security   # security review (always for auth/data/network changes)
```

Reviewer and security agents post findings. Implementer addresses blockers and highs.

## Phase 8 — Ship

```
/ship
```

Release agent pushes branch, opens PR, watches CI, asks for merge confirmation, squash-merges, tags release, triggers deploy.

## Estimated wall-clock time

| Feature size | Hands-on time | Wall-clock |
|---|---|---|
| XS (≤ 50 LOC) | 30 min | 1-2 hours |
| S (50-300 LOC) | 1-2 hours | 4-8 hours |
| M (300-1000 LOC) | 2-4 hours | 1-2 days |
| L (1000+ LOC) | 4-8 hours | 2-5 days |
| XL (multi-week) | break into multiple specs |

## Tips

- If the spec has > 4 open questions, the idea isn't crisp enough yet. Brainstorm first.
- If `/analyze` flags blockers, fix them before `/implement`. Don't ignore.
- If an `/implement all` loop stalls (no progress in 2 iterations), stop and inspect.
- The verifier should produce *real evidence*. A "looks fine" report doesn't count.
