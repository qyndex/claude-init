# Company / Team OKRs

> The top of the alignment stack. Specs reference KRs by ID via `objective:` frontmatter. Initiatives reference KRs in their `## Strategic context`.

**Cadence**: quarterly. Cut on the first business day of the quarter; review weekly; close on the last business day.

---

## Current quarter — 2026-Q3 (Jul 1 — Sep 30)

### O1: Customers can self-serve 90% of common questions
Strategic theme: support-cost reduction.

| KR | Target | Today | Owner | Active initiatives |
|---|---|---|---|---|
| KR-2026Q3-01 | Self-serve resolution rate from 42% → 70% | 51% | @sarah | initiative 042 |
| KR-2026Q3-02 | Support tickets per active customer ≤ 0.4/mo | 0.62 | @sarah | initiative 042 |
| KR-2026Q3-03 | CSAT for self-serve flow ≥ 4.4/5 | 4.1 | @sarah | initiative 042 |

### O2: Checkout reliability
Strategic theme: revenue protection.

| KR | Target | Today | Owner | Active initiatives |
|---|---|---|---|---|
| KR-2026Q3-04 | Checkout failure rate 2.1% → 0.5% | 1.7% | @alex | initiative 037 |
| KR-2026Q3-05 | p95 checkout latency ≤ 800ms | 1.1s | @alex | initiative 037 |

### O3: Platform health
Strategic theme: keep velocity sustainable.

| KR | Target | Today | Owner | Active initiatives |
|---|---|---|---|---|
| KR-2026Q3-06 | Tech-debt items >90 days old ≤ 10 | 18 | @platform | initiative 044 |
| KR-2026Q3-07 | Plugin-staleness >12 mo: 0 | 2 | @platform | initiative 044 |
| KR-2026Q3-08 | Spec drift findings/qtr ≤ 5 | 11 | @platform | initiative 044 |

---

## Next quarter — 2026-Q4 (draft, not yet cut)

(populate via `/okrs draft 2026-Q4`)

---

## Archive

Move quarters into `OKRs-archive/` once the quarter closes. Keep the last two quarters here for quick reference.

---

## How specs align

Every spec under `specs/active/` MUST have an `objective:` frontmatter field referencing a KR ID. If a spec doesn't fit any current KR, that's a signal — either:
1. The KR list is incomplete (propose one in next quarter's cut), OR
2. The spec is opportunistic and should be deferred or absorbed by an existing KR.

The `okr-align` skill (`.claude/skills/okr-align/SKILL.md`) checks this on every `/specify`.

## How initiatives align

Every initiative under `initiatives/active/` MUST link a KR in its `## Strategic context`. If multiple, the initiative is too broad — split it.

## Metrics that don't fit OKRs

Some metrics (security CVE count, on-call burden, deploy frequency) aren't OKRs — they're guardrails. They live in `slo.yml` and `.claude/memory/playbooks/oncall-handoff.md`, not here.
