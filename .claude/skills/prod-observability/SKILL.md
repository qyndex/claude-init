---
name: prod-observability
description: Scaffold the PRODUCTION observability + alerting + notification stack into a shipped app — OTEL collector, Sloth SLO burn-rate rules, synthetic monitor, Alertmanager routing, Sentry release tracking. Distinct from the `observability` skill (which emits telemetry in app code) — this gives that telemetry a destination + makes SLOs fire alerts. Round 12 A.
when_to_use: A spec has a `## SLOs` section and is about to ship to prod; user says "add monitoring", "wire alerting", "set up observability", "SLO alerts", "page on breach", "uptime monitoring"; the release agent preparing first prod deploy.
model: sonnet
disable-model-invocation: false
last_verified: 2026-05-28
---

# Production Observability

## Mandate

The `observability` skill makes the app EMIT logs/metrics/traces. This skill gives them a HOME and makes the SLO actually fire. The gap it closes: `slo.yml` declares burn-rate thresholds that, without this, nothing evaluates at runtime.

## What it scaffolds (from `templates/observability/`)

| Template | Drops to | Purpose |
|---|---|---|
| `otel-collector.yaml` | `deploy/otel-collector.yaml` | app OTLP → collector → Tempo/Prometheus/Loki (swappable) |
| `slo-gen.sh` (script) | runs at ship time | compiles `slo.yml` → Prometheus multi-burn-rate rules (Sloth) |
| `synthetic-monitor.yml` | `.github/workflows/` | Playwright critical journey vs PROD every 5 min |
| `alertmanager.yaml` | `deploy/alertmanager.yaml` | severity routing → PagerDuty (page) + Slack + hotfix dispatch |
| `sentry-release.sh` | `scripts/` | release tag + source maps → error maps to commit/PR |

## Procedure

1. Read the spec's `## SLOs` + `## Rollout` sections + `slo.yml`.
2. Copy the 5 templates into the shipped repo (substitute `service`, `PROD_URL`, backend endpoints).
3. Run `slo-gen.sh` → commit `deploy/prometheus-slo-rules.yaml` (this is the #1 thing — turns SLO doc into enforcement).
4. Wire the app SDK: `OTEL_EXPORTER_OTLP_ENDPOINT` → collector; Sentry init with `release` + `environment` + `spec.id` tag.
5. Set repo variables: `PROD_URL`, `PROM_URL`, `PROM_REMOTE_WRITE`, `TEMPO_ENDPOINT`, `LOKI_ENDPOINT`, `PUSHGATEWAY_URL`; secrets: `PAGERDUTY_ROUTING_KEY`, `SLACK_WEBHOOK_URL`, `SENTRY_AUTH_TOKEN`, `GH_DISPATCH_PAT`.
6. Add the `@synthetic` tag to the read-only critical journey in `e2e/`.
7. Verify: a deliberate test breach (raise error rate in staging) → SLO rule fires → Alertmanager pages + dispatches → hotfix pipeline opens an issue.

## The correlation chain (Round 12 D)

`trace_id` (W3C traceparent) → service spans → log lines (shared trace_id) → `release=<SHA>` (Sentry tag + OTEL `service.version`) → commit (Sentry suspect-commits) → spec (`spec.id` OTEL resource attr + `github_issue`). Click a prod error → land on the introducing PR.

## How it feeds the hotfix pipeline

Alertmanager `severity:page` → webhook → GitHub `repository_dispatch: prod-alert` → `hotfix-ingest.yml` → `hotfix-to-task.sh` → top-of-queue task + hotfix issue → autonomous fix → PR. **This skill creates the alert source the hotfix loop consumes.**

## Hard rules

- **SLO must be enforced, not documented.** If `slo-gen.sh` didn't run, the SLO is vapor.
- **Synthetic journeys are read-only.** Never mutate prod data in a monitor.
- **Page only on `severity:page`.** SEV3/4 → Slack ticket, not a wake-up.
- **Backend is swappable.** App emits OTLP; only the collector's exporter block changes per backend.
- **Source maps + release tags are non-negotiable** for prod JS/TS — without them, errors are unreadable minified stacks.

## References

- OTEL Collector: https://opentelemetry.io/docs/collector/configuration/
- Sloth (SLO → Prometheus): https://sloth.dev/
- Multi-window multi-burn-rate: Google SRE Workbook ch.5
- Sentry releases: https://docs.sentry.io/product/releases/

## Done means

- `deploy/prometheus-slo-rules.yaml` committed (SLO enforced)
- Collector + Alertmanager configs in `deploy/`
- Synthetic monitor workflow running every 5 min
- Sentry release tracking in the ship pipeline
- A test breach demonstrably pages + opens a hotfix
