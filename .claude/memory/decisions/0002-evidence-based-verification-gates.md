---
name: 0002-evidence-based-verification-gates
description: "ADR-0002: verification requires durable artifacts (TDD ledger, Playwright evidence rig, evidence bundle), not attestations (Round 10 A/B/C)"
status: accepted
created: 2026-05-25
metadata:
  type: decision
  status: accepted
---

# ADR-0002: Verification requires durable artifacts, not attestations

- **Date**: 2026-05-25
- **Deciders**: @shravanjha
- **Owners**: [@shravanjha]
- **written_by**: human
- **source_session**:
- **last_verified**: 2026-06-12
- **Context**: Round 10 audit — "done" claims with no artifacts; .claude/CLAUDE.md §VII
- **Tags**: architecture
- **subsystem**: verification
- **orphaned_from**:

## Context

Rounds 1-9 relied on agents *asserting* that tests ran and journeys worked.
The Round 10 audit found "done" tasks with no red/green proof, user-facing
changes shipped with no journey evidence, and PR bodies claiming AC coverage
that nothing could substantiate.

## Decision

Every "done" claim must be backed by a **durable artifact a machine can check**:

1. **TDD ledger** (Round 10 A) — `verify/<date>/T-<id>/red.log` + `green.log`; `verify.sh` blocks `[x]` without both.
2. **Playwright evidence rig** (Round 10 B) — `VERIFY_FEATURE=<id>` journeys capture video/trace/HAR/per-AC screenshots to `verify/<date>-<feature>/`; `spec-match.sh` maps ACs to tagged tests.
3. **Evidence bundle** (Round 10 C) — `collect-evidence.sh <spec-id>` emits the AC checklist embedded in the PR body; `evidence-gate` blocks merge on any UNPROVEN AC.

"Looks fine" is not verification. If there is no artifact, it didn't happen.

## Alternatives considered

- **Trust agent attestations** — zero overhead; rejected: demonstrably produced false "done"s (Round 10 evidence).
- **Human re-verification of everything** — highest assurance; rejected: does not scale to autonomous loops, defeats the harness's purpose.
- **CI-only verification** — central and tamper-resistant; partially adopted (evidence-gate); local gates still required so autonomous loops fail fast before PR time.

## Consequences

- Positive: a false "done" now requires forging artifacts, not just asserting; gaps are auditable after the fact.
- Negative: friction on small changes; mitigated by docs-only escape hatch (no-ac.json) and SKIP_* operator overrides.
- Neutral: verify/ becomes a growing artifact store — bounded by gc-verify.sh (30d archive).

## Re-verification triggers

- The 2026-06-12 gap audit (G49-G57) found the gates check existence, not truth — fixes land in the same campaign; re-verify this ADR holds after them.
- Playwright or the CI runner changes in a way that invalidates the evidence formats.
- 12 months elapse since `last_verified:`.

## References

- .claude/CLAUDE.md §VII
- docs/research/harness-gaps-10dim.md (Dimension 9)
- Related: ADR-0001, ADR-0003
