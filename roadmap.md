# Roadmap

> Now / Next / Later view of in-flight and queued initiatives. Updated via `/roadmap update`. Cuts via `/roadmap cut` at the start of each planning cycle.

**Last updated**: YYYY-MM-DD by @<who>
**Planning cadence**: weekly micro-update, monthly re-rank, quarterly re-cut

---

## NOW (in flight, this quarter)

| Initiative | KR | Phase | % done | Health | Owner |
|---|---|---|---|---|---|
| [042 — Self-serve docs](initiatives/active/042-self-serve.md) | KR-2026Q3-01 | P2 of 3 | 60% | 🟢 on track | @sarah |
| [037 — Checkout reliability](initiatives/active/037-checkout.md) | KR-2026Q3-04 | P1 of 2 | 40% | 🟡 at risk | @alex |
| [044 — Platform debt paydown](initiatives/active/044-debt.md) | KR-2026Q3-06 | continuous | n/a | 🟢 | @platform |

## NEXT (queued for next quarter)

| Initiative | KR | Why now | Sponsor |
|---|---|---|---|
| [051 — Mobile push](initiatives/active/051-push.md) | TBD (Q4) | EU launch requires push | @product |
| [052 — Search v2](initiatives/active/052-search.md) | TBD (Q4) | search relevance complaints up 30% | @search |

## LATER (parked; not yet committed)

| Initiative | Notes |
|---|---|
| 060 — ML personalization | needs Q1 2027 platform readiness |
| 061 — Multi-region failover | post-launch SLO |
| 062 — White-label tenant | sales pipeline contingent |

## ABANDONED / SUPERSEDED

| Initiative | Status | Replaced by |
|---|---|---|
| 015 — Legacy reporting API | abandoned 2026-04 | 037 (different cut-line) |

---

## Tactical view (specs in flight this week)

For per-feature granularity, see `tasks/TASKS.md`. The roadmap is for *initiative-level* tracking.

## Velocity tracking

- **This quarter target**: ship 6 initiatives total (3 NOW + start 2 from NEXT)
- **Pace**: 2 shipped, 1 at risk, 3 in flight → 60% confidence

## Health legend
- 🟢 on track for target ship date
- 🟡 at risk (mitigations active; weekly review)
- 🔴 off track (escalated; replan or descope decision pending)
- ⏸️ paused (sponsor decision; explicit resume date)

## Roadmap-change protocol

The roadmap changes only via:
1. `/roadmap promote <id>` — pull a LATER item into NEXT
2. `/roadmap cut` — quarterly hard re-cut (new quarter; reset)
3. `/roadmap pause <id> --until <date>` — pause an in-flight initiative
4. `/roadmap abandon <id>` — move to abandoned with a written rationale

Ad-hoc edits without going through these commands are discouraged — they break the audit trail.
