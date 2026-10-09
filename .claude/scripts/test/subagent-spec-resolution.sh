#!/usr/bin/env bash
# Regression: installed subagent hooks preserve workflow spec identity.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/hooks" "$tmp/specs/active" "$tmp/plans/active" \
         "$tmp/.swarms/coordinator"

# Copy installed hooks into a hermetic fixture.
cp "$ROOT/.claude/hooks/workflow-state.sh"  "$tmp/.claude/hooks/"
cp "$ROOT/.claude/hooks/subagent-context.sh" "$tmp/.claude/hooks/"

# ── Fixture: 003 is the workflow-state spec; 007 is newer by mtime ──────────
: > "$tmp/specs/active/003-alpha.md"
sleep 0.1 2>/dev/null || true
: > "$tmp/specs/active/007-beta.md"          # newest-by-mtime ≠ workflow-state spec
# workflow-state.json persists 003 (what the parent's phase logic keyed on).
printf '{"phase":"implementing","spec":"specs/active/003-alpha.md","plan":""}' \
  > "$tmp/.swarms/coordinator/workflow-state.json"

# Drive subagent-context.sh exactly as the harness does: JSON on stdin.
out=$(cd "$tmp" && printf '{"tool_name":"Agent","tool_input":{"subagent_type":"implementer"}}' \
      | bash .claude/hooks/subagent-context.sh 2>/dev/null)

# The emitted additionalContext must name 003 (workflow-state), NOT 007 (mtime).
printf '%s' "$out" | grep -q '003-alpha'
check "child inherits the workflow-state spec (003), not newest-by-mtime" $?
! printf '%s' "$out" | grep -q '007-beta'
check "child does NOT inherit the newest-by-mtime spec (007)" $?

# ── Regression: pre-M-05c state (no .spec key) still falls back to ls -t ─────
printf '{"phase":"implementing"}' > "$tmp/.swarms/coordinator/workflow-state.json"
out2=$(cd "$tmp" && printf '{"tool_name":"Agent","tool_input":{"subagent_type":"implementer"}}' \
       | bash .claude/hooks/subagent-context.sh 2>/dev/null)
printf '%s' "$out2" | grep -q '007-beta'
check "no .spec key → falls back to ls -t newest (007)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
