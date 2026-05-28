---
description: Bisect a performance regression. Reads .claude/memory/perf-baselines/ for historical measurements, walks git history, finds the commit that introduced the regression.
argument-hint: "<metric> <good-sha>..<bad-sha>"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /bisect-perf — Find the commit that broke perf

```bash
metric="$1"     # e.g., p95_latency
range="$2"      # good-sha..bad-sha

baseline_dir=".claude/memory/perf-baselines"
good_sha=$(echo "$range" | cut -d. -f1)
bad_sha=$(echo "$range" | cut -d. -f3-)

# 1. Find the baseline for good_sha
good_val=$(grep -l "$good_sha" "$baseline_dir"/*.json 2>/dev/null | head -1 | xargs jq -r ".$metric")
bad_val=$(grep -l "$bad_sha" "$baseline_dir"/*.json 2>/dev/null | head -1 | xargs jq -r ".$metric")
echo "Good ($good_sha): $metric = $good_val"
echo "Bad  ($bad_sha): $metric = $bad_val"

# 2. Git bisect — at each step, run the benchmark
git bisect start "$bad_sha" "$good_sha"

while ! git bisect status 2>/dev/null | grep -q 'first bad commit'; do
  echo "Testing $(git rev-parse HEAD)..."

  # Run the benchmark
  current=$(npx lighthouse-ci collect 2>/dev/null | jq -r ".$metric" \
           || npx k6 run perf/$metric.js 2>/dev/null | jq -r ".$metric")

  if (( $(awk "BEGIN {print ($current > $good_val * 1.20)}") )); then
    git bisect bad
  else
    git bisect good
  fi
done

# 3. Report
first_bad=$(git bisect log | grep 'first bad commit' | awk '{print $NF}')
echo "Regression introduced in: $first_bad"
git show --stat "$first_bad"

# 4. Open a fix task
cat >> tasks/TASKS.md <<EOF
- [ ] T-perf-regression-${first_bad:0:7}  | priority: perf  | created: $(date -Iseconds)
  summary: Address $metric regression introduced in $first_bad
  files: $(git show --name-only --format= "$first_bad" | head -5 | tr '\n' ' ')
  accept: $metric returns to <= $good_val
  owner: @<author of $first_bad>
EOF

git bisect reset
```

## Hard rules

- **Bisect needs baselines saved per-commit.** `/perf-trend` writes these; this command depends on it.
- **Threshold: 20% degradation = regression.** Adjust per service tier.
- **Run the benchmark deterministically.** Same hardware, same load, same input data.
- **Open a task with the author tagged.** The author owns the fix.

## References

- git bisect docs
- `/perf-trend` (writes the baselines)
- `.claude/memory/perf-baselines/` (the data)

$ARGUMENTS
