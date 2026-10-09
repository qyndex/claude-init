#!/usr/bin/env bash
# Spec 006 AC-5: malformed/missing/high-severity SARIF must block.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
check_fail() { if bash "$ROOT/.claude/scripts/check-sarif.sh" "$1" >"$tmp/log" 2>&1; then echo "FAIL: unsafe SARIF passed ($1)"; fail=$((fail+1)); else pass=$((pass+1)); fi; }
check_fail "$tmp/missing"
printf 'not json' > "$tmp/bad"; check_fail "$tmp/bad"
printf '{}' > "$tmp/empty"; check_fail "$tmp/empty"
printf '{"version":"2.1.0","runs":[{"results":[{"level":"warning","properties":{"security-severity":"10.0"}}]}]}' > "$tmp/high"; check_fail "$tmp/high"
printf '{"version":"2.1.0","runs":[{"tool":{"driver":{"rules":[{"id":"x","properties":{"security-severity":"8.0"}}]}},"results":[{"ruleId":"x","level":"warning"}]}]}' > "$tmp/rule-high"; check_fail "$tmp/rule-high"
printf '{"version":"2.1.0","runs":[{"results":[]}]}' > "$tmp/clean"
if bash "$ROOT/.claude/scripts/check-sarif.sh" "$tmp/clean" >"$tmp/log" 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); fi
printf '{"version":"2.1.0","runs":[{"results":[{"level":"warning","properties":{"security-severity":"4.0"}}]}]}' > "$tmp/low"
if bash "$ROOT/.claude/scripts/check-sarif.sh" "$tmp/low" >"$tmp/log" 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); fi
if actionlint -shellcheck= "$ROOT/.github/workflows/iac-scan.yml" >"$tmp/lint" 2>&1; then pass=$((pass+1)); else cat "$tmp/lint"; fail=$((fail+1)); fi
echo "passed: $pass; failed: $fail"; [ "$fail" -eq 0 ]
