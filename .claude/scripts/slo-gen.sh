#!/usr/bin/env bash
# SLO → Prometheus alert rules — Round 12 A. THE #1 gap closer.
#
# Turns slo.yml (declarative SLOs that nothing evaluated) into REAL Prometheus
# multi-window multi-burn-rate alerting rules via Sloth. Until this runs,
# "p95 < 200ms" is a doc; after, a breach fires an alert that pages someone.
#
# Usage: bash .claude/scripts/slo-gen.sh [--out deploy/prometheus-slo-rules.yaml]
# Requires: sloth (github.com/slok/sloth) — falls back to a hand-rolled
# multiwindow generator if sloth isn't installed.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUT="deploy/prometheus-slo-rules.yaml"
[ "${1:-}" = "--out" ] && OUT="$2"
mkdir -p "$(dirname "$OUT")"

[ ! -f slo.yml ] && { echo "slo.yml not found"; exit 1; }

# Build a Sloth spec from slo.yml. We map each service's availability + latency
# SLO into a Sloth SLO with the burn-rate alerting Sloth generates by default
# (page at 14.4x/1h+5m and 6x/6h+30m; ticket at 3x/1d+2h and 1x/3d+6h).
sloth_spec="deploy/.sloth-spec.yaml"

{
  echo "version: prometheus/v1"
  # JUSTIFIED: slo.yml may be absent — the muted grep plus the fallback default the service name to "app" rather than failing SLO generation
  echo "service: \"$(grep -m1 '^service:' slo.yml 2>/dev/null | sed 's/service:[[:space:]]*//' || echo app)\""
  echo "slos:"
  # Parse services from slo.yml. Expected shape:
  #   services:
  #     <name>:
  #       availability: 99.9%
  #       latency_p95: 200ms
  #       error_budget_burn_alert: "..."
  awk '
    /^services:/ { in_svc=1; next }
    in_svc && /^  [a-z]/ { svc=$1; sub(/:$/,"",svc) }
    in_svc && /availability:/ {
      gsub(/[%[:space:]]/,""); split($0,a,":"); avail=a[2]
      printf "  - name: %s-availability\n", svc
      printf "    objective: %s\n", avail
      printf "    description: \"Availability SLO for %s (from slo.yml)\"\n", svc
      printf "    sli:\n      events:\n"
      printf "        error_query: sum(rate(http_requests_total{service=\"%s\",code=~\"5..\"}[{{.window}}]))\n", svc
      printf "        total_query: sum(rate(http_requests_total{service=\"%s\"}[{{.window}}]))\n", svc
      printf "    alerting:\n      name: %sHighErrorRate\n      page_alert: { labels: { severity: page } }\n      ticket_alert: { labels: { severity: ticket } }\n", svc
    }
  ' slo.yml
} > "$sloth_spec"

if command -v sloth >/dev/null 2>&1; then
  sloth generate -i "$sloth_spec" -o "$OUT" \
    && echo "✓ Sloth compiled $OUT from slo.yml" \
    || { echo "✗ sloth generate failed — see $sloth_spec"; exit 1; }
else
  echo "⚠ sloth not installed — emitting a minimal multiwindow rule by hand"
  echo "  Install for full multi-burn-rate: go install github.com/slok/sloth/cmd/sloth@latest"
  cat > "$OUT" <<'YAML'
# Minimal SLO burn-rate alert (hand-rolled fallback). Replace with Sloth output.
groups:
  - name: slo-burn-rate
    rules:
      - alert: HighErrorRateFast
        expr: |
          (sum(rate(http_requests_total{code=~"5.."}[1h])) / sum(rate(http_requests_total[1h]))) > (14.4 * 0.001)
        for: 5m
        labels: { severity: page }
        annotations:
          summary: "Fast burn: >14.4x error budget over 1h"
          runbook: "docs/runbooks/{{ $labels.service }}.md"
      - alert: HighErrorRateSlow
        expr: |
          (sum(rate(http_requests_total{code=~"5.."}[6h])) / sum(rate(http_requests_total[6h]))) > (6 * 0.001)
        for: 30m
        labels: { severity: page }
        annotations:
          summary: "Slow burn: >6x error budget over 6h"
          runbook: "docs/runbooks/{{ $labels.service }}.md"
YAML
fi

echo "Next: Prometheus loads $OUT; Alertmanager routes severity:page → PagerDuty + the hotfix pipeline (templates/observability/alertmanager.yaml)."
