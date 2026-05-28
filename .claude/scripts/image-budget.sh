#!/usr/bin/env bash
# Image generation budget gate — Round 9 D.
#
# Per-image cap: $0.10 hard
# Daily budget: $5 default (override via IMAGE_DAILY_BUDGET_USD)
# Tracking: .claude/state/image-spend.jsonl

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

mkdir -p .claude/state
LOG=".claude/state/image-spend.jsonl"

# Args: provider model slug est_cost_usd
PROVIDER="${1:-unknown}"
MODEL="${2:-unknown}"
SLUG="${3:-unnamed}"
EST_COST="${4:-0.04}"

PER_IMAGE_CAP=0.10
DAILY_BUDGET="${IMAGE_DAILY_BUDGET_USD:-5}"

# Per-image cap check
if awk "BEGIN { exit !($EST_COST > $PER_IMAGE_CAP) }"; then
  echo "✗ Per-image cap breached: \$${EST_COST} > \$${PER_IMAGE_CAP}"
  echo "  Either: pick a cheaper model OR raise IMAGE_DAILY_BUDGET_USD (per-image cap is hard)"
  exit 1
fi

# Daily budget check
today=$(date +%Y-%m-%d)
today_spent=$(grep "\"date\":\"$today\"" "$LOG" 2>/dev/null | jq -s '[.[].cost] | add // 0')
projected=$(awk "BEGIN { print $today_spent + $EST_COST }")

if awk "BEGIN { exit !($projected > $DAILY_BUDGET) }"; then
  echo "✗ Daily budget breached: \$${today_spent} + \$${EST_COST} = \$${projected} > \$${DAILY_BUDGET}"
  echo "  Wait for tomorrow OR raise IMAGE_DAILY_BUDGET_USD"
  exit 1
fi

# 80% alert
threshold_80=$(awk "BEGIN { print $DAILY_BUDGET * 0.8 }")
if awk "BEGIN { exit !($projected > $threshold_80) }"; then
  echo "⚠ Daily image budget at $(awk "BEGIN { printf \"%.0f\", ($projected / $DAILY_BUDGET) * 100 }")%"
fi

# Log the spend
jq -nc \
  --arg date "$today" \
  --arg ts "$(date -Iseconds)" \
  --arg provider "$PROVIDER" \
  --arg model "$MODEL" \
  --arg slug "$SLUG" \
  --argjson cost "$EST_COST" \
  '{date: $date, ts: $ts, provider: $provider, model: $model, slug: $slug, cost: $cost}' \
  >> "$LOG"

echo "✓ Approved: $PROVIDER/$MODEL → $SLUG (\$${EST_COST}); today's spend: \$$(awk "BEGIN { printf \"%.4f\", $projected }")"
