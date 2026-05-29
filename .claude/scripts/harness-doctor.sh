#!/usr/bin/env bash
# Harness health check — AC-35.
# Runs the same structural checks as validate.sh but outputs machine-readable JSON.
# Used by harness-validate.yml to upload a structured artifact and by T-109.
#
# Usage:
#   bash .claude/scripts/harness-doctor.sh          # human-readable summary
#   bash .claude/scripts/harness-doctor.sh --json   # JSON array of check results

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

JSON_MODE=0
[ "${1:-}" = "--json" ] && JSON_MODE=1

result_file=$(mktemp)
trap 'rm -f "$result_file"' EXIT
printf '[\n' > "$result_file"
first_result=1

add_result() {
  local check="$1" status="$2" detail="$3"
  local entry
  entry=$(jq -nc --arg c "$check" --arg s "$status" --arg d "$detail" \
    '{check:$c,status:$s,detail:$d}')
  if [ "$first_result" -eq 1 ]; then
    first_result=0
    printf '%s\n' "$entry" >> "$result_file"
  else
    printf ',%s\n' "$entry" >> "$result_file"
  fi
  if [ "$JSON_MODE" -eq 0 ]; then
    [ "$status" = "pass" ] && printf '  ✓ %s\n' "$check" || printf '  ✗ %s: %s\n' "$check" "$detail"
  fi
}

[ "$JSON_MODE" -eq 0 ] && printf '\nHarness Doctor\n──────────────\n'

# Core files present
for f in .claude/CLAUDE.md .claude/settings.json .mcp.json tasks/TASKS.md; do
  if [ -f "$f" ]; then
    add_result "$f exists" "pass" ""
  else
    add_result "$f exists" "fail" "missing required file"
  fi
done

# JSON validity
for f in .claude/settings.json .mcp.json; do
  if [ -f "$f" ]; then
    if jq -e . "$f" > /dev/null 2>&1; then
      add_result "$f valid JSON" "pass" ""
    else
      add_result "$f valid JSON" "fail" "jq parse error"
    fi
  fi
done

# disableBypassPermissionsMode (nested under .permissions in this harness)
if [ -f .claude/settings.json ]; then
  val=$(jq -r '(.permissions.disableBypassPermissionsMode // .disableBypassPermissionsMode) // ""' .claude/settings.json 2>/dev/null)
  if [ "$val" = "disable" ]; then
    add_result "disableBypassPermissionsMode=disable" "pass" ""
  else
    add_result "disableBypassPermissionsMode=disable" "fail" "got: $val"
  fi
fi

# Hook executables
hook_fails=0
while IFS= read -r sh; do
  if [ ! -x "$sh" ]; then
    add_result "hook executable: $sh" "fail" "not executable"
    hook_fails=$((hook_fails + 1))
  fi
done < <(find .claude/hooks -name '*.sh' -type f 2>/dev/null)
[ "$hook_fails" -eq 0 ] && add_result "hooks executable" "pass" ""

# Constitution size
if [ -f .claude/CLAUDE.md ]; then
  lines=$(wc -l < .claude/CLAUDE.md | tr -d ' ')
  if [ "$lines" -le 300 ]; then
    add_result "constitution ≤300 lines" "pass" "${lines} lines"
  else
    add_result "constitution ≤300 lines" "fail" "${lines} lines (cap 300)"
  fi
fi

# @latest pins
if [ -f .mcp.json ] && command -v jq >/dev/null 2>&1; then
  unpinned=$(jq -r '.mcpServers[]?.args[]? // empty' .mcp.json 2>/dev/null | grep -E '@latest' || true)
  if [ -z "$unpinned" ]; then
    add_result "no @latest MCP pins" "pass" ""
  else
    add_result "no @latest MCP pins" "fail" "found: $unpinned"
  fi
fi

# Swarm templates
if [ -f .swarms/templates/handoff.yaml ]; then
  if grep -q 'tdd_state' .swarms/templates/handoff.yaml 2>/dev/null; then
    add_result "handoff.yaml has tdd_state" "pass" ""
  else
    add_result "handoff.yaml has tdd_state" "fail" "missing tdd_state block"
  fi
fi

printf ']\n' >> "$result_file"

if [ "$JSON_MODE" -eq 1 ]; then
  cat "$result_file"
else
  fail_count=$(jq '[.[] | select(.status=="fail")] | length' "$result_file" 2>/dev/null || echo 0)
  total=$(jq 'length' "$result_file" 2>/dev/null || echo 0)
  printf '\n%s check(s), %s failure(s)\n' "$total" "$fail_count"
  [ "${fail_count:-0}" -gt 0 ] && exit 1
fi
