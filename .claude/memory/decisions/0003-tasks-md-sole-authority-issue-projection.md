---
name: 0003-tasks-md-sole-authority-issue-projection
description: "ADR-0003: tasks/TASKS.md is the sole task-state authority; GitHub Issues are a write-only projection (Round 11)"
status: accepted
created: 2026-05-27
metadata:
  type: decision
  status: accepted
---

# ADR-0003: tasks/TASKS.md is the sole task-state authority; GitHub Issues are a write-only projection

- **Date**: 2026-05-27
- **Deciders**: @shravanjha
- **Owners**: [@shravanjha]
- **written_by**: human
- **source_session**:
- **last_verified**: 2026-06-12
- **Context**: Round 11 — split-brain risk between board state and ledger state; .claude/CLAUDE.md §XVI
- **Tags**: architecture
- **subsystem**: task-state
- **orphaned_from**:

## Context

Two writable stores of task state (TASKS.md for agents, GitHub Issues/Projects
for humans) inevitably diverge. An autonomous loop reading board state that a
human dragged out of date — or vice versa — makes silently wrong decisions.
A single authority with one-way sync removes the reconciliation problem.

## Decision

`tasks/TASKS.md` is the **sole source of truth** for task state. GitHub Issues
are a **write-only projection** of specs (one issue per spec, phases as
sub-issues, atomic tasks as a checklist). Agents must never read task state from
the GitHub API (`no-issue-authority.yml` fails the build on `gh issue view` /
`gh api .../issues` in state-consuming contexts). Human board moves are
advisory — the projector re-asserts ledger state and comments. Sync happens only
at network boundaries (PR-time, coordinator merge, `/issues sync`), never in the
autonomous inner loop.

## Alternatives considered

- **Issues as authority** — best for human visibility; rejected: every autonomous decision would need an API round-trip, and agents would act on hand-dragged board state.
- **Bidirectional sync** — both sides writable; rejected: reconciliation conflicts are exactly the split-brain this decision removes.
- **No projection at all** — simplest; rejected: stakeholders need board visibility without reading a markdown ledger.

## Consequences

- Positive: zero split-brain; the ledger diff history is the audit trail; agents work offline.
- Negative: humans cannot change task state from the board; their moves get reverted with a comment.
- Neutral: a CI guard (no-issue-authority.yml) must stay in place permanently.

## Re-verification triggers

- GitHub Projects gains a webhook/locking model that makes bidirectional sync safe.
- The projector's revert-and-comment behavior generates sustained operator friction.
- 12 months elapse since `last_verified:`.

## References

- .claude/CLAUDE.md §XVI
- docs/ISSUE-LIFECYCLE.md
- Related: ADR-0001, ADR-0002
