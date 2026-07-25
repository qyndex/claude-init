---
id: 005
slug: traceability-and-decision-harvest
spec: specs/active/005-traceability-and-decision-harvest.md
status: approved
owner: "@claude"
created: 2026-07-25
updated: 2026-07-25
---

# Plan 005: Requirement traceability + decision harvest

Implements spec-005 (6 ACs, 5 audited gaps). Sequencing follows the harness
convention: **advisory-first** for any check that would red the current tree, guarded
files ship as staged patches, TDD red→green per component.

## Approach per gap

### G1 / AC-1 — spec→plan completeness (validate.sh, unguarded)
Add a `[spec-plan-trace]` block to `validate.sh`: for each `specs/active|archive/*.md`
with `status: approved|shipped`, check a plan exists whose frontmatter `spec:` (or id)
references that spec. Missing → **warn** (`warn()`, per OQ-1), naming the spec.
- Component: new validate.sh section. No new file.
- Decision recorded (OQ-1): warn-first. Flip-to-required is a separate follow-up spec.

### G2 / AC-2 — run /analyze coverage (script, unguarded)
The `/analyze` SKILL exists but never runs → zero markers. Build
`.claude/scripts/analyze-coverage.sh <spec-id>` that does the deterministic subset the
skill describes: parse `AC-N` from the spec, parse tasks tagged `spec:NNN` from
TASKS.md, and emit `.claude/state/analyze-<id>.json` with `{spec, ac_total, ac_covered,
uncovered_acs[], tasks_for_spec, generated}`. AC "covered" = at least one task
references the spec AND (heuristic) the spec has ≥1 task. Print uncovered ACs.
- Component: new script. Marker file is the AC-2 proof.
- Note: full AC↔task *semantic* mapping needs task→AC tags which the grammar lacks;
  this ships the structural coverage (spec has tasks, ACs enumerated) + lists ACs for
  human/`/analyze` to map. Honest scope in the script header.

### G3 / AC-3 — decision harvester (script, unguarded; wires into reconcile-shipped)
`.claude/scripts/harvest-decisions.sh <commit-ish>`: read the commit body, extract
`Constraint:/Rejected:/Directive:` trailers, and if the commit carries a
`Directive:` that names a decision (heuristic: non-trivial), write a **draft ADR** to
`.claude/memory/decisions/NNNN-<slug>.md` with `status: proposed` (OQ-2), body pre-
filled with the harvested trailers under Context/Decision. Dedupe by a content hash of
the trailer set stored in the ADR frontmatter (`harvest_hash:`) — re-running the same
commit does not create a second ADR. Reuses `adr-new.sh` numbering.
- Wire: `reconcile-shipped.sh` calls `harvest-decisions.sh <mergeCommit>` per reconciled
  PR (a 2-line addition — reconcile-shipped.sh is unguarded).
- Draft-only: never sets `accepted`.

### G4 / AC-4 — SHIPPED.md ↔ task-state reconciliation (script, unguarded)
`.claude/scripts/trace-mismatch.sh`: for each spec in `specs/SHIPPED.md`, compare its
recorded verdict against TASKS.md task-completion for that spec. Emit `TRACE-MISMATCH:
spec NNN tasks done but evidence verdict=FAIL/UNPROVEN`. Exit non-zero in `--check`
mode (for CI later), advisory by default. Reuses shipped-registry parsing.
- Proof: the current 001/002 disagreement is reported.

### G5 / AC-5 — wire roadmap→spec + pivot→spec (OQ-3: wire for real)
- **roadmap**: define a machine-readable roadmap row format carrying `spec:NNN`
  references; add a `validate.sh` `[roadmap-trace]` check that every referenced spec id
  resolves (warn on dangling). Seed `roadmap/changelog.md` or root `roadmap.md` with the
  format + a README note on the schema.
- **pivot**: add a `/pivot` skill (`.claude/skills/pivot/SKILL.md`, guarded → patch)
  that writes `pivots/active/<id>.md` with a resolvable `target:` (spec/initiative id);
  add `validate.sh` check that a pivot's `target:` resolves. Create `pivots/active/`.
- Components: validate.sh checks (unguarded) + `/pivot` SKILL.md (guarded, patch) +
  folder/README seeds.

### AC-6 — no regression
After every component: `validate.sh` rc=0. All new checks are `warn()` where the
current tree would otherwise red (spec-004 planless, 001/002 mismatch, dangling refs).

## Component → task decomposition (for /tasks)

| Task | Gap | File(s) | Guarded? | Test |
|---|---|---|---|---|
| T-P1 | G1 | validate.sh `[spec-plan-trace]` | no | test/spec-plan-trace.sh |
| T-P2 | G2 | analyze-coverage.sh + state marker | no | test/analyze-coverage.sh |
| T-P3 | G3 | harvest-decisions.sh + reconcile wire | no (reconcile unguarded) | test/harvest-decisions.sh |
| T-P4 | G4 | trace-mismatch.sh | no | test/trace-mismatch.sh |
| T-P5 | G5a | validate.sh `[roadmap-trace]` + roadmap schema/README | no | test/roadmap-trace.sh |
| T-P6 | G5b | /pivot SKILL.md (patch) + pivots/active + validate `[pivot-trace]` | skill guarded | test/pivot-trace.sh |
| T-P7 | AC-6 | full validate rc=0 + wire harvest into reconcile | mixed | verify sweep |

## Risks / rejected

- **Rejected**: full semantic AC↔task tagging (add `ac:` to task grammar) — changes the
  task grammar (§ non-goal "ID conventions stay"); structural coverage + AC listing
  instead.
- **Rejected**: hard-fail G1/G4 now — reds the current tree (spec-004, 001/002); OQ-1
  chose warn-first.
- **Risk**: harvester noise — every PR has many trailers. Mitigate: only `Directive:`-
  bearing commits draft an ADR, deduped by harvest_hash, draft-only so a human curates.

## Verification

Each task: red→green ledger under `verify/2026-07-25/T-P<N>/`. Final: `validate.sh`
rc=0, all new tests green, `harvest-decisions.sh` dry-run against a real merged commit
produces a proposed ADR, `trace-mismatch.sh` reports 001/002.
