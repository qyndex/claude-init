#!/usr/bin/env bash
# Stop hook. Reminds Claude to verify before claiming done, when the session
# has produced uncommitted changes touching production code.
# Also enforces NEXUS handoff for coordinator sessions (AC-3).

set -uo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# ─── AC-3: coordinator NEXUS enforcement at Stop time ───────────────────
# A coordinator may be launched directly (claude --bg --agent coordinator),
# in which case the Stop hook fires — not SubagentStop. Re-run the same
# NEXUS block check that subagent-stop.sh performs for coordinator subagents.
input_json=$(cat)
agent_type=$(printf '%s' "$input_json" | jq -r '.tool_input.subagent_type // .agent_type // ""' 2>/dev/null || true)
# Detect coordinator by agent_type field or by session context marker.
# CLAUDE_AGENT_TYPE is set by the coordinator's session; fall back to checking
# the current .swarms/coordinator/ state.
if [ "${agent_type}" = "coordinator" ] || [ "${CLAUDE_AGENT_TYPE:-}" = "coordinator" ]; then
  final_msg=$(printf '%s' "$input_json" | jq -r '.tool_response.final_message // .tool_response.content // ""' 2>/dev/null || true)
  if [ -n "$final_msg" ]; then
    yaml_block=$(printf '%s' "$final_msg" | awk '
      /^```(nexus|yaml)$/ { in_block=1; next }
      /^```$/ && in_block { in_block=0 }
      in_block { print }
    ')
    if [ -z "$yaml_block" ]; then
      cat <<EOF
{"hookSpecificOutput":{"hookEventName":"Stop","permissionDecision":"deny","permissionDecisionReason":"coordinator Stop without NEXUS handoff block. Emit a \`\`\`nexus or \`\`\`yaml block per .swarms/templates/handoff.yaml before stopping."}}
EOF
      exit 2
    fi
    if [ -f .claude/scripts/validate-handoff.sh ]; then
      if ! printf '%s' "$yaml_block" | bash .claude/scripts/validate-handoff.sh --stdin >/dev/null 2>&1; then
        cat <<EOF
{"hookSpecificOutput":{"hookEventName":"Stop","permissionDecision":"deny","permissionDecisionReason":"coordinator Stop with INVALID NEXUS handoff. Re-emit with all required fields per .swarms/templates/handoff.yaml."}}
EOF
        exit 2
      fi
    fi
  fi
fi

# JUSTIFIED: the redirect drops git stderr when not in a repo — guarded by the rev-parse check above, an empty result yields dirty=0 and a clean early exit
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$dirty" -eq 0 ]; then
  exit 0
fi

# Check if any production files changed
# JUSTIFIED: the redirect drops git diff stderr and the fallback yields empty when grep matches nothing (exit 1) — empty prod_changed correctly means "no prod files touched" and triggers a clean exit
prod_changed=$(git diff --name-only HEAD 2>/dev/null | grep -Ev '^(specs/|plans/|tasks/|docs/|.claude/|.github/|verify/|README|CHANGELOG)' | head -5 || true)

if [ -z "$prod_changed" ]; then
  exit 0
fi

# Check if a recent verify report exists
recent_verify=""
if [ -d verify ]; then
  # JUSTIFIED: the redirect drops find stderr and the fallback yields empty if find errors or matches nothing — empty recent_verify correctly emits the "no recent verification" block
  recent_verify=$(find verify -name 'REPORT.md' -mtime -1 -print 2>/dev/null | head -1 || true)
fi

if [ -z "$recent_verify" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Production files changed but no recent verification report (verify/*/REPORT.md from the last 24h). Run /verify before ending. To override: re-send your last message; Claude Code Stop-hook protocol allows resubmission to bypass a block. (Sending the word 'continue' is not a special token — it just resubmits.)"
  }
}
EOF
  exit 2
fi

exit 0
