---
description: Manage quarterly OKRs (Objectives and Key Results). Author, update, close, and re-cut. The alignment anchor for all specs and initiatives.
argument-hint: "[draft <Qn>] | [status] | [close <kr-id>] | [cut]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
disable-model-invocation: true
---

# /okrs — Quarterly Objectives + Key Results

## Sub-commands

### `/okrs status`
Default. Show current-quarter KRs with progress:
```
2026-Q3 — 18 days remaining

O1: Customers self-serve 90% of common questions
  KR-01  self-serve resolution rate 42→70%   today: 51%   pace: AHEAD
  KR-02  tickets/customer ≤ 0.4/mo           today: 0.62  pace: BEHIND
  KR-03  CSAT ≥ 4.4/5                         today: 4.1   pace: ON-TRACK

O2: Checkout reliability
  KR-04  failure rate 2.1→0.5%                today: 1.7%  pace: ON-TRACK
  KR-05  p95 latency ≤ 800ms                  today: 1.1s  pace: BEHIND

O3: Platform health
  ...
```

### `/okrs draft <Qn>`
Draft next-quarter OKRs. Interview-driven. Looks at:
- Currently in-flight initiatives needing KR continuation
- Themes from recent incidents (operations OKRs)
- Strategic asks from sponsors/execs
Writes to a `next-quarter` section in `OKRs.md`.

### `/okrs close <kr-id>`
Final disposition of a KR:
- shipped — target met
- partial — partial credit; document why
- missed — explicitly missed; surface learnings
- deprecated — context changed; archive
Updates `OKRs.md` with closing data; moves to `OKRs-archive/<year>-Q<n>.md` if closing the whole quarter.

### `/okrs cut`
Quarterly hard re-cut on the first business day of a new quarter:
1. Archive previous quarter to `OKRs-archive/`
2. Promote draft to current
3. Re-align all `initiatives/active/` to new KRs
4. Surface initiatives that no longer map to any KR (reconsider or close)
5. Surface specs in `specs/active/` whose `objective:` field now references closed KRs

## Hard rules

- **No spec ships without a KR.** Exceptions: ≤20 LOC bug fixes, security patches, and explicitly tagged `KR-COMPLIANCE` / `KR-PLATFORM`.
- **Don't auto-write KRs.** Always interview the user; OKRs are strategic, not generated.
- **Don't allow > 5 KRs per Objective.** If you have 7, you have too many; split or descope.
- **Targets must be numeric and measurable.** "Improve UX" is not a KR. "CSAT ≥ 4.4" is.

$ARGUMENTS
