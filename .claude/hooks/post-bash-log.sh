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

# ─── Spec 001 AC-17 + Spec 002 AC-32: typed JSONL lane events ────────────
# Only fires inside a swarm stream — worktree branch matches feat-<N>.
# Outside a stream this is a clean no-op (no events file is touched).
#
# AC-32 adds: error.kind enum with retryable flag, and lane.started emission
# when the stream runs its first command (first turn, turn_count == 1).
#
# JUSTIFIED: git error muted — a blank branch means "not a stream", skips emission
stream_id=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -oE '^feat-[a-z0-9-]+' || true)
if [ -n "$stream_id" ]; then
  lane_event=""
  error_kind=""
  retryable="false"

  # Determine lane event from command
  case "$cmd" in
    *tdd-ledger.sh\ red\ *|*tdd-ledger.sh\ red)    lane_event="lane.red" ;;
    *tdd-ledger.sh\ green\ *|*tdd-ledger.sh\ green) lane_event="lane.green" ;;
    *LANE_BLOCKED*)                                 lane_event="lane.blocked" ;;
    # AC-32: lane.started on very first bash command in a new stream session
    *)
      if [ -f ".swarms/streams/${stream_id}/state.json" ]; then
        prev_state=$(jq -r '.state // ""' ".swarms/streams/${stream_id}/state.json" 2>/dev/null || true)
        [ "$prev_state" = "ready_for_prompt" ] && lane_event="lane.started"
      fi
      ;;
  esac

  # AC-32: classify non-zero exit codes into error.kind with retryable flag
  if [ "${exit_code:-0}" -ne 0 ] && [ -z "$lane_event" ]; then
    lane_event="lane.error"
    case "${exit_code}" in
      124|137) error_kind="timeout";   retryable="true" ;;   # timeout / OOM-kill
      130)     error_kind="interrupt"; retryable="true" ;;   # SIGINT
      1)       error_kind="tool_error"; retryable="false" ;; # generic tool failure
      2)       error_kind="hook_block"; retryable="false" ;; # pre-bash-guard hard block
      *)       error_kind="unknown";   retryable="false" ;;
    esac
    # Detect transient network/rate-limit errors in output
    combined_short="${stdout:0:500}${stderr:0:500}"
    if printf '%s' "$combined_short" | grep -qE 'rate[_ -]?limit|HTTP 429|connection reset|ECONNREFUSED|timeout'; then
      error_kind="transient"; retryable="true"
    fi
  fi

  if [ -n "$lane_event" ]; then
    mkdir -p .swarms/events
    ev_json=$(jq -nc \
      --arg ts "$ts" \
      --arg sid "$stream_id" \
      --arg ev "$lane_event" \
      --arg cmd "${cmd:0:200}" \
      --arg error_kind "$error_kind" \
      --arg retryable "$retryable" \
      --argjson exit_code "${exit_code:-0}" \
      '{ts: $ts, stream_id: $sid, event: $ev, payload: {command: $cmd, exit_code: $exit_code, error_kind: (if $error_kind != "" then $error_kind else null end), retryable: ($retryable == "true")}}')
    # Append-only JSONL; O_APPEND on a single short write is atomic on local FS.
    # JUSTIFIED: the redirect drops write stderr — lane telemetry is best-effort; a write failure must never abort the PostToolUse hook
    printf '%s\n' "$ev_json" >> ".swarms/events/${stream_id}.jsonl" 2>/dev/null
  fi
fi

exit 0
