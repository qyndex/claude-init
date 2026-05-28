---
service: <service-name>
tier: T1 | T2 | T3
on_call: "@<rotation>"
escalation: ["@<L2>", "@<L3>", "@<exec>"]
slos: <path-to-slo.yml>
dashboards: ["<grafana>", "<datadog>"]
runbook_version: 1
last_reviewed: YYYY-MM-DD
---

# Runbook: <service>

## Identity

- **Owner**: @<team>
- **Tier**: T1 (mission-critical) | T2 (important) | T3 (internal-only)
- **Repos**: <list>
- **Dependencies**: <upstream services>
- **Dependents**: <downstream services>

## SLOs

| SLI | Target | Window | Burn-rate alert |
|---|---|---|---|
| Availability | 99.9% | 30d | 2% in 1h, 10% in 6h |
| Latency p95 | < 200ms | 5m | > 2x for 10m |
| Latency p99 | < 500ms | 5m | > 2x for 10m |
| Error rate | < 0.1% | 5m | > 0.5% for 5m |

## Common symptoms → mitigations

### Symptom: error rate spike
1. Check `/audit-trail` for recent deploys (last 30 min)
2. If recent deploy: `/rollback-flag <flag>` if gated, else `/rollback` previous binary
3. Check Sentry MCP for new exception classes
4. Check upstream dependency health
5. Page if not resolved in 15 min

### Symptom: p95 latency >2x baseline
1. Check load — recent traffic spike?
2. Check downstream services (cascading slowness?)
3. Check DB slow query log
4. Check resource limits (CPU/memory) for the service
5. Page if not resolved in 30 min

### Symptom: availability dropping
1. Check pods/instances health
2. Check load balancer
3. Check upstream certs (TLS expiry?)
4. Check DNS
5. Page immediately if <99% in 5min window

## Recent changes (auto-populated by deploy hook)

- 2026-05-28 14:23: deploy <sha> via @<who> (PR #123)
- 2026-05-27 11:05: flag `feat_checkout_v2` ramped 10→50% via @<who>
- ...

## Last 5 incidents

(Auto-populated from `.claude/memory/incidents/` filtered by this service tag.)

## Escalation policy

| Severity | Page | Wait | Escalate to |
|---|---|---|---|
| P1 | immediate | 0 | @oncall + @L2 |
| P2 | business hours | 15 min if no ack | @L2 |
| P3 | next business day | 4h if no ack | team channel |

## On-call duties

- Acknowledge pages within 5 min (P1), 15 min (P2)
- Status updates in #incidents every 15 min during P1
- Postmortem within 24h via `/lesson-learned --category incident`
- Hand off at end of shift via `/oncall-handoff`

## References

- Service spec: <path>
- Architecture diagram: <path>
- Dashboards: <urls>
- Source: `.claude/templates/runbook.md` v1
