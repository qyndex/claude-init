---
id: <NNN>
slug: <kebab-case-slug>
status: proposed   # proposed | active | paused | shipped | dropped | abandoned | superseded
horizon: quarter   # week | month | quarter | half | year | multi-year
owner: "@<person>"
sponsor: "@<exec>"
created: YYYY-MM-DD
target_ship: YYYY-Qn   # or YYYY-MM-DD
supersedes: <id>   # optional
superseded_by:     # set when a successor pivot replaces this initiative
feedback_refs: []  # FB-IDs from .claude/memory/feedback/ that drove this initiative

# ─── Round 7 B: Shape Up appetite ──────────────────────────────────────
# Declare a FIXED time/budget appetite up front. Scope flexes within the appetite,
# not the other way around. Circuit breaker (Round 7 B) fires at 50% and 100%
# and surfaces for review — default action is NOT auto-kill, but the operator
# must decide: extend (with explicit must-have justification), cancel, or pause.
appetite:
  time: 6w           # e.g. 2w, 4w, 6w, 12w (a full quarter is the max)
  budget_usd: 5000   # tokens + infra; tracked via .claude/scripts/cost-report.sh --by-initiative
  declared_at: YYYY-MM-DD
  circuit_breaker:
    at_50pct: convergence_check   # warn if hill chart shows uphill
    at_100pct: surface_for_review # default per Round 7 user pick — operator decides
  extension_allowed_iff:
    - remaining_scope_is_must_have
    - all_unknowns_resolved
    - peer_review_signoff
---

# Initiative <NNN>: <Title>

> The "above the spec" artifact. Use for any program that spans more than one quarter, more than one team, or more than a handful of specs. **An 18-month migration lives here, not in `specs/`.**

## North star

<One paragraph: why this initiative exists; what outcome it produces; who benefits.>

## Strategic context

- **Objective** (link to `OKRs.md`): KR-2026Q3-04 — "Reduce checkout failure rate from 2.1% to 0.5%"
- **Stakeholders**: <names + role + interest>
- **Adjacent initiatives**: <ids that this depends on / blocks / overlaps>
- **Hypothesis / bet**: <what we're trading; what proves us right or wrong>

## Success criteria

Each criterion must be:
- Measurable (cite the metric + source)
- Time-bounded (cite the target date)
- Externally verifiable (cite the dashboard / SLO / business KPI)

1. ...
2. ...
3. ...

## Anti-goals (explicitly out of scope)

- ...
- ...

## Phases (each phase ships independently)

| Phase | Window | Theme | Exit criterion | Owns specs |
|---|---|---|---|---|
| P0 — Discovery | 2026-Q3 | scope + ADRs | spec catalog complete + 3 ADRs landed | 001, 002 |
| P1 — Foundation | 2026-Q4 | platform plumbing | data model + service skeletons behind flag-default-OFF | 003, 004, 005 |
| P2 — Migration | 2027-Q1 → Q2 | iterative cutover | per-tenant cutover automated; old path deprecated | 006-020 |
| P3 — Decommission | 2027-Q3 | legacy removal | old code deleted; storage reclaimed | 021, 022 |

## Roadmap dependencies

- Depends on: <initiative id> (`needs API gateway v2 from initiative 003`)
- Blocks: <initiative id>
- External: <vendor / regulatory / partner>

## Risks (ranked)

| Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|
| Migration tooling slower than planned | M | H | parallelize tenant batches; pre-warm caches | @<name> |
| Regulatory change Q1 | L | H | engage legal counsel monthly | @<name> |
| Org reshuffle mid-program | M | M | document everything in initiative + ADRs | @<name> |

## Feature flag policy for this initiative

- **Prefix**: `init_042_*` (so all flags for this program share a namespace)
- **Owner of registry**: @<name>
- **Default cleanup window**: 90 days after 100% rollout

## Spec catalog (auto-populated)

| Spec | Phase | Status | Ships in |
|---|---|---|---|
| specs/active/003-foo.md | P1 | approved | 2026-12-15 |
| specs/active/004-bar.md | P1 | draft | TBD |
| ... | ... | ... | ... |

## Decision log (links to ADRs)

- ADR-007 — Data partition key choice — accepted 2026-07-12
- ADR-013 — Vendor selection — accepted 2026-08-03
- ADR-019 — Cutover strategy — accepted 2026-09-22

## Metrics tracked

- Primary: <metric, source, target>
- Secondary: <metric, source, target>
- Guardrails: <metric thresholds that auto-pause the initiative>

## Communication cadence

- Weekly: stakeholder digest (Slack #initiative-042)
- Monthly: exec readout (with execs + sponsor)
- Quarterly: OKR review + roadmap re-cut

## Review history

- 2026-09-01: P0 → P1 transition approved
- 2026-12-15: P1 50% milestone; on track
- ...
