#!/usr/bin/env bash
# PreToolUse hook. Two responsibilities:
#   1. Refuse spawn-class commands (claude --bg / -p / --remote) when monthly
#      cost cap is exceeded. Reads .claude/hooks/.log/cost-summary.json.
#   2. Refuse a single subagent spawn whose prompt exceeds 4 KB (Round 5 D7 —
#      catches "parent passes 10K-token brief, child pays it" leak).
#
# Wired on Bash and Agent|Task matchers in .claude/settings.json.

set -uo pipefail

input=$(cat)
# JUSTIFIED: jq error muted — malformed hook stdin yields empty tool_name, which falls through all gates to the default exit 0 (allow)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUMMARY_FILE="$ROOT/.claude/hooks/.log/cost-summary.json"

# ─── (1) Prompt size gate for subagent dispatches ───────────────────────
# Fires on Agent or Task tool calls. We don't BLOCK on size — large reviews are
# real — but emit a warning that bubbles into the transcript.
if [ "$tool_name" = "Agent" ] || [ "$tool_name" = "Task" ]; then
  # JUSTIFIED: jq error muted — absent prompt yields empty, sizing to 0 bytes which passes under every threshold (no false block)
  prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null)
  prompt_bytes=$(printf '%s' "$prompt" | wc -c | tr -d ' ')

  # Round 6 C: hard ceiling — deny at 32 KB. The earlier "ask" decision
  # auto-resolves under Auto Mode, so the previous gate was effectively a
  # comment. 32 KB ≈ 8000 tokens is enough for a comprehensive brief; bigger
  # than that is almost always file contents inlined.
  if [ "${prompt_bytes:-0}" -gt 32768 ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Subagent prompt too large: ${prompt_bytes} bytes (~$((prompt_bytes / 4)) tokens). HARD CEILING is 32 KB. Pass file paths, not contents. Use Explore for reads. Split into multiple narrower subagents."
  }
}
EOF
    exit 0
  fi

  if [ "${prompt_bytes:-0}" -gt 16384 ]; then
    # Detect inline file contents heuristically: contiguous lines look like
    # source code or markdown headers with consistent indentation.
    inline_hint=""
    # JUSTIFIED: grep errors muted on both arms — these are purely a heuristic hint enrichment; a no-match (exit 1) simply leaves inline_hint empty and the warning still fires
    if printf '%s' "$prompt" | grep -qE '^[a-zA-Z0-9_/.-]+\.(py|ts|tsx|js|jsx|md|go|rs|java|kt|sql)$' 2>/dev/null \
      || printf '%s' "$prompt" | grep -qE '^(```|---$)' 2>/dev/null; then
      inline_hint=" Detected probable inlined file content — replace with file paths."
    fi
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Large subagent prompt: ${prompt_bytes} bytes (~$((prompt_bytes / 4)) tokens). The child pays this on every turn.$inline_hint Consider (a) pointers/paths not contents, (b) narrower subagents, (c) Explore for reads."
  }
}
EOF
    exit 0
  fi
  exit 0
fi

# ─── (2) Spawn-class cost gate ──────────────────────────────────────────
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

case "$cmd" in
  *"claude --bg"*|*"claude -p"*|*"claude --remote"*) ;;
  *) exit 0 ;;
esac

# Round 5 D10: synchronous refresh (was background+disown — race condition).
# We need a current summary before deciding.
# JUSTIFIED: best-effort cost-summary refresh — if the report script fails the [ ! -f "$SUMMARY_FILE" ] check below catches the stale/missing summary and degrades to an "ask" decision rather than crashing the gate
bash "$ROOT/.claude/scripts/cost-report.sh" month >/dev/null 2>&1 || true

if [ ! -f "$SUMMARY_FILE" ]; then
  # No summary even after refresh — refuse to allow blind spend
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Cost summary unavailable (cost-report.sh produced no output). Spawn allowed only after confirmation. Run \`bash .claude/scripts/cost-report.sh month\` manually to verify."
  }
}
EOF
  exit 0
fi

# JUSTIFIED: jq error muted — a corrupt summary yields empty pct; the `${pct:-0}` defaults below treat that as 0% used, the fail-open spend posture (gate only blocks at proven ≥100%)
pct=$(jq -r .pct_used "$SUMMARY_FILE" 2>/dev/null | cut -d. -f1)
# JUSTIFIED: jq error muted — total_usd is only interpolated into the human reason string; an empty value degrades the message, not the decision
total=$(jq -r .total_usd "$SUMMARY_FILE" 2>/dev/null)
# JUSTIFIED: jq error muted — cap is only interpolated into the human reason string; an empty value degrades the message, not the decision
cap=$(jq -r .monthly_cap_usd "$SUMMARY_FILE" 2>/dev/null)

if [ "${pct:-0}" -ge 100 ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Cost cap exceeded: \$${total} of \$${cap} monthly cap (${pct}%). To override, raise CLAUDE_MONTHLY_CAP_USD env var or wait until next month. To inspect spend: bash .claude/scripts/cost-report.sh"
  }
}
EOF
  exit 0
fi

if [ "${pct:-0}" -ge 90 ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Cost cap at ${pct}% (\$${total} of \$${cap}). Confirm this spawn is necessary; consider switching to Sonnet/Haiku to extend runway."
  }
}
EOF
  exit 0
fi

exit 0
