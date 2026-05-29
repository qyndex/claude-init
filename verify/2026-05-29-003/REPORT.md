# Spec 003 — Audit Round-2 Remediation: Verification Report

Date: 2026-05-29 · Spec: `specs/active/003-audit-round2-remediation.md` · Plan: `plans/active/003-audit-round2-remediation.md` · Status: **COMPLETE**

## Summary

18 tasks (T-111..T-128), all `[x]`. 5 agent-implemented inline; 9 operator-gated (constitution-class: settings.json, .mcp.json, .github/workflows, .claude/CLAUDE.md, docs) applied via the one-shot `apply-spec-003.sh` script by the operator (the Auto-Mode classifier correctly blocks an agent from self-modifying its own permission/security config); 4 phase-exit/verification tasks.

Final gates — all green:

- `bash .claude/scripts/validate.sh` → **all checks passed** (15 categories incl. the new ruleset-coverage check)
- `bash .claude/scripts/check-model-consistency.sh` → **all agents match §V; no stale-version refs**
- `bash .claude/scripts/check-tdd-ledger.sh` → 0 fails (warn-only until evidence committed, then hard-enforcing)

Each task has paired `verify/2026-05-29-003/T-<id>/{red,green}.log`.

## AC status — all PASS

| AC    | Description                                         | Task  | Evidence                                                                             |
| ----- | --------------------------------------------------- | ----- | ------------------------------------------------------------------------------------ |
| AC-1  | verify.sh honors SKIP\_\* only with operator marker | T-111 | SKIP_TDD_LEDGER=1 w/o marker → gate still runs                                       |
| AC-2  | verify.sh logs active SKIP\_\* set                  | T-112 | verify/.skip-log honored=0/1                                                         |
| AC-3  | server-side TDD-ledger re-check                     | T-113 | step wired in harness-validate.yml; check-tdd-ledger.sh (R-1 tracked-only)           |
| AC-4  | evidence.json mandatory (no prose fallback)         | T-114 | evidence-gate.yml hard-fails without evidence.json                                   |
| AC-5  | bare Edit scoped to dirs                            | T-116 | 17 Edit() entries; no bare Edit                                                      |
| AC-6  | legit Write targets present                         | T-117 | Write(initiatives/\*\*) etc. + ./initiatives dir                                     |
| AC-7  | credential deny-list closed                         | T-118 | .npmrc/.git-credentials/.pfx/.tfstate/kubeconfig… Read+Write                         |
| AC-8  | real runtime sandbox; inert block removed           | T-120 | permissions.sandbox deleted; --sandbox documented in AUTOPILOT.md; §XI corrected     |
| AC-9  | filesystem MCP bypass documented                    | T-121 | §X note: deny-list does not gate filesystem MCP                                      |
| AC-10 | alwaysLoad MCP servers pinned                       | T-121 | filesystem+git → 2026.1.14                                                           |
| AC-11 | CI workflow model pins → opus-4-8                   | T-123 | 5 files bumped (review, security, claude, overnight, feedback-poll); zero stale refs |
| AC-12 | model-consistency scans workflows/docs              | T-124 | flags synthetic opus-4-7 workflow                                                    |
| AC-13 | worktree schema valid                               | T-125 | invalid baseRef + symlinkDirectories removed                                         |
| AC-14 | validate.sh ruleset↔job coverage check              | T-126 | synthetic missing-job context fails                                                  |
| AC-15 | specs 001/002 shipped                               | T-127 | both status: shipped                                                                 |
| AC-16 | auto spec-status advancement                        | T-127 | spec-status-sync.sh + post-write-roadmap.sh hook                                     |
| AC-17 | stale-spec-check flags ready-to-archive             | T-127 | stale-spec-check.yml tightened                                                       |
| AC-18 | full clean + REPORT                                 | T-128 | this report; all gates green                                                         |

## Files changed

**Agent-implemented (inline):**

- `.claude/scripts/verify.sh` — SKIP\_\* marker guard + logging (AC-1/2)
- `.claude/scripts/validate.sh` — ruleset-coverage category + FORCE_CONSTITUTION_EDIT log-exclusion fix (AC-14)
- `.claude/scripts/check-model-consistency.sh` — stale-version scan (AC-12)
- `.claude/scripts/spec-status-sync.sh` — NEW (AC-16)
- `.claude/scripts/check-tdd-ledger.sh` — NEW, server-side ledger gate (AC-3)
- `.claude/hooks/post-write-roadmap.sh` — fires spec-status-sync on TASKS.md change (AC-16)
- `.github/workflows/stale-spec-check.yml` — ready-to-archive detection (AC-17)
- `docs/AUTOPILOT.md` — model bump + runtime-sandbox section
- `specs/active/001,002` — status: shipped (AC-15)
- `.gitignore` — allow-skip-gates marker + verify/.skip-log

**Operator-applied (apply-spec-003.sh):**

- `.claude/settings.json` — Edit scoping, Write targets, deny-list, sandbox removal, worktree fix (AC-5/6/7/8/13)
- `.mcp.json` — filesystem+git pins (AC-10)
- `.github/workflows/{claude-review,claude-security,claude,evidence-gate,harness-validate}.yml` — model bumps, evidence-mandatory, ledger step (AC-3/4/11)
- `.claude/routines/{overnight-build,feedback-poll}.yml` — model bumps (AC-11)
- `.claude/CLAUDE.md` — §X filesystem-MCP note, §XI runtime-sandbox wording (AC-8/9)

## Round-1 inline fixes (prior, for the record)

CI job-name deadlock (harness-validate), version-agnostic model gate (check-doc-consistency.sh), graphify typo (.mcp.json), 4 broken agent skill refs, dead PII credit-card regex (PCRE→ERE), constitution-guard path-canonicalization + loud bypass logging.

## Residual / accepted risk (documented, out of scope → candidate spec-004)

- `npx`/`uvx`/`make`/`just`/`curl` remain in the allow-list (RCE-by-indirection) — kept per the "fix safe wins only" decision; needed for legitimate autonomous builds.
- `review`/`security-review` required checks carry `if: draft == false` (skipped→pending on draft PRs) + depend on `ANTHROPIC_API_KEY` — flagged by the CI auditor; not in spec-003 scope.
- `pre-bash-guard.sh` does not honor `FORCE_CONSTITUTION_EDIT` (by design — bash-guard is independent of the constitution-write guard); this is why operator edits to `.github/workflows` must avoid shell redirects (the apply script uses python in-place writes).

## Process note

The first `apply-spec-003.sh` run surfaced two real bugs that the agent then fixed: (1) the model bump missed `feedback-poll.yml` (hardcoded file list → made data-driven), and (2) `validate.sh`'s FORCE_CONSTITUTION_EDIT export-scan matched a transient runtime log in `.claude/hooks/.log/` (excluded `.log/` from the scan). Both are now fixed; second run was 19/19.
