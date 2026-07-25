---
id: 005
slug: traceability-and-decision-harvest
status: approved
owner: "@claude"
human_owner: "@operator"
created: 2026-07-24
updated: 2026-07-25
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Spec 005: Requirement traceability + decision harvest

## Problem statement

A 2026-07-24 traceability audit (see References) found that the harness's artifact
chain — roadmap → initiative → spec → plan → task → verify/evidence → decision — is
only partially wired. Some links are enforced, several are advisory-and-never-run,
and the decision layer captures nothing automatically. As the project grows, "what
requirement drove this change, and where is the proof it shipped?" cannot be answered
end-to-end from the artifacts alone. This spec closes the five concrete gaps the audit
identified so traceability is continuous and machine-checkable, not aspirational.

## Goals

In scope (each maps to an audited gap):
- **G1 — spec→plan completeness**: fail (or warn) when an `approved`/`shipped` spec has no plan. (spec-004 shipped planless, unflagged.)
- **G2 — run /analyze spec→task coverage**: make the "every AC maps to ≥1 task, every plan component maps to ≥1 task" check actually execute and produce `.claude/state/analyze-<id>.json` (today: zero markers exist).
- **G3 — decision harvest at ship time**: read merged-commit `Constraint:`/`Rejected:`/`Directive:` trailers and draft deduped ADR entries into `.claude/memory/decisions/`, human-approves promotion. Wires into `reconcile-shipped.sh` (shipped in the autonomous-ship PR).
- **G4 — SHIPPED.md ↔ task-state reconciliation**: detect and surface the disagreement where `specs/SHIPPED.md` records a spec FAIL/UNPROVEN while its tasks read done (specs 001/002 today).
- **G5 — roadmap/pivot linkage OR honest de-scope**: either wire roadmap→spec and pivot→spec references (and a `/pivot` skill), or explicitly mark those folders template-only in docs so they don't masquerade as traced.

## Non-goals

- Rewriting the eight-phase workflow or the ID conventions (spec:NNN, T-NNN stay).
- Auto-PROMOTING harvested ADRs without human approval (draft-only; human accepts).
- Building a full initiative-authoring flow (initiatives stay STATE-pointer-only unless G5 says otherwise).
- Retroactively back-filling ADRs for all historical commits (harvest is forward-looking from ship time; a one-shot backfill is optional).

## User stories

- As the operator, I want every shipped spec to have traceable proof (plan exists, ACs map to tasks, evidence bundle present) so I can trust "shipped" without re-deriving it.
- As the operator, I want the decisions the agent made to land in ADR format automatically so the decision log stays current without me hand-writing each one.
- As a future maintainer, I want `validate.sh` to flag a broken traceability link at PR time, not months later.

## Acceptance criteria

1. **AC-1 (G1)**: `validate.sh` reports, for every spec with `status: approved|shipped`, whether a plan referencing that spec id exists; a missing plan is at least a warning (decision: warn vs fail recorded in the plan). Proven by a test spec with no plan triggering the message.
2. **AC-2 (G2)**: `/analyze <id>` runs against a real spec and writes `.claude/state/analyze-<id>.json` containing the AC→task and plan-component→task coverage result; an uncovered AC is listed. Proven by running it on spec 003/004 and asserting the marker file + at least one coverage field.
3. **AC-3 (G3)**: a `harvest-decisions.sh` reads a merged commit's `Constraint:/Rejected:/Directive:` trailers and emits a **draft** ADR stub (or appends to a pending-decisions queue) under `.claude/memory/decisions/` (or `.proposed/`), deduped so re-running does not duplicate. It is invoked from `reconcile-shipped.sh` at ship time. Proven by feeding a fixture commit and asserting a draft ADR with those trailer lines, and idempotence on re-run.
4. **AC-4 (G4)**: a check compares `specs/SHIPPED.md` verdicts against task-completion state and emits a `TRACE-MISMATCH` line for any spec whose tasks read done but whose newest evidence verdict is FAIL/UNPROVEN. Proven by the current 001/002 disagreement being reported.
5. **AC-5 (G5)**: either (a) roadmap and pivot artifacts carry a resolvable spec/initiative reference validated by `validate.sh`, OR (b) `docs/` + the folder READMEs explicitly state these are template-only/unwired, and `validate.sh` does not imply they are traced. The chosen path is recorded in the plan.
6. **AC-6**: none of the above breaks existing gates — `validate.sh` stays rc=0 on the current tree, and the new checks are additive (advisory-first where they would otherwise red existing planless/uncovered specs, per the harness's advisory→required sequencing convention).

## Constraints

- **Surgical & advisory-first**: new checks that would red the *current* repo (e.g. spec-004 planless, 001/002 mismatch) ship advisory first, then flip to required in a follow-up once the existing debt is paid — same sequencing the liveness gate used.
- **Guarded files** (`validate.sh` is unguarded; hooks/skills/workflows/settings are guarded) → guarded changes ship as staged patches under `.claude/memory.proposed/patches/`.
- **Decision harvest is draft-only**: never auto-accept an ADR; human flips `status: proposed → accepted`.
- **Security**: no new network calls in the inner loop; harvest reads local git only.

## Open questions

Resolved at /clarify 2026-07-25:

- [RESOLVED OQ-1] G1: **warn-first**, flip to required in a follow-up once existing planless specs (spec-004) get plans. Matches liveness-gate advisory→required sequencing.
- [RESOLVED OQ-2] G3: harvested decisions land in **`.claude/memory/decisions/` as `status: proposed`** so `/adr-walk` surfaces them; a human flips `proposed → accepted`.
- [RESOLVED OQ-3] G5: **wire roadmap→spec and pivot→spec for real** — resolvable references + a `/pivot` skill + `validate.sh` link checks.

## Dependencies

- Depends on: `reconcile-shipped.sh`, `daily-briefing.sh` (shipped in the autonomous-ship PR / branch `feat/autonomous-ship`).
- Related: ADR-0004 (autonomous merge), ADR-0002 (evidence-based verification), ADR-0003 (TASKS.md sole authority).

## Change history

```
- 2026-07-24 | @claude | created | drafted from the 2026-07-24 traceability audit (5 gaps)
```

## References

- Traceability audit: this session's Explore agent findings (2026-07-24) — folder inventory, chain validators, gap map.
- Load-bearing files: validate.sh:498-613, spec-match.sh, initiative-state.sh:80-96, .claude/skills/analyze/SKILL.md, next-task.sh:112-116, shipped-registry.sh, adr-new.sh, memory-index.sh:265-385.
- Related ADR: ADR-0004
