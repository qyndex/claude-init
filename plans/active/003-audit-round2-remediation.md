---
id: 003
slug: audit-round2-remediation
status: approved
spec: specs/active/003-audit-round2-remediation.md
created: 2026-05-29
updated: 2026-05-29
---

# Plan 003: Audit Round-2 Remediation

Implements spec 003. Closes the round-2 audit findings not fixed inline. Six phases; each AC maps to ≥1 task with a machine-verifiable `accept:` command and a paired red/green TDD ledger under `verify/2026-05-29-003/`.

## Architecture / approach

No new subsystems. This is hardening of existing files plus three small new scripts:

- `.claude/scripts/spec-status-sync.sh` (AC-16) — derives spec completion from `tasks/TASKS.md`, flips `status: approved → shipped` when all referencing tasks are `[x]`/`[s]`. Called from `post-write-roadmap.sh`.
- `verify.sh` gains a SKIP-marker guard + SKIP-logging (AC-1, AC-2).
- `validate.sh` gains two new categories: ruleset↔job coverage (AC-14) and deny-list completeness (AC-7 assertion).

Settings.json + constitution-class edits (Phase 2/3 permission/sandbox, CI workflow model pins) are **operator-gated**: tasks generate the exact diff; the operator applies it under `FORCE_CONSTITUTION_EDIT=1` (now logged). Tasks that touch constitution-class files are marked `parallel: no` and flagged `operator-apply`.

## Phasing

- **Phase 1 — Gate enforceability** (AC-1..AC-4): verify.sh SKIP guard+log, server-side ledger in harness-validate, evidence.json mandatory. Highest delivery-integrity value → first.
- **Phase 2 — Permission hardening** (AC-5..AC-7): Edit scoping, Write targets, deny-list. Operator-apply (settings.json).
- **Phase 3 — Sandbox + MCP containment** (AC-8..AC-10): remove inert sandbox block + wire runtime sandbox + docs, scope filesystem MCP, pin alwaysLoad servers. Operator-apply (settings.json, .mcp.json, constitution).
- **Phase 4 — Supply-chain + config drift** (AC-11..AC-14): workflow model pins, model-consistency over workflows, worktree schema fix, ruleset↔job validate check. Operator-apply (workflows).
- **Phase 5 — Lifecycle correctness** (AC-15..AC-17): ship 001/002, spec-status-sync, stale-spec tightening.
- **Phase 6 — Verification + exit** (AC-18): validate clean + harness-doctor + REPORT.md.

## Data model / contracts

- `.claude/state/allow-skip-gates` — operator marker file (gitignored). Presence ⇒ verify.sh honors `SKIP_*`. Absence ⇒ ignored + gate runs.
- `verify/<date>/no-ac.json` sentinel — `{"verdict":"PASS","ac_unproven":[],"smoke_exit_max":0,"reason":"docs-only"}` for doc-only PRs (R-3 mitigation for AC-4).
- `spec-status-sync.sh` contract: reads `tasks/TASKS.md`, for each `specs/active/NNN-*.md` with `status: approved`, if every task line `spec:NNN` is `[x]` or `[s]` → rewrite frontmatter `status: shipped` + `updated: <today>`; `--dry-run` lists without writing; exit 0.

## Dependencies

- Phase 1 before Phase 6 (gates must enforce before final verify).
- Phase 2/3/4 operator-apply tasks depend on the operator clearing the leaked `FORCE_CONSTITUTION_EDIT` first (so the guard logs intentional edits), then re-setting it deliberately per edit.
- AC-14 (ruleset check) independent — can land first as the root-cause guard.

## Risks (from spec)

- R-1 server-side ledger false-fail on gitignored evidence → check only tracked `verify/` paths.
- R-2 Edit scoping blocks a legit root edit → mirror Write set + named root files exactly.
- R-3 evidence.json mandatory blocks doc PRs → `no-ac.json` sentinel.

## Acceptance command (whole plan)

`SKIP_COVERAGE=1 SKIP_STORY_MAP=1 SKIP_INTEG_COV=1 bash .claude/scripts/validate.sh && test -f verify/2026-05-29-003/REPORT.md`
