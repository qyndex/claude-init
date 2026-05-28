# Production observability — the shipped app

Round 12. The SHIPPED application's observability + alerting + notification + the prod→hotfix loop. Distinct from [OBSERVABILITY.md](OBSERVABILITY.md) (which traces the *factory's agents*).

## The chain, end to end

```
prod app  ──OTLP──▶  otel-collector  ──▶  Tempo (traces) / Prometheus (metrics) / Loki (logs)
                                              │
slo.yml ──slo-gen.sh──▶ prometheus-slo-rules.yaml ──▶ Prometheus evaluates burn-rate
                                              │
                              breach ──▶ Alertmanager ──severity:page──▶ PagerDuty (wake human)
                                              │                         └─webhook─▶ repository_dispatch: prod-alert
synthetic-monitor.yml (*/5m vs PROD) ─fail──┘                                          │
                                                                                       ▼
                                                              hotfix-ingest.yml / hotfix-sentry-poll.yml
                                                                                       │
                                                              hotfix-to-task.sh (dedup + top-of-queue)
                                                                                       │
                                                       TASKS.md priority:hotfix  +  hotfix issue (write-only)
                                                                                       │
                                              debugger Phase 0 → self-heal → collect-evidence → PR (Closes #hotfix)
                                                                                       │
                                                              human reviews + merges → DONE → flag@100 → SHIPPED
```

## The two planes (don't conflate)

| | Factory observability | Prod-app observability |
|---|---|---|
| **Doc** | OBSERVABILITY.md | this doc |
| **Subject** | Claude Code agents | the shipped product |
| **Backend** | Langfuse (cloud) | OTEL collector → Tempo/Prometheus/Loki |
| **Signal** | agent cost, tokens, tool calls | app errors, latency, SLO burn, uptime |
| **Alert** | cost-cap gate | SLO burn-rate → PagerDuty → hotfix |

## Setup (per shipped project)

1. **Scaffold** — invoke the `prod-observability` skill, which copies `templates/observability/*` into the project.
2. **Pick a backend** — default OSS: deploy `otel-collector.yaml` + Prometheus + Tempo + Loki + Grafana. (Datadog alt: promote the `datadog` MCP, swap the collector exporters.)
3. **Enforce SLOs** — run `bash .claude/scripts/slo-gen.sh` → commit `deploy/prometheus-slo-rules.yaml`. **This is the load-bearing step** — without it the SLO is a doc nobody evaluates.
4. **Route alerts** — deploy `alertmanager.yaml`; set `PAGERDUTY_ROUTING_KEY`, `SLACK_WEBHOOK_URL`, `GH_DISPATCH_PAT`.
5. **Synthetic monitor** — add `synthetic-monitor.yml`; tag the read-only critical journey `@synthetic`; set `PROD_URL`.
6. **Release tracking** — call `sentry-release.sh` from the ship pipeline; set `SENTRY_AUTH_TOKEN`/`ORG`/`PROJECT`.
7. **Correlation** — app SDK init sets W3C traceparent + Sentry `release=<SHA>` + `spec.id`. Now error → trace → commit → spec → PR.

## The Alertmanager → repository_dispatch relay

Alertmanager's `webhook_configs` POSTs its own JSON; GitHub `dispatches` wants `{event_type, client_payload}`. A tiny relay maps them. Minimal Cloudflare Worker / Lambda:

```js
export default { async fetch(req, env) {
  const a = await req.json();
  const al = a.alerts?.[0] ?? {};
  return fetch(`https://api.github.com/repos/${env.GH_REPO}/dispatches`, {
    method: "POST",
    headers: { Authorization: `token ${env.GH_PAT}`, "Accept": "application/vnd.github+json" },
    body: JSON.stringify({ event_type: "prod-alert", client_payload: {
      source: "alertmanager",
      severity: al.labels?.severity === "page" ? "SEV1" : "SEV2",
      fingerprint: al.fingerprint,
      title: al.annotations?.summary ?? "SLO burn",
      runbook: al.annotations?.runbook,
    }}),
  });
}}
```
(If you run Datadog, its native GitHub webhook can target the dispatch endpoint directly — no relay.)

## Hard rules

- **SLO must be machine-evaluated.** `slo-gen.sh` output committed, Prometheus loading it, or the SLO is vapor.
- **Synthetic = read-only.** A monitor must never mutate prod.
- **Page only severity:page.** SEV3/4 → Slack ticket.
- **Source maps + release tags are mandatory** for prod JS/TS.
- **The factory never auto-merges a hotfix.** It diagnoses + fixes + opens a PR with evidence; a human merges (see hotfix autonomy in incident-response.md).

## See also

- `.claude/skills/prod-observability/SKILL.md` — the scaffolder
- `.claude/memory/playbooks/incident-response.md` — the human IC track that runs in parallel
- `slo.yml` — declarative SLOs (now enforced via slo-gen.sh)
- the hotfix pipeline: `hotfix-sentry-poll.yml`, `hotfix-ingest.yml`, `hotfix-to-task.sh` (Round 12 B/C/D)
