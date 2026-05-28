---
description: View, update, promote, pause, or re-cut the roadmap. The Now/Next/Later view of initiatives. Anchored to OKRs; sourced from initiatives/.
argument-hint: "[status] | [promote <id>] | [pause <id> --until <date>] | [abandon <id> --reason <text>] | [cut]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
disable-model-invocation: true
---

# /roadmap — Initiative-level Now / Next / Later

## Sub-commands

### `/roadmap status` (default)
Prints the current `roadmap.md` Now/Next/Later view + per-initiative health (🟢🟡🔴) + critical-path issues. Reads:
- `roadmap.md` for the manual view
- `initiatives/active/*.md` for current health
- `OKRs.md` for KR alignment

### `/roadmap promote <id>`
Move an initiative from LATER → NEXT, or NEXT → NOW:
- Verifies KR alignment (skill: okr-align)
- Verifies dependencies are satisfied
- Surfaces required prerequisite work
- Updates `roadmap.md` + initiative frontmatter

### `/roadmap demote <id>` (Round 7 A)
Mirror of `promote`: move NOW → NEXT, or NEXT → LATER. For mid-quarter reprioritization driven by market signals or customer feedback. Updates `roadmap.md` + `roadmap/changelog.md` (Batch B); requires `--reason <text>`.

```bash
/roadmap demote 037 --reason "customer feedback pivots focus to retention"
```

### `/roadmap pause <id> --until <date>`
Pause an in-flight initiative (status → paused) with explicit resume date and rationale. Logs to:
- Initiative's `## Review history`
- `.claude/memory/decisions/<date>-pause-<id>.md`

### `/roadmap abandon <id> --reason <text>`
Move to abandoned with mandatory rationale. Triggers:
- Write decision record
- Close associated KRs if KR was solely served by this initiative
- **Delegates to `/pivot drop <id>` (Round 7 A)** for the full cascade (specs, plans, tasks, swarm streams, manifest, salvage candidates)
- For full retained-learnings extraction: chain to `/abandon <id>` (Round 7 D)

### `/roadmap reshuffle --from-feedback`  (Round 7 C)
Reads `.claude/memory/feedback/_triage-latest.md`; if top item carries `business_signal: churn-risk` + ARR > threshold + renewal < 60d, proposes:
1. `/roadmap demote` of a NOW initiative
2. `/roadmap promote` of a feedback-spawned initiative
3. Write an ADR explaining the swap

Sponsor approval is the gate; agent surfaces the swap, human signs off. **The "by Friday, priority 1" path.**

### `/roadmap cut`
Quarterly re-cut. Runs `/okrs cut` first, then:
1. Move shipped initiatives → archive
2. Promote NEXT → NOW based on remaining quarter capacity
3. Promote LATER → NEXT based on strategic priorities
4. Surface initiatives with no clear quarter assignment

## Health flags

- 🟢 on track: phase progress matches phase target_ship pace
- 🟡 at risk: behind pace ≤ 30% OR 1 critical risk open
- 🔴 off track: behind pace > 30% OR 2+ critical risks OR sponsor escalation
- ⏸️ paused: explicit pause status

## Output

```
Roadmap as of 2026-08-15

NOW (in flight)
  042 self-serve docs       P2/3  60%  🟢  @sarah
  037 checkout reliability  P1/2  40%  🟡  @alex   risk: vendor SLA
  044 platform debt         continuous   🟢  @platform

NEXT (Q4)
  051 mobile push           queued; depends on 037 P2 completion
  052 search v2             queued

LATER
  060 ML personalization
  061 multi-region failover
  062 white-label tenant

Issues
  - 037 vendor SLA risk → escalate to @alex this week
  - 051 NEXT readiness depends on 037 P2; trend is slipping
```

$ARGUMENTS
