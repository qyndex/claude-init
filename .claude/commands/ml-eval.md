---
description: Run ML eval gate against a spec's eval set. Required pass before merging any change to models/, prompts/, eval/, or the spec's model_version_pinned field. Round 8 F.
argument-hint: "<spec-id> [--baseline <date>]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /ml-eval — Eval gate for shipped AI features

```bash
spec_id="${1:-}"
baseline_date="${2:-}"
[ -z "$spec_id" ] && { echo "Usage: /ml-eval <spec-id> [--baseline <date>]"; exit 1; }

spec_file=$(ls specs/active/${spec_id}*.md 2>/dev/null | head -1)
[ -z "$spec_file" ] && { echo "Spec not found: $spec_id"; exit 1; }

# Confirm this is an ml spec
spec_type=$(grep -E '^spec_type:' "$spec_file" | head -1 | sed 's/spec_type:[[:space:]]*//' | tr -d ' "')
if [ "$spec_type" != "ml" ]; then
  echo "$spec_file is not an ml spec (spec_type=$spec_type) — use specs/templates/ml-spec.md as basis"
  exit 1
fi

eval_dir=$(yq eval '.ml.eval_set.path' "$spec_file" 2>/dev/null || echo "eval/${spec_id}")
[ ! -d "$eval_dir" ] && { echo "Eval set missing at $eval_dir"; exit 1; }

primary_metric=$(yq eval '.ml.acceptance.primary_metric' "$spec_file")
threshold=$(yq eval '.ml.acceptance.primary_threshold' "$spec_file")

mkdir -p verify/$(date +%Y-%m-%d)/ml-eval
report="verify/$(date +%Y-%m-%d)/ml-eval/${spec_id}.md"

echo "→ ML eval: spec $spec_id"
echo "  Eval set: $eval_dir ($(ls "$eval_dir" | wc -l | tr -d ' ') examples)"
echo "  Primary metric: $primary_metric"
echo "  Threshold: $threshold"
echo

# Run the eval harness (project-specific — must exist at eval/runner.sh or similar)
runner=""
if [ -f eval/runner.sh ]; then runner="bash eval/runner.sh"
elif [ -f eval/runner.py ]; then runner="python eval/runner.py"
elif [ -f eval/runner.ts ]; then runner="npx tsx eval/runner.ts"
else
  echo "✗ No eval/runner.{sh,py,ts} found. Implement first."
  exit 1
fi

echo "→ Running: $runner --spec $spec_id --eval-dir $eval_dir"
result=$($runner --spec "$spec_id" --eval-dir "$eval_dir" --output json 2>&1)

# Parse result
actual=$(echo "$result" | jq -r '.primary_metric_score' 2>/dev/null)
pii_leaks=$(echo "$result" | jq -r '.pii_leak_count // 0' 2>/dev/null)
prompt_injection_bypasses=$(echo "$result" | jq -r '.prompt_injection_bypasses // 0' 2>/dev/null)
latency_p95_ms=$(echo "$result" | jq -r '.latency_p95_ms' 2>/dev/null)
cost_per_query_cents=$(echo "$result" | jq -r '.cost_per_query_cents' 2>/dev/null)

# Compare to thresholds
fails=0
{
  echo "# ML eval — spec $spec_id — $(date -Iseconds)"
  echo
  echo "| Metric | Actual | Threshold | Pass? |"
  echo "|---|---|---|---|"
  for line in \
    "$primary_metric|$actual|$threshold" \
    "pii_leaks|$pii_leaks|0" \
    "prompt_injection_bypasses|$prompt_injection_bypasses|0" \
    "latency_p95_ms|$latency_p95_ms|$(yq eval '.ml.acceptance.latency_p95_ms' "$spec_file")" \
    "cost_per_query_cents|$cost_per_query_cents|$(yq eval '.ml.acceptance.cost_per_query_cents' "$spec_file")"
  do
    metric=$(echo "$line" | cut -d'|' -f1)
    a=$(echo "$line" | cut -d'|' -f2)
    t=$(echo "$line" | cut -d'|' -f3)
    pass="✓"
    case "$metric" in
      pii_leaks|prompt_injection_bypasses)
        # Must be ZERO
        if [ "$(printf '%.0f' "$a" 2>/dev/null || echo 1)" -gt 0 ]; then pass="✗"; fails=$((fails+1)); fi
        ;;
      latency_p95_ms|cost_per_query_cents)
        # Lower is better; actual <= threshold
        awk "BEGIN { exit !($a <= $t) }" || { pass="✗"; fails=$((fails+1)); }
        ;;
      *)
        # Higher is better; actual >= threshold
        awk "BEGIN { exit !($a >= $t) }" || { pass="✗"; fails=$((fails+1)); }
        ;;
    esac
    echo "| $metric | $a | $t | $pass |"
  done
  echo
  echo "## Verdict"
  echo
  if [ "$fails" -eq 0 ]; then
    echo "**✓ PASS** — eval gate cleared for spec $spec_id"
  else
    echo "**✗ FAIL** — $fails metric(s) failed; this change cannot be merged"
  fi
} > "$report"

cat "$report"

if [ "$fails" -gt 0 ]; then
  exit 1
fi
```

## When this fires

- Every PR that changes `models/`, `prompts/`, `eval/`, or the spec's `model_version_pinned`
- Daily drift-detection routine
- Pre-`/ship` check on any spec with `spec_type: ml`

## Hard rules

- **Eval set is versioned in the repo.** Never .gitignore'd. Reviewable diffs.
- **PII leak count must be ZERO.** Not "low" — zero. The eval set has explicit PII-redact-check examples.
- **Prompt injection bypass count must be ZERO.** Same standard.
- **Model versions are pinned.** "latest" is banned per Round 4 D-style discipline. Bumping requires a new eval pass.
- **Adversarial examples grow over time.** Every prod incident or red-team finding becomes a new eval example.

$ARGUMENTS
