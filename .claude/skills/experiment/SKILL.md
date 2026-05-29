---
name: experiment
description: A/B test design — hypothesis, MDE, sample size, primary/guardrail metrics, significance gate. Different from flag-rollout (which gradually exposes to ALL users). An experiment runs two variants in parallel to learn which is better.
when_to_use: "User says \"A/B test\", \"experiment\", \"does this improve <metric>\", \"split test\". Spec template's `## Rollout` section sets `flag.type: experiment`."
allowed-tools: Read, Glob, Grep, Edit, Write, WebSearch, WebFetch
model: opus
disable-model-invocation: true
---

# Experiment

A/B/n testing discipline. Don't ramp blind — measure.

## When experiment > flag-rollout

- You don't know if the change is positive
- A guardrail metric could regress (engagement, revenue, support tickets)
- You need statistical evidence to defend the decision

## When flag-rollout > experiment

- The change is correct by definition (security fix, bug fix, deprecated path removal)
- The new path is mandated (compliance, regulatory)
- Engagement/revenue impact is known from prior research

## Process

1. **Hypothesis** — "Adding social proof on checkout will increase conversion rate from 3.2% to ≥ 3.5% (Δ ≥ 0.3pp)."
2. **Primary metric** — what you're trying to move (must be a single number). conversion_rate, time_to_signup, CSAT.
3. **Guardrail metrics** — must not regress. revenue_per_visitor, page_load_time, support_ticket_rate.
4. **MDE** (minimum detectable effect) — smallest change worth detecting (Δ = 0.3pp).
5. **Sample size** — calculate from MDE + baseline + power (default 80% / α=0.05). Use a calculator (statsig, Eppo, internal).
6. **Variants** — control (current) vs. treatment(s). 50/50 or N-way.
7. **Allocation** — flag-provider segments users into variants (sticky by user_id).
8. **Run duration** — until sample size reached OR `max_duration` (default 4 weeks).
9. **Stop early only on guardrail violation** (auto-rollback) — never on primary metric (avoid peeking bias).
10. **Decision** — at sample size, run significance test:
    - Primary significantly improved + no guardrail regression → ship variant
    - Primary not significant → ship neither (status quo) OR test a stronger variant
    - Guardrail regressed → kill experiment immediately
11. **Document** — `.claude/memory/decisions/<date>-experiment-<id>.md` with results, plot, decision.

## Hard rules

- **Pre-register the analysis plan.** Write the decision criteria BEFORE seeing data. No peeking. No HARKing.
- **Don't analyze every day.** Use sequential testing if you must (Bayesian bandits / SPRT). Otherwise wait for sample size.
- **Guardrails are veto.** A 0.5pp lift in primary doesn't justify a 2pp regression in retention.
- **Run for at least 1 full week.** Daily/weekly cycles confound short experiments.
- **Sticky assignment.** A user sees the same variant every visit. Reassignment breaks the experiment.

## Output

```
experiments/<id>-<slug>/
  hypothesis.md
  sample-size-calc.md
  pre-registration.md       (committed BEFORE results)
  results/
    raw.csv
    analysis.ipynb
    plot.png
  decision.md
```

## References

- Trustworthy Online Controlled Experiments — Kohavi, Tang, Xu (the bible)
- Eppo / Statsig / GrowthBook docs on sequential testing
- Effective sample size calculators: https://www.evanmiller.org/ab-testing/sample-size.html
