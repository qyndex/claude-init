---
# ML/AI feature spec template — Round 8 F.
#
# Use INSTEAD of the regular spec template when the feature involves shipping
# ML/AI capability to customers. The factory is AI-native (uses Claude) but
# when it SHIPS AI features, those need guardrails the factory doesn't impose
# on itself.

id: <NNN>
slug: <kebab-case-slug>
status: draft
spec_type: ml
owner: "@<person>"
human_owner: "@<person>"
created: YYYY-MM-DD

# Standard spec fields apply
objective: KR-2026Q3-XX
initiative:
service_tier: T2

# ─── ML-specific fields ──────────────────────────────────────────────
ml:
  capability: <classification | generation | embedding | retrieval | ranking | agent>
  model_provider: <anthropic | openai | bedrock | self-hosted>
  model_id: <claude-sonnet-4-6 | gpt-5 | etc.>
  model_version_pinned: true     # NEVER use "latest" in prod
  fallback_model: <if primary unavailable>

  # Training data lineage
  training_data:
    sources: ["s3://..."]
    snapshot_at: YYYY-MM-DD
    pii_scrubbed: true
    consent_documented: <ADR link>
    license_compatibility_checked: true

  # Evaluation set — REQUIRED before prod
  eval_set:
    path: eval/<spec-id>/  # versioned in repo
    size: 200              # minimum 100 examples for meaningful eval
    labeled_by: "@<person> + 2 reviewers"
    last_refreshed: YYYY-MM-DD
    # Composition
    composition:
      golden_path: 50%      # typical successful query
      edge_cases: 30%       # unusual but valid input
      adversarial: 15%      # prompt injection, jailbreaks
      pii_redact_check: 5%  # confirm output doesn't leak PII

  # Quality bars (per metric)
  acceptance:
    primary_metric: <accuracy | f1 | bleu | rouge | human-rated>
    primary_threshold: 0.85
    drift_alert_pct: 5      # auto-alert if metric drops 5pp vs baseline
    latency_p95_ms: 800
    cost_per_query_cents: 0.5
    refusal_rate_max_pct: 2  # % of legitimate queries the model refused

  # Safety guardrails — REQUIRED for any user-facing AI
  safety:
    prompt_injection_filter: true   # detect "ignore previous instructions" et al.
    output_filter: true              # detect PII, hate speech, illegal content in output
    rate_limit_per_user_min: 60
    audit_log: true                  # log every input + output for 90d
    human_in_loop_for: ["high-risk-action-1"]  # e.g., financial transactions
---

# ML Spec <NNN>: <Title>

## Problem statement

> Same as regular spec.

## ML capability

What the model does: <classification | generation | embedding | ranking | etc.>

## Why ML (vs deterministic)

- ...
- ...

## User journey

1. User does X
2. Input goes through PII filter
3. Model receives prompt template `<...>`
4. Output goes through safety filter
5. User sees Y

## Acceptance criteria

Each criterion testable against the eval set:

1. **AC-1**: ≥85% accuracy on golden-path examples
2. **AC-2**: 100% refusal on adversarial prompt-injection examples
3. **AC-3**: 0 PII leaks across all 200 eval examples
4. **AC-4**: p95 latency <800ms
5. **AC-5**: cost per query <0.5 cents

## Rollout

```yaml
flag:
  name: ml_<feature>
  default: false
ramp_plan:
  - stage: staff_on
    wait: 7d
    exit_gate: "0 prompt-injection bypasses; <2% refusal rate"
  - stage: canary
    pct: 1
    wait: 7d
    exit_gate: "primary_metric >= 0.85; latency p95 < 800ms; no PII leaks"
  - stage: ramp
    pct: 10
    wait: 7d
  - stage: full
    pct: 100

auto_rollback_threshold:
  primary_metric_drop_pct: 5   # ↓5pp = pull
  cost_per_query_increase_pct: 50
  latency_p95_increase_pct: 100
  pii_leak_count: 1            # ZERO tolerance
```

## Eval gate (CI requirement)

Every PR that touches:
- `models/`, `prompts/`, `eval/`
- The model_id or model_version_pinned field of this spec

…runs `/ml-eval <spec-id>`. The eval must pass before merge.

## Drift detection

Daily Cloud Routine:
- Pull last 24h of production samples (anonymized)
- Re-score against current eval set
- If primary_metric drops >5pp from baseline → page on-call

## What we'll do when it fails

| Failure mode | Response |
|---|---|
| Primary metric drops below threshold | Flag-kill via `/flag kill ml_<feature>`; investigate via offline replay |
| Prompt-injection bypass discovered | Add example to eval; pull feature; ADR documenting the new defense |
| PII leak detected | Immediate kill + customer notification per privacy playbook |
| Cost spikes | Investigate prompt change / model change; rollback to prior version |

## References

- Eval set: `eval/<spec-id>/`
- Training data lineage: <ADR>
- Drift monitoring dashboard: <URL>
- Safety review: <ADR>
