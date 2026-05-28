---
name: flag-rollout
description: Phased flag rollout from default-OFF to 100%, with auto-rollback discipline.
metadata:
  type: playbook
---

# Playbook: Phased flag rollout

> The "phased delivery in prod" backbone. Ship default-OFF, ramp through cohorts, auto-rollback on metric breach, clean up.

## Stages

```
default-OFF (post-merge)
  ↓ (zero errors deploy verified)
staff ON (internal dogfooding)
  ↓ (1-2 days; positive feedback)
1% canary
  ↓ (24-48h; error_rate within threshold)
10%
  ↓ (48-72h; primary metric ≥ baseline)
50%
  ↓ (3-7 days; significance reached if experiment)
100%
  ↓ (1 week observation)
flag cleanup (delete from code + provider)
```

## Each stage's gate

| Stage | Gate (mechanical) |
|---|---|
| default-OFF | flag exists in provider, code deployed, no errors |
| staff ON | 24h, zero new errors with staff cohort |
| 1% | 24-48h, `error_rate ≤ baseline + 0.1pp`, `p95 ≤ budget` |
| 10% | 48-72h, `error_rate ≤ baseline + 0.05pp`, primary metric trending |
| 50% | 3-7 days, `success_metric ≥ baseline` significant |
| 100% | 1 week, no regression |
| cleanup | T+cleanup_after, flag-cleanup skill runs |

## Auto-rollback thresholds

Per spec's Rollout section:
```yaml
auto_rollback_threshold:
  error_rate: ">= 1% for 5 min"
  p95_latency_increase: ">= 2x baseline for 10 min"
  custom_metric: "<metric> <operator> <value> for <window>"
```

When breached:
1. flag-kill skill kicks in (no human approval needed during active page)
2. Incident opened
3. Postmortem within 24h

## Walk-through (the canonical 6-month feature)

**Week 0**: Spec approved; rollout section completed.
**Week 1**: First implementation tasks complete; PRs merged; flag default-OFF in code.
**Week 2**: Deploy. Flag exists in provider, default-OFF. Verify code path is exercised under staff-on.
**Week 3**: Staff ON. Dogfooding ~50 people. Feedback collected via Slack.
**Week 4**: Canary 1%. Monitor 24h. If green: 10%.
**Week 5**: Ramp through 10% → 50%.
**Week 6**: 50% for a week to allow significance (if experiment).
**Week 7-8**: 100%. Observation window.
**Week 12** (or whenever cleanup_after hits): flag-cleanup skill removes the conditional.

## Hard rules

- **Default-OFF unless proven otherwise.** Every flag starts here.
- **Don't skip stages.** Each is its own learning.
- **Wait the window.** Time-based bugs surface after time, not request count.
- **Cleanup is part of done.** A 100% flag still in code is debt.
- **Don't ramp two related flags simultaneously.** Sequence (DB → API → UI).

## Anti-patterns

- "It's a small change, ship at 100%." → no it isn't.
- "1% looks fine, jump to 50%." → bugs surface at 10-30%, not at 1%.
- "Cleanup later." → later = never. Schedule it.
- "Multiple flags at once." → blast radius compounds.

## References

- `.claude/skills/flag-rollout/SKILL.md` — the skill that drives this
- `.claude/skills/flag-cleanup/SKILL.md` — cleanup automation
- Martin Fowler "Feature Toggles" (https://martinfowler.com/articles/feature-toggles.html)
