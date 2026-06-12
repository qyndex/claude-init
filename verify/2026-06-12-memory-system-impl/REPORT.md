# Verification report — memory-system implementation

- **Date:** 2026-06-12
- **Spec:** docs/research/memory-system-review.md §7 (six recommendations from the panel review)
- **Status:** all six implemented; hook changes staged for operator install (constitution-class).

## Recommendation → implementation map

| § | Recommendation | Implementation | Status |
|---|---|---|---|
| 7.1 | Fix the template-line task grep | `T-[0-9]+` guard on every task-state grep in workflow-state.sh, session-start-context.sh, subagent-context.sh, session-end.sh | **Staged** (`*.sh.fixed` here) — hooks are operator-protected |
| 7.2 | Initiative living STATE.md + pointers | New `.claude/scripts/initiative-state.sh` (sync/show); STATE.md ≤60 lines at `initiatives/active/<id>.STATE.md`; pointers written to `.claude/state/current-{initiative,spec}`; sync wired into staged session-end.sh; injection wired into staged session-start-context.sh + subagent-context.sh | **Done** (script live; wiring staged) |
| 7.3 | Wire the read path | New `.claude/scripts/memory-recall.sh` (index-backed, path-intersection scoring, ≤K lines, injection-safe); wired into staged session-start-context.sh; constitution delegation row proposed in `.claude/memory.proposed/constitution-diff.md` | **Done** (script live; injection staged; constitution = proposal) |
| 7.4 | Lifecycle frontmatter enforcement | `validate.sh` new check (status + created/written_at on all topic files); backfilled 7 playbooks + 1 incident; `memory-index.sh` now maps `written_at`→`created`, excludes `in-flight*.md`, knows `rollup` type; index rebuilt: 16/22 entries with lifecycle data (was 0/9) | **Done** |
| 7.5 | Multi-horizon rollups | New `.claude/scripts/memory-rollup.sh` (weekly/monthly/quarterly/auto, 100-line caps, deterministic, idempotent); dream skill step 8 invokes it; first rollups generated (2026-W24, 2026-06, 2026-Q2) | **Done** |
| 7.6 | Loud memory-plane failures | `harness-doctor.sh` +4 checks (stuck-pending witness >2d, pointer presence, STATE.md freshness ≤7d, index ≥50% lifecycle-populated); staged session-start-context flags WITNESS-DEAD pending briefs; staged session-end reports sync failure on stderr; 3 dead May checkpoints archived | **Done** |

## Bonus defects found & fixed during implementation

1. **`grep -c ... || echo 0` double-print** (session-end.sh): on zero matches grep prints `0` AND exits 1, producing `0\n0`, which broke `--argjson` and silently zeroed out `session-recent.json` (observed 0 bytes). Fixed in staged copy.
2. **GNU-awk 3-arg `match()` on BSD awk** (session-start-context.sh rate-limit check): syntax error on macOS — the check never worked there. Replaced with a portable grep/sed/awk pipeline in the staged copy.
3. **jq `.` rebinding** in my own recall scoring (`$pt | startswith(.)` matches everything) — caught by the test suite, fixed.

## Evidence

```
$ bash .claude/scripts/test/memory-system.sh        # 15/15 pass
$ bash verify/2026-06-12-memory-system-impl/test-hooks.sh   # 10/10 pass
$ bash .claude/scripts/validate.sh                  # all checks pass (incl. new frontmatter check: 16/16)
$ bash .claude/scripts/harness-doctor.sh            # 15 checks, 0 failures (incl. 4 new memory-plane checks)
```

Key behavioral proof from test-hooks.sh: with the fixed workflow-state.sh, the
persisted next-task is `none` (was the literal `T-NNN | spec:NNN ...` template for
32 turns) and the phase advanced off the bogus `implementing`.

## Operator install (hooks are constitution-class)

```
! for f in workflow-state session-start-context subagent-context session-end; do cp "verify/2026-06-12-memory-system-impl/$f.sh.fixed" ".claude/hooks/$f.sh" && chmod +x ".claude/hooks/$f.sh"; done && bash verify/2026-06-12-memory-system-impl/test-hooks.sh | tail -2
```

Then review `.claude/memory.proposed/constitution-diff.md` and apply the two
constitution amendments by hand (or via /constitution).

## Verdict: PASS (re-verified 2026-06-12, post e2e-fix install)

Re-ran the proof commands after the operator installed the 52 staged e2e-fix files:

- `bash .claude/scripts/test/memory-system.sh` → passed=15 failed=0
- `bash verify/2026-06-12-memory-system-impl/test-hooks.sh` → passed=10 failed=0
- `bash .claude/scripts/validate.sh` → all checks passed (0 failures, 2 env warnings)
- `bash .claude/scripts/harness-doctor.sh` → 7 flags, ALL out-of-scope operator wiring
  (routine registration pending CLI login, release-please placeholder, repo secret,
  live ruleset activation, feedback/deploy wiring, 1 reviewed stop-verify block) —
  zero memory-plane failures; the 4 memory-plane checks this campaign added are green.

The four `.fixed` hooks shipped here were superseded by the e2e-fix staged install
(same fixes carried forward in `verify/2026-06-12-e2e-fixes/staged/`, installed by
the operator via APPLY=1 install.sh).
