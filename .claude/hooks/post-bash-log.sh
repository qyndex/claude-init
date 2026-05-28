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

exit 0
