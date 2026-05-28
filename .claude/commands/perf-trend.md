---
description: Track perf metrics month-over-month. Stores PR-time baselines in .claude/memory/perf-baselines/, compares current to historical, surfaces regressions.
argument-hint: "[--metric <name>] [--window 30d|90d|180d]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /perf-trend — Catch slow regressions

A p95 of 150ms → 250ms over 6 months won't trip any single PR's gate. This skill compares against historical baselines and surfaces the trend.

```bash
metric="${1:-p95_latency}"
window="${2:-90d}"

baseline_dir=".claude/memory/perf-baselines"
mkdir -p "$baseline_dir"

# 1. Get current measurement
current=$(npx lighthouse-ci collect 2>/dev/null | jq -r ".[\"$metric\"]" 2>/dev/null \
  || curl -s http://staging/healthcheck-perf | jq -r ".$metric" 2>/dev/null \
  || echo "unavailable")

# 2. Load historical baselines
history=$(ls -t "$baseline_dir"/*.json 2>/dev/null | head -10)

# 3. Compare
echo "Current $metric: $current"
echo
echo "History (last 10 measurements):"
for h in $history; do
  date=$(basename "$h" .json)
  val=$(jq -r ".$metric" "$h" 2>/dev/null)
  echo "  $date: $val"
done

# 4. Compute trend
oldest=$(echo "$history" | tail -1)
if [ -n "$oldest" ]; then
  oldval=$(jq -r ".$metric" "$oldest" 2>/dev/null)
  if [ -n "$oldval" ] && [ "$oldval" != "null" ]; then
    delta=$(awk "BEGIN {print ($current - $oldval) / $oldval * 100}")
    echo
    echo "Trend over $window: ${delta}%"
    if (( $(awk "BEGIN {print ($delta > 20)}") )); then
      echo "⚠ REGRESSION: $metric has degraded > 20% over $window"
      echo
      echo "Consider /bisect-perf $metric $(git log --before='$window' --format=%h | head -1)..HEAD"
    fi
  fi
fi

# 5. Save today's measurement
echo "{\"$metric\": $current, \"sha\": \"$(git rev-parse HEAD)\", \"date\": \"$(date -Iseconds)\"}" \
  > "$baseline_dir/$(date +%Y-%m-%d).json"
```

## Hard rules

- **Compare across windows, not just PRs.** A single PR within budget can still trend a service into trouble.
- **Save baselines per-commit.** When you bisect a regression, you need historical data with SHAs.
- **Alert at 20% degradation.** Adjust per service tier; T1 services should alert sooner.

$ARGUMENTS
