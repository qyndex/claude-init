#!/usr/bin/env bash
# Regression: installed dream hook enforces cost checks and OAuth spawn wiring.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }


tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/hooks"
cp "$ROOT/.claude/hooks/auto-dream-check.sh" "$tmp/.claude/hooks/"

H="$tmp/.claude/hooks/auto-dream-check.sh"

# (1) Cost gate is inline before the spawn: refreshes summary + reads pct_used +
#     skips at >=100%.
grep -q 'cost-report.sh month' "$H"
check "dream refreshes cost-summary inline before spawning" $?
grep -qE 'pct.*-ge 100|pct.*>=.*100' "$H"
check "dream skips the spawn at >=100% of the monthly cap" $?
# The skip path must NOT stamp last_run_epoch (a skip is not a completed dream).
# Assert the >=100% branch reaches exit 0 WITHOUT a printf last_run_epoch between
# the guard and the exit.
gate_block=$(awk '/pct.*-ge 100/{f=1} f{print} /exit 0/{if(f)exit}' "$H")
! printf '%s' "$gate_block" | grep -q 'last_run_epoch'
check "cost-skip path does NOT stamp last_run_epoch (no false success)" $?

# (2) Spawn uses the metabolism seam, NOT raw --bare.
grep -q 'metabolism_spawn' "$H"
check "dream spawns via metabolism_spawn seam (OAuth honored)" $?
! grep -qE "claude -p --bare" "$H"
check "dream no longer uses 'claude -p --bare' (M-01b consistency)" $?

# (3) Success is stamped ONLY inside the success branch; failure logs FAILED and
#     leaves state unstamped.
grep -qE 'if metabolism_spawn' "$H"
check "spawn result is branched on (rc-gated stamp)" $?
grep -qiE 'dream FAILED.*NOT stamped|FAILED.*rc' "$H"
check "spawn failure logs a loud FAILURE and does not stamp success" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
