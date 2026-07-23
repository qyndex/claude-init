#!/usr/bin/env bash
# M-19 — the scheduled dream spawn must (1) respect the monthly cost cap INLINE
# (O-7 HIGH-1: pre-spawn-cost-gate.sh never sees this nohup spawn); (2) spawn via
# the metabolism seam (OAuth, no --bare — the bug M-01b fixed but this site missed);
# (3) stamp last_run_epoch ONLY on success, so an auth-absent/failed dream fails
# LOUD and leaves the state unstamped (no false success).
#
# auto-dream-check.sh is a GUARDED hook → the fix ships as a staged patch. This test
# applies it onto a temp copy and asserts the STRUCTURE (grep the patched hook +
# the patch), since a real dream spawn needs a live claude/OAuth.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PATCH="$ROOT/.claude/memory.proposed/patches/M-19-dream-cost-gate-and-oauth-spawn.patch"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

[ -f "$PATCH" ] || { echo "  - missing patch: $PATCH"; echo "passed: 0"; echo "failed: 1"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/hooks"
cp "$ROOT/.claude/hooks/auto-dream-check.sh" "$tmp/.claude/hooks/"
( cd "$tmp" && git apply "$PATCH" ) 2>/dev/null
check "M-19 patch applies onto the guarded hook" $?

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
