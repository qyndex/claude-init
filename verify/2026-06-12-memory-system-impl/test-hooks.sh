#!/usr/bin/env bash
# Behavior tests for the staged hook fixes (memory-system implementation).
# Run BEFORE installing; re-run after install by pointing HOOKS_DIR at .claude/hooks.
set -uo pipefail

cd "$(dirname "$0")/../.."   # repo root
STAGE="verify/2026-06-12-memory-system-impl"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }

# Scaffold: staged hooks expect ../scripts/lib relative to themselves.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/hooks" "$TMP/scripts/lib"
cp "$STAGE"/workflow-state.sh.fixed "$TMP/hooks/workflow-state.sh"
cp "$STAGE"/session-start-context.sh.fixed "$TMP/hooks/session-start-context.sh"
cp "$STAGE"/subagent-context.sh.fixed "$TMP/hooks/subagent-context.sh"
cp "$STAGE"/session-end.sh.fixed "$TMP/hooks/session-end.sh"
cp .claude/scripts/lib/atomic-write.sh "$TMP/scripts/lib/"

echo "[workflow-state.sh.fixed]"
out=$(echo '{}' | bash "$TMP/hooks/workflow-state.sh")
echo "$out" | grep -q 'T-NNN' && bad "still leaks the T-NNN template line" \
  || ok "no T-NNN template leakage in state banner"
state_next=$(jq -r '.next' .swarms/coordinator/workflow-state.json)
case "$state_next" in
  *T-NNN*) bad "persisted state still holds template ('$state_next')" ;;
  *) ok "persisted next-task is real ('$state_next')" ;;
esac
phase=$(jq -r '.phase' .swarms/coordinator/workflow-state.json)
[ "$phase" != "implementing" ] && ok "phase advanced off bogus 'implementing' (now: $phase)" \
  || bad "phase still 'implementing' despite 0 pending tasks"

echo "[session-start-context.sh.fixed]"
out=$(bash "$TMP/hooks/session-start-context.sh")
echo "$out" | grep -q '\[initiative\]' && ok "injects initiative STATE line" \
  || bad "no [initiative] line in session-start context"
echo "$out" | grep -q 'T-NNN' && bad "leaks T-NNN template in next-tasks" \
  || ok "no T-NNN template in next-tasks"

echo "[subagent-context.sh.fixed]"
out=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"researcher","prompt":"x"}}' \
  | bash "$TMP/hooks/subagent-context.sh")
echo "$out" | grep -q 'Initiative state:' && ok "injects initiative STATE pointer" \
  || bad "no initiative pointer in subagent context"
echo "$out" | grep -q 'T-NNN' && bad "leaks T-NNN as current task" || ok "no T-NNN current-task leakage"

echo "[session-end.sh.fixed]"
rm -f .claude/memory/.cache/session-recent.json
echo '{}' | bash "$TMP/hooks/session-end.sh" >/dev/null 2>&1
[ -s .claude/memory/.cache/session-recent.json ] \
  && ok "session-recent.json written non-empty (argjson double-print fixed)" \
  || bad "session-recent.json empty/missing — grep -c bug persists"
jq -e '.tasks.in_progress' .claude/memory/.cache/session-recent.json >/dev/null 2>&1 \
  && ok "session-recent.json is valid JSON with task counts" \
  || bad "session-recent.json invalid"
[ -s .claude/state/current-initiative ] && ok "session-end synced initiative pointers" \
  || bad "pointers missing after session-end"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
