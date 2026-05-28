---
id: <NNN>
slug: <kebab-case-slug>
status: draft   # draft | review | approved | shipped | paused | dropped | superseded | abandoned
owner: "@claude"
human_owner: "@<person>"   # the human accountable, even when Claude drafts
created: YYYY-MM-DD
updated: YYYY-MM-DD
supersedes:        # optional, id of prior spec
superseded_by:     # optional, id of new spec
complexity: M     # S | M | L | XL  (XL → consider an initiative instead)
objective: KR-2026Q3-04   # KR id from OKRs.md (or KR-COMPLIANCE / KR-PLATFORM synthetic)
initiative:        # optional, parent initiative id
service_tier: T2   # T1 (mission-critical) | T2 (important) | T3 (internal-only)
feedback_refs: []  # FB-IDs from .claude/memory/feedback/ that drove this spec (Round 7 C)
github_issue:      # auto-populated by tasks-to-issues.sh — the projected issue number (Round 11)
---

# Spec <NNN>: <Title>

## Problem statement

> Who is affected, what's broken or missing, and why does it matter?

<2-4 sentences>

## Goals

In scope:
- ...
- ...

## Non-goals

Explicitly out of scope (state to prevent drift):
- ...
- ...

## User stories

- As a `<role>` I want `<capability>` so that `<outcome>`.
- As a `<role>` I want `<capability>` so that `<outcome>`.

## Acceptance criteria

Each criterion is testable, measurable, observable. Number them so tasks can reference.

1. **AC-1**: <observable behavior, e.g., "After clicking Submit on an empty form, the email field shows the error 'Email is required' within 200ms.">
2. **AC-2**: ...
3. **AC-3**: ...

## Constraints

- **Performance**: p95 < 200ms for the read path; p95 < 500ms for the write path
- **Security**: must follow `.claude/skills/security-guard/SKILL.md` checklist
- **Compatibility**: backwards-compatible with API v1 callers
- **Compliance**: <SOC2 / HIPAA / GDPR / N/A>
- **Accessibility**: WCAG 2.1 AA

## Rollout (required for non-trivial features — drives flag-rollout skill)

```yaml
flag:
  name: <namespace>_<feature>           # e.g., init_042_checkout_v2
  type: rollout | kill-switch | permission | experiment
  default: false                         # default-OFF unless explicitly justified
  provider: openfeature | posthog | launchdarkly | unleash | none
  depends_on: []                         # other flags that must be 100% before this can ramp
  owner: "@<person>"                     # human flag owner

ramp_plan:
  - stage: staff_on          # internal dogfooding
    cohort: staff
    wait: 24h
    exit_gate: "zero errors; dogfooding feedback positive"
  - stage: canary
    pct: 1
    wait: 24-48h
    exit_gate: "error_rate <= baseline + 0.1pp; p95 within budget"
  - stage: ramp
    pct: 10
    wait: 48-72h
    exit_gate: "error_rate <= baseline + 0.05pp; primary metric trending"
  - stage: half
    pct: 50
    wait: 3-7d
    exit_gate: "success_metric significant"
  - stage: full
    pct: 100
    wait: 7d observation
    exit_gate: "no regression over 1 week"

success_metric:
  name: <metric name>                    # e.g., conversion_rate
  baseline: <number>
  target: <number>
  source: <dashboard URL or query>

auto_rollback_threshold:
  error_rate: ">= 1% for 5 min"
  p95_latency: ">= 2x baseline for 10 min"
  custom: ""                             # service-specific guardrail metric

cleanup_after: 30d                       # remove the flag from code N days after 100%
```

## SLOs (for any service-level change)

```yaml
service_tier: T2                         # T1 / T2 / T3 — drives gate strictness
slos:
  availability: 99.9%                    # error budget = 0.1%
  latency_p95: 200ms
  latency_p99: 500ms
  error_budget_burn_alert: "2% in 1h | 10% in 6h"   # multi-window burn-rate
runbook: docs/runbooks/<service>.md
dashboards:
  - <grafana / datadog URL>
on_call_rotation: "@<team-handle>"
```

## Open questions

Mark unresolved questions with `[OQ]`. The spec is **not approved** until none remain. Use `/clarify` to walk through them.

- [OQ-1] ...
- [OQ-2] ...

## Dependencies

- Depends on spec: <id>
- Blocks spec: <id>
- External: <service / library / API>

## Out of scope (will be picked up later)

- ...

## Change history

Track material scope changes after `status: approved`. Each entry is a single line.

```
- YYYY-MM-DD | @<author> | <kind> | <one-line reason>
  # kind: scope-grow | scope-cut | ac-changed | rollout-changed | superseded
```

Examples:
```
- 2026-04-12 | @bob | scope-grow | added webhook delivery to AC-3 after legal review
- 2026-04-18 | @claude | rollout-changed | extended canary 24h→72h after p95 wobble
- 2026-05-02 | @bob | superseded | replaced by spec 087 (new auth model)
```

Why this matters: a 9-month feature accumulates 10+ scope changes that are otherwise lost to PR comments. Spec drift becomes invisible without an audit trail. `/spec-drift-check` reads this section + git log to detect silent regressions.

## References

- Issue/ticket: <url>
- Related ADR: ADR-XXXX
- External docs: <url>
