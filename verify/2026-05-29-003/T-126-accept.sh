#!/usr/bin/env bash
# AC-14: validate.sh has a ruleset↔job coverage category that fails when a
# required_status_checks context has no PR-triggered, non-paths-filtered job.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# 1. The category must exist and run.
out=$(bash .claude/scripts/validate.sh 2>&1 || true)
echo "$out" | grep -q '\[ruleset-coverage\]' || { echo "FAIL: no [ruleset-coverage] category in validate.sh"; exit 1; }

# 2. On the real repo (round-1 deadlock now fixed), the category must PASS:
#    every required context maps to a real PR-triggered job.
echo "$out" | grep -A6 '\[ruleset-coverage\]' | grep -qE '✓|maps to' || { echo "FAIL: ruleset-coverage did not report OK"; exit 1; }

# 3. Synthetic negative: a fabricated ruleset context with no job must FAIL.
tmp=$(mktemp)
jq '(.rules[] | select(.parameters.required_status_checks).parameters.required_status_checks) += [{"context":"this-job-does-not-exist-xyz"}]' \
   .github/rulesets/main-protection.json > "$tmp" 2>/dev/null || cp .github/rulesets/main-protection.json "$tmp"
# Run just the coverage function against the synthetic file via env override.
neg=$(RULESET_FILE_OVERRIDE="$tmp" bash .claude/scripts/validate.sh 2>&1 || true)
echo "$neg" | grep -qE 'this-job-does-not-exist-xyz|✗.*ruleset|no matching job' || { echo "FAIL: synthetic missing-job context not flagged"; rm -f "$tmp"; exit 1; }
rm -f "$tmp"

echo "PASS: AC-14 ruleset↔job coverage check present and correct"
exit 0
