#!/usr/bin/env bash
# Test for pre-bash-dep-freshness.sh fail-closed behavior (Spec 001 AC-10).
#
# Tagged: AC-10
#
# When the registry/OSV is unreachable, the hook must emit permissionDecision:"ask"
# (fail CLOSED), not exit 0 silently. We simulate the outage with
# DEP_FRESHNESS_FORCE_OFFLINE=1 so the test needs no real network. Also asserts
# that non-install commands still pass straight through (exit 0, no decision).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$ROOT/.claude/hooks/pre-bash-dep-freshness.sh"

pass=0
fail=0
fails=()

run() { # run <env-assignments|""> <command>  → echoes hook stdout
  local envp="$1" cmd="$2" payload
  payload=$(jq -nc --arg c "$cmd" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')
  if [ -n "$envp" ]; then
    # JUSTIFIED: test harness mutes the hook's stderr so only its stdout JSON decision is asserted on
    printf '%s' "$payload" | env $envp bash "$HOOK" 2>/dev/null
  else
    # JUSTIFIED: test harness mutes the hook's stderr so only its stdout JSON decision is asserted on
    printf '%s' "$payload" | bash "$HOOK" 2>/dev/null
  fi
}

expect_ask() { # expect_ask <label> <output>
  local label="$1" out="$2"
  if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails+=("$label: expected ask, got: ${out:-<empty>}")
  fi
}

expect_no_decision() { # expect_no_decision <label> <output>
  local label="$1" out="$2"
  if printf '%s' "$out" | grep -q '"permissionDecision"'; then
    fail=$((fail+1)); fails+=("$label: expected no decision, got: $out")
  else
    pass=$((pass+1))
  fi
}

# 1. npm install with a forced registry outage → must ASK (fail closed).
out=$(run "DEP_FRESHNESS_FORCE_OFFLINE=1" "npm install lodash@4.17.0")
expect_ask "npm install fails closed when registry unreachable" "$out"

# 2. pip install with a forced outage → must ASK.
out=$(run "DEP_FRESHNESS_FORCE_OFFLINE=1" "pip install requests==2.0.0")
expect_ask "pip install fails closed when registry unreachable" "$out"

# 3. A non-install command must pass straight through (no decision emitted).
out=$(run "" "ls -la")
expect_no_decision "non-install command passes through" "$out"

# 4. Bare `npm install` (no package, runs against package.json) passes through.
out=$(run "DEP_FRESHNESS_FORCE_OFFLINE=1" "npm install")
expect_no_decision "bare npm install passes through" "$out"

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
