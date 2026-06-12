---
id: 004
slug: ci-gates-fail-own-code
status: draft
owner: "@claude"
human_owner: "@shravan"
created: 2026-06-13
updated: 2026-06-13
supersedes:
superseded_by:
complexity: L
objective: KR-2026Q3-HARNESS-FACTORY-FITNESS
initiative: harness-factory-readiness
service_tier: T1
feedback_refs: []
github_issue:
---

# Spec 004: CI gates fail against the harness's own code (live-E2E findings)

> Surfaced by the live greenfield E2E run (docs/GREENFIELD-E2E-TEST-PLAN.md) on
> 2026-06-12/13, the FIRST time GitHub Actions executed the harness gates on a
> real runner. Local `validate.sh` is green, but several required CI checks fail
> against claude-init's own shipped code AND against a clean greenfield scaffold.
> These were invisible to local testing — exactly the gap the E2E test existed to
> close. Evidence: qyndex/claude-init main run 27420264459 (Harness Validate),
> 27420264482 (CI/lint-test), 27420264515 (Silent Failure Audit); sandbox PR #2
> (qyndex/harness-e2e-sandbox).

## Problem statement

Five required-or-gating CI checks fail against code the harness ships, so a brand
-new project adopting the harness cannot merge its first PR, and claude-init's own
main is red. None reproduce under local `validate.sh`.

## Findings (each → a phase)

1. **Shellcheck on hooks fails the `harness-validate` + CI `lint-test` gates.**
   The shipped hooks carry ~44 shellcheck diagnostics (SC1083 literal `{}` in
   parameter expansions, SC2034 unused vars, SC2164 unguarded `cd`, SC2012/SC2011
   `ls` parsing, SC2221/SC2222 overlapping case patterns). The CI step runs
   `shellcheck --format=gcc` at default severity and fails on any; `validate.sh`
   does not run shellcheck, so local is green. Either the hooks must be clean or
   the gate severity/baseline must be declared — silently shipping a gate the
   harness's own code fails is the worst of both.

2. **`silent-failure-audit` reports 222 unjustified of 1059 → exit 1.**
   `lint-silent-failures.sh` flags 222 swallowed errors lacking a JUSTIFICATION.
   Gating on a number the harness itself fails makes every adopter's first push
   red. Needs a triage pass (justify the legitimate ones, fix the real swallows)
   and/or a committed baseline.

3. **`merge-gate` first-run / daily-batch check fails on a fresh repo.**
   `check-daily-batch` requires a recent green daily-batch or an inline
   first-run security scan; the inline path fails on a clean scaffold. Also: the
   age window uses `git log --reverse --format=%aI | head -1`, which reads the
   first *commit* date — `git archive` adoption preserves old timestamps, so a
   repo created today can read as weeks old and trip the >7-day bound falsely.

4. **`commitlint` `subject-case` rejects the harness's own §VI commit style.**
   Conventional-config's default `subject-case` rule rejects leading-capital /
   acronym subjects (e.g. `feat(e2e): AC-5 journey…`), but §VI's commit protocol
   permits any imperative summary. The harness ships no `commitlint.config.*`
   aligning the rule with its own documented protocol, so compliant commits fail.

5. **`doc-claims-audit` false-positives on `docs/factory-history/**`.**
   `audit-doc-claims.sh` greps "Blocked by <hook>.sh" enforcement-claim phrasing
   but matches the SAME phrasing quoted inside JSON `permissionDecisionReason`
   example strings in vendored factory-history docs — flagging gates that DO
   exist as ORPHANs. The audit should skip `docs/factory-history/**` (a vendored
   snapshot) and/or ignore quoted-JSON occurrences. (Open question: should the
   git-archive scaffold ship `docs/factory-history/` to greenfield adopters at
   all? If not, setup.sh template-clean should strip it — see spec 002 group-5.)

## Acceptance criteria

- **AC-1** `harness-validate` (shellcheck-on-hooks) passes on claude-init main and a fresh scaffold — hooks clean or a declared, committed shellcheck baseline.
- **AC-2** `silent-failure-audit` exits 0 on claude-init main — legitimate swallows justified, real ones fixed, or a committed baseline with a burn-down task.
- **AC-3** `merge-gate`/`check-daily-batch` passes (or correctly grants first-run allowance) on a repo created today, including one scaffolded via `git archive` (timestamp-leak case).
- **AC-4** A `commitlint.config.*` ships that accepts every commit-subject shape §VI permits; the harness's own history passes.
- **AC-5** `doc-claims-audit` produces zero orphans on claude-init main; factory-history quoted-JSON examples no longer false-positive.
- **AC-6** A re-run of the live E2E good-feature PR (#2 equivalent) goes green on every non-credential-gated required check.

## Out of scope

- The credential-gated LLM checks (`claude-review`, `security-review`, `anti-slop-triage`) — those need a repo secret (operator), tracked separately.
- Fixing the deploy stub (BYO, separate).

## Notes

The gauntlet half of the E2E (PR #3) is working as designed: 9 required checks RED
+ merge hard-refused. That is Phase 1 PASS. This spec is only about the GOOD-path
checks that should be green but aren't.
