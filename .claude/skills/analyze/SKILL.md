---
name: analyze
description: Cross-check spec, plan, and tasks for consistency. Phase 4.5 of the eight-phase workflow. Catches scope drift, missing acceptance criteria, dependency cycles. Modeled on github/spec-kit /speckit.analyze. Run after /tasks, before /implement.
when_to_use: Spec, plan, and tasks all exist for a feature and you want a sanity check before coding. User says "analyze the plan", "check consistency", "any gaps".
argument-hint: "<feature id>"
model: sonnet
allowed-tools: Read, Glob, Grep, TodoWrite
---

# Analyze

Cross-artifact consistency check. Catch drift before it becomes code.

## Process

1. Read the **spec** (`specs/active/<id>-<slug>.md`).
2. Read the **plan** (`plans/active/<id>-<slug>.md`).
3. Read the **tasks** in `tasks/TASKS.md` filtered by `spec:<id>`.
4. Run the consistency checklist (below).
5. Report findings, severity-tagged.
6. Block `/implement` if any blockers.

## Consistency checks

- [ ] Every spec acceptance criterion has at least one task that exercises it.
- [ ] Every plan component is implemented by at least one task.
- [ ] No task references a file outside the plan's scope.
- [ ] No cyclic dependencies in the task DAG.
- [ ] Every task's `accept:` command is syntactically valid (no obvious typos).
- [ ] All declared dependencies (packages, services, MCP servers) appear in install/setup tasks.
- [ ] Spec, plan, and tasks share the same id namespace.
- [ ] No open `[OQ]` items in the spec.
- [ ] Phase boundaries align — every plan phase has tasks; no orphan tasks.
- [ ] Risks in the plan have mitigation tasks or explicit acceptance of the risk.
- [ ] Backwards-compat constraints from the spec appear as tests.

## Output

```
# Analysis — feature <id> — <date>

## Coverage
- Spec criteria with tasks: 8/8 ✓
- Plan components with tasks: 6/6 ✓
- Tasks with accept commands: 12/12 ✓

## Gaps
- BLOCKER: Acceptance criterion "rate limit 100 req/min" has no task.
- HIGH: Plan mentions `redis-rate-limiter` but no install task.

## Cycles
- None ✓

## Verdict
BLOCK — 1 blocker, 1 high. Address before /implement.
```

After save: post the summary to the user. If green, "Ready for /implement." If red, list the gaps.
