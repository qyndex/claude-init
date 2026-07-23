# O-7 Second-Order-Effects Re-Review — Phase 2-5

> Researcher agent, 2026-07-24. Read-only. Third of three O-7 dimensions. The
> metabolism is now alive (Phase 0-1 shipped), which is exactly what makes these
> concurrency/merge effects reachable.

## Ranked findings

| id | severity | title | triggers | mitigation |
|---|---|---|---|---|
| CRITICAL-1 | CRITICAL | No locking on memory-plane writes; `with-lock.sh` exists but unused by memory scripts | M-11, M-12, M-13-14, M-18, M-21-22 | wrap `memory-index/gc/rollup/initiative-state` RMW in `with_lock` (shared lock name); M-18 CI writes via PR-branch, not direct push |
| CRITICAL-2 | CRITICAL | `index.jsonl`/`STATE.md`/rollups/`MEMORY.md` are full-rewrite → merge-hostile across swarm streams | M-10, M-11, M-23-26 | append+dedupe-by-id for index; drop wall-clock `updated_at` from STATE body; sort rollup children deterministically; route swarm syncs through `.swarms/coordinator/` |
| HIGH-1 | HIGH | `pre-spawn-cost-gate.sh` does NOT gate hook-originated/scheduled `claude` spawns (only Claude's own Bash-tool calls) | M-18, M-19 | inline `cost-summary.json` pct check inside `auto-dream-check.sh` + new M-19 spawn site before `nohup`, skip+log at ≥100% |
| HIGH-2 | HIGH | M-12/M-18 churn does NOT break stop-verify (`.claude/` pre-excluded, stop-verify.sh:91) but adds evidence-gate noise + compounds merge surface | M-12, M-18 | pin M-12 projection to network-boundary triggers only (not every write); label memory-plane diffs distinctly in evidence bundles |
| MEDIUM-1 | MEDIUM | `LIVENESS_SOFT` is plan-only (unimplemented); rollup-freshness check is wall-clock-relative not branch-local | M-04-promote, M-18 | promote only index-staleness + dream-failure-count (branch-local) to required validate.sh; keep rollup-freshness advisory-only |
| MEDIUM-2 | MEDIUM | `memory-index.sh verify` is O(n²)-ish per-ref rescan; grows as M-11/M-20 add edges | M-11, M-20 | not urgent; single-pass id→back_refs map if verify runtime grows |

## Answers to the four O-7 starting questions

1. **Cost gate:** NOT in the scheduled/hook spawn path (HIGH-1) — `pre-spawn-cost-gate.sh:81-84` only intercepts Claude's own Bash-tool `claude -p/--bg/--remote`; `auto-dream-check.sh:115-122`'s `nohup bash -c "…claude -p…"` runs as plain shell from a hook, never through the classifier.
2. **Concurrent writes:** REAL, unmitigated (CRITICAL-1). `with-lock.sh` proven for `tasks/TASKS.md` but zero memory scripts call it. Live race: `post-write-format.sh:62` fires `memory-index.sh touch` on every memory Write vs a backgrounded dream/M-05b `rebuild`'s truncate-then-rewrite (`memory-index.sh:138,160-170`).
3. **Tracked-file churn vs stop-verify:** NOT a stop-verify break (`.claude/` excluded at stop-verify.sh:91) — the real risk is merge-conflict surface (CRITICAL-2) + evidence-bundle noise (HIGH-2).
4. **Swarm merge conflicts:** REAL and structural (CRITICAL-2) — M-23-26 makes concurrent swarm writers to full-rewrite memory files normal.

**M-04-promote:** `LIVENESS_SOFT` unimplemented (name only, appears solely in planning docs); rollup-freshness (`harness-doctor.sh:194-216`) needs externally-supplied `LIVENESS_NOW_WEEK` → not branch-local. Recommend promoting only the two branch-local checks.

## Recommended plan change (decision for operator)

Insert a **pre-Phase-2 lead item** (call it **M-10-lock**) that wraps `with_lock "memory-plane"` around the read-modify-write sections of `memory-index.sh`, `memory-gc.sh`, `memory-rollup.sh`, `initiative-state.sh` **before** M-11/M-12 land — those are the first Phase 2-5 items to add new writers on top of today's unlocked paths. All four scripts are unguarded (`.claude/scripts/`), so this is a plain edit, TDD-testable with a concurrent-writer fixture.

## Red baselines captured (parent, live)
- **M-20**: `memory-index.sh verify` → **9 asymmetries** (matches plan). Mechanism confirmed: every ADR refs `ADR-000N` (token) but ids are slugs (`0001-…`) → `endswith` never matches → all 9 are id/ref-shape false-asymmetries. Fix = id-normalization in the matcher. `verify/2026-07-24/M-20/red-baseline.txt`.
- **M-18**: `cmd_weekly` computes `week=$(date +%G-W%V)` at `memory-rollup.sh:36`, no `$2`/target-week read → `weekly 2026-W25` silently identical to `weekly`. `verify/2026-07-24/M-18/red-baseline.txt`.
