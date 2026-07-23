# O-7 Test-Realism Re-Review — Phase 2-5

> Researcher agent, 2026-07-24. Read-only. Reviews the test realism of every
> Phase 2-5 item in `docs/research/memory-implementation-plan-2026-07.md` before
> the build starts. One of three O-7 dimensions (buildability + second-order
> effects run separately).

## Verdicts

| Item | Verdict | Key reasoning |
|---|---|---|
| M-19 (reconciliation) | UNTESTABLE-BY-RIG | plan-acknowledged; LLM prose |
| M-19 (fallback-trigger) | RIG-TESTABLE | reuses M-02 fixture shape |
| M-11 (§V auto-amend, prompt consumers) | UNTESTABLE-BY-RIG | plan-acknowledged; constitution-blocked |
| M-11 (mechanical convergence + contradiction detector) | RIG-TESTABLE, FALSE-GREEN-RISK | needs positive+negative fixture case for the detector |
| M-13-14 | FIXTURE-FRAGILE as worded → RIG-TESTABLE if corrected | plan self-corrected to "assert empty"; must not regress to literal "20 lines" |
| M-20 | FIXTURE-FRAGILE ("9 asymmetries") | needs synthetic index fixture + exact-count assertion, not live-repo count |
| M-15-16-17 | RIG-TESTABLE (3/4 clean) | archive reachability needs a synthetic `.archive/` chain fixture |
| M-18 | RIG-TESTABLE, conditional | requires `ROLLUP_NOW` actually threaded into `date` calls or backfill claim untestable |
| M-08 | RIG-TESTABLE | precedent exists (`shipped-registry.sh`) |
| M-10 | RIG-TESTABLE | needs positive+negative fixture |
| M-12 | RIG-TESTABLE, FALSE-GREEN-RISK | must diff byte-content outside markers, not just presence of decisions |
| M-21-22 | RIG-TESTABLE | mirrors `gc-suite.sh` idiom |
| M-23-26 | RIG-TESTABLE (mechanical); UNTESTABLE (ADR-classification accuracy) | fixture trees under `test/fixtures/adopt/` |
| M-04-promote | RIG-TESTABLE | best-designed; add anti-regression grep vs wall-clock reintroduction |

## Pre-build corrections required

1. **M-20**: rewrite red_assertion to a synthetic `index.jsonl` fixture with a manufactured asymmetry count (mirror the M-13-14 "assert output IS EMPTY" correction already in plan.json). "9" is a fact about the live repo, not a fixture.
2. **M-10 / M-11 / M-12**: require explicit **positive + negative** fixture cases:
   - M-11 contradiction detector must stay SILENT on a consistent fixture (else it passes by always firing).
   - M-12 must byte-diff content OUTSIDE the `<!-- BEGIN:auto -->` markers (else a full-file clobber false-greens).
   - M-10 rule must NOT reject a frontmatter-only ADR (else it just greps "Status" and fails everything).
3. **M-18**: confirm `ROLLUP_NOW` is threaded into `cmd_weekly`'s `date` computation as an M-18 **code** task — otherwise the "backfill W25-W30" claim is untestable without waiting real weeks.
4. **M-04-promote**: add a structural anti-regression grep asserting no raw `date +%s` window comparison exists outside the env-parameterized helper (guards against a later "simplification" reintroducing the wall-clock wedge that bit twice per plan §5).

## Established rig patterns (confirmed from Phase 0-1 tests)

- Hermetic `mktemp -d` + `trap rm -rf` fixtures; never mutate the real tree.
- `check()` pass/fail counters, final `passed:`/`failed:` lines.
- Guarded-file fix → staged `.patch`, test applies onto a temp copy via `git apply` (green pre-install). `dream-state.sh` SKIP-not-FAIL variant with `_REQUIRE=1`.
- PATH-shim stub (`metabolism-spawn.sh`): fake `claude` recording argv/env.
- Recording stub (`boot-autoheal.sh`): stubs append to a shared `calls.log` to assert call-order/gating.
- Deterministic clock via env vars (`GC_VERIFY_AGE_DAYS`-style) or relative dates — never hardcoded absolute dates.

## Open questions for operator

- O-6: extract M-19's ADD/UPDATE/DELETE/NOOP into a deterministic diff script, or accept untested?
- Confirm M-18's target-week arg threading is scoped as an M-18 code task, not assumed pre-existing.
