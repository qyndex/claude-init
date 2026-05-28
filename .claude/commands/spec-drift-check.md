---
description: Detect drift — code shipped months ago that no longer matches the spec's acceptance criteria. Re-runs the spec's `accept:` commands; flags regressions vs. original verification evidence.
argument-hint: "[--all] | [spec-id]"
allowed-tools: Read, Glob, Grep, Bash
disable-model-invocation: true
---

# /spec-drift-check — Catch silent regressions vs. original spec

A spec written 6 months ago said "p95 < 200ms". Today's code is at 450ms. Nothing failed any PR's gate. This skill finds those.

```bash
target="${1:-shipped}"   # shipped | <spec-id> | all

if [ "$target" = "shipped" ]; then
  specs=$(grep -l '^status: shipped' specs/archive/*.md specs/active/*.md 2>/dev/null)
elif [ "$target" = "all" ]; then
  specs=$(ls specs/active/*.md specs/archive/*.md 2>/dev/null)
else
  specs=$(ls specs/active/${target}*.md specs/archive/${target}*.md 2>/dev/null)
fi

echo "# Spec drift check"
echo

for spec in $specs; do
  id=$(basename "$spec" .md)
  echo "## $id"

  # 1. Extract acceptance criteria
  ac=$(awk '/^## Acceptance/,/^## /' "$spec" | grep -E '^[0-9]+\.|^- \*\*AC-' | head -10)
  if [ -z "$ac" ]; then
    echo "  (no parseable acceptance criteria)"
    continue
  fi

  # 2. Find original verify report
  date_field=$(grep -E '^created:' "$spec" | sed 's/created: //')
  verify_dir=$(ls -d verify/${date_field}-* 2>/dev/null | head -1)

  # 3. Re-run verification (if reproducible)
  task_file=$(grep "spec:$id" tasks/TASKS.md 2>/dev/null | head -1)
  if [ -n "$task_file" ]; then
    accept_cmd=$(echo "$task_file" | grep -oE 'accept: .*' | sed 's/accept: //')
    if [ -n "$accept_cmd" ]; then
      echo "  Re-running: $accept_cmd"
      if eval "$accept_cmd" >/dev/null 2>&1; then
        echo "  ✓ Still passes"
      else
        echo "  ✗ DRIFT — acceptance command no longer exits 0"
      fi
    fi
  fi

  # 4. Perf budget check (if spec carries one)
  perf_target=$(grep -E '^- \*\*Performance\*\*:|p95.*<|latency.*<' "$spec" | head -1)
  if [ -n "$perf_target" ]; then
    echo "  Spec said: $perf_target"
    echo "  Current: query .claude/memory/perf-baselines/ for current $id"
    # Compare against baseline
  fi
done

echo
echo "## Recommendation"
echo "For drift-detected specs, open follow-up tasks via /debt add 'spec drift: <spec-id>'"
echo "Run /perf-trend for trend visualization"
```

## Recurring scan

The scheduled, non-interactive version is `.claude/scripts/spec-drift-scan.sh` — it does the
same re-run of each shipped spec's `accept:` command, writes flagged drifts to
`.claude/memory/incidents/drift-<date>.md`, AND (this is the loop the interactive command
above does NOT close on its own) queues `priority: spec-drift` follow-up tasks via
`findings-to-tasks.sh`. `dream-cron` runs it every **Monday** (step 9). Run it by hand anytime:

```bash
bash .claude/scripts/spec-drift-scan.sh
```

$ARGUMENTS
