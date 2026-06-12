#!/usr/bin/env bash
# Smoke test: workflow-state.sh is robust outside a git repo (Spec 001 AC-23).
#
# Tagged: AC-23
#
# Runs the hook in a NON-GIT temp directory and asserts:
#   (a) it exits 0,
#   (b) it writes a valid-JSON no-op state {phase:null,next:null,streak:0,warned_at:0},
#   (c) its stdout is valid JSON with an EMPTY additionalContext.
#
# lint-silent-failures: ignore-file
# This is a TEST: stderr is muted on probes because each assertion's exit code
# (via `check`) is the signal, not diagnostic noise.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="${HOOK_UNDER_TEST:-$ROOT/.claude/hooks/workflow-state.sh}"

pass=0
fail=0
fails=()
check() {
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Run the hook from inside a directory that is NOT a git repo.
out="$(cd "$TMP" && printf '' | bash "$HOOK")"
rc=$?
check "no-git-exits-0: hook exits 0 outside a git repo" "$rc"

# (b) state file written + valid JSON + no-op shape
state="$TMP/.swarms/coordinator/workflow-state.json"
[ -f "$state" ]
check "no-git-state-file-exists: workflow-state.json was written" $?

jq -e . "$state" >/dev/null 2>&1
check "no-git-state-valid-json: state file parses as JSON" $?

jq -e '.phase == null and .next == null and .streak == 0 and .warned_at == 0' "$state" >/dev/null 2>&1
check "no-git-state-noop-shape: {phase:null,next:null,streak:0,warned_at:0}" $?

# (c) stdout is valid JSON with an empty additionalContext
printf '%s' "$out" | jq -e . >/dev/null 2>&1
check "no-git-stdout-json: hook stdout is valid JSON" $?

printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext == ""' >/dev/null 2>&1
check "no-git-empty-context: additionalContext is empty" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
