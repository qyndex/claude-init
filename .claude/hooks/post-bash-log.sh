#!/usr/bin/env bash
# PostToolUse hook for Bash. Logs every command + outcome for auditability.

set -uo pipefail

input=$(cat)
mkdir -p .claude/hooks/.log

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
exit_code=$(printf '%s' "$input" | jq -r '.tool_response.exit_code // .tool_response.exitCode // 0')
stdout=$(printf '%s' "$input" | jq -r '.tool_response.stdout // ""')
stderr=$(printf '%s' "$input" | jq -r '.tool_response.stderr // ""')
ts=$(date -Iseconds)

# One line per command. Keep PII-light.
printf '%s\texit=%s\t%s\n' "$ts" "$exit_code" "${cmd:0:200}" >> .claude/hooks/.log/bash.log

# ─── Round 6 F: rate-limit sniffer ──────────────────────────────────────
# Detect 429 / rate_limit_exceeded / "retry after" in tool output. Surface a
# structured event so cost-report.sh / dream-skill / status-line can see it.
# Pattern matches the Anthropic CLI error format + common API client errors.
combined="${stdout}${stderr}"
if printf '%s' "$combined" | grep -qE 'rate[_ -]?limit|HTTP 429|"status":[[:space:]]*429|429:|"type":[[:space:]]*"rate_limit'; then
  # Extract retry-after if visible
  retry_after=$(printf '%s' "$combined" | grep -oiE 'retry[ -]?after[":[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1)
  retry_after="${retry_after:-unknown}"

  jq -nc \
    --arg ts "$ts" \
    --arg cmd "${cmd:0:200}" \
    --arg retry_after "$retry_after" \
    --argjson exit_code "${exit_code:-0}" \
    '{
      ts: $ts,
      kind: "rate_limit",
      command: $cmd,
      exit_code: $exit_code,
      retry_after_s: $retry_after
    # JUSTIFIED: the redirect drops jq stderr — the ratelimit log is best-effort telemetry; a write failure must never abort the PostToolUse hook
    }' >> .claude/hooks/.log/ratelimit.jsonl 2>/dev/null

  # Also surface in the bash.log with a flag
  printf '%s\tRATE_LIMIT\tretry_after=%s\n' "$ts" "$retry_after" >> .claude/hooks/.log/bash.log
fi

# ─── Spec 001 AC-17: typed lane events for swarm streams ────────────────
# Only fires inside a swarm stream — the worktree branch matches feat-<N>.
# Outside a stream this is a clean no-op (no events file is touched). We key
# the lane transition off the TDD-ledger command the stream just ran:
#   tdd-ledger.sh red   → lane.red      (a test went red)
#   tdd-ledger.sh green → lane.green    (the test passed)
# and off an explicit task-blocked marker the stream emits when it parks a
# task as [b]. The coordinator tails .swarms/events/<id>.jsonl to drive merges.
# JUSTIFIED: the redirect drops git stderr outside a repo/worktree — a blank branch just means "not a stream" and skips emission
stream_id=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -oE '^feat-[a-z0-9-]+' || true)
if [ -n "$stream_id" ]; then
  lane_event=""
  case "$cmd" in
    *tdd-ledger.sh\ red\ *|*tdd-ledger.sh\ red)   lane_event="lane.red" ;;
    *tdd-ledger.sh\ green\ *|*tdd-ledger.sh\ green) lane_event="lane.green" ;;
    *LANE_BLOCKED*)                                lane_event="lane.blocked" ;;
  esac
  if [ -n "$lane_event" ]; then
    mkdir -p .swarms/events
    ev_json=$(jq -nc \
      --arg ts "$ts" \
      --arg sid "$stream_id" \
      --arg ev "$lane_event" \
      --arg cmd "${cmd:0:200}" \
      --argjson exit_code "${exit_code:-0}" \
      '{ts: $ts, stream_id: $sid, event: $ev, payload: {command: $cmd, exit_code: $exit_code}}')
    # Append-only JSONL; O_APPEND on a single short write is atomic on local FS.
    # JUSTIFIED: the redirect drops write stderr — lane telemetry is best-effort; a write failure must never abort the PostToolUse hook
    printf '%s\n' "$ev_json" >> ".swarms/events/${stream_id}.jsonl" 2>/dev/null
  fi
fi

exit 0
