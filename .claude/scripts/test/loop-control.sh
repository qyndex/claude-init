#!/usr/bin/env bash
# Test for the consecutive-aborts loop-control state machine (Spec 001 AC-5).
#
# Tagged: AC-05
#
# The state machine guards the autopilot loop against thrash: it counts
# consecutive aborts ([!] task writes), resets on progress ([x]), triggers a
# PIVOT (researcher subagent) on the 2nd consecutive abort of the SAME task, and
# hard-stops when count >= 3. State lives in a JSON file overridable via STATE_FILE
# so this test never touches the real .claude/state/consecutive-aborts.json.
#
# Interface under test (provided by .claude/scripts/lib/loop-state.sh):
#   loop_state_init                 → writes a fresh {count:0,...} to $STATE_FILE
#   loop_state_record <id> <status> → status in {abort,progress}; updates counters
#   loop_state_count                → prints current count
#   loop_state_should_pivot         → exit 0 if a pivot is due (2nd same-task abort)
#   loop_state_should_stop          → exit 0 if count >= 3 (hard cap)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIB="$ROOT/.claude/scripts/lib/loop-state.sh"

pass=0
fail=0
fails=()

# Hermetic state file in a temp dir — the "consecutive-aborts" backing store.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export STATE_FILE="$TMP/consecutive-aborts.json"

# shellcheck source=/dev/null
. "$LIB"

expect() {
  # expect <label> <actual> <wanted>
  local label="$1" actual="$2" wanted="$3"
  if [ "$actual" = "$wanted" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$label: got '$actual' wanted '$wanted'")
  fi
}

expect_rc() {
  # expect_rc <label> <actual-rc> <wanted-rc>
  local label="$1" actual="$2" wanted="$3"
  if [ "$actual" = "$wanted" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$label: rc=$actual wanted=$wanted")
  fi
}

# ---- fresh state inits to count:0 ----
loop_state_init
expect "init count is 0" "$(loop_state_count)" "0"

# ---- increment on [!] (abort) ----
loop_state_record T-100 abort
expect "after 1 abort count is 1" "$(loop_state_count)" "1"

# ---- a pivot is due on the 2nd consecutive abort of the SAME task ----
loop_state_should_pivot; expect_rc "no pivot after 1 abort" "$?" "1"
loop_state_record T-100 abort
expect "after 2 aborts count is 2" "$(loop_state_count)" "2"
loop_state_should_pivot; expect_rc "pivot due after 2nd same-task abort" "$?" "0"

# ---- reset on [x] (progress) ----
loop_state_record T-100 progress
expect "progress resets count to 0" "$(loop_state_count)" "0"

# ---- hard-stop on count >= 3 ----
loop_state_record T-200 abort
loop_state_record T-200 abort
loop_state_should_stop; expect_rc "no hard-stop at count 2" "$?" "1"
loop_state_record T-200 abort
expect "three aborts count is 3" "$(loop_state_count)" "3"
loop_state_should_stop; expect_rc "hard-stop at count 3" "$?" "0"

# ---- switching task resets the same-task pivot signal but not the global count ----
loop_state_init
loop_state_record T-300 abort
loop_state_record T-301 abort
loop_state_should_pivot; expect_rc "different tasks do not trigger pivot" "$?" "1"

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
