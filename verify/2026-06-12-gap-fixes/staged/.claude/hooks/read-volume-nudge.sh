#!/usr/bin/env bash
# PostToolUse hook for Read — gap-audit G35.
# Constitution §IV says heavy reads (>3 files / >20K tokens) belong in Explore,
# but nothing detected a missed delegation. This counts in-session Reads and
# nudges once per threshold crossing (8, then every further 8) — deterministic
# and cheap; the decision stays with the model.

set -uo pipefail

payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0

session=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$session" ] && session="default"

THRESHOLD="${READ_NUDGE_THRESHOLD:-8}"
state_dir=".claude/state/read-nudge"
mkdir -p "$state_dir" 2>/dev/null || exit 0
state_file="$state_dir/${session}.count"

# JUSTIFIED: a missing/corrupt counter restarts at 0 — worst case the nudge fires late
count=$(cat "$state_file" 2>/dev/null || echo 0)
case "$count" in (*[!0-9]*|'') count=0 ;; esac
count=$(( count + 1 ))
printf '%s\n' "$count" > "$state_file" 2>/dev/null || true

if [ $(( count % THRESHOLD )) -ne 0 ]; then
  exit 0
fi

jq -nc --arg n "$count" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("[delegation] " + $n + " in-session Reads so far. Heavy reads (>3 files / >20K tokens) belong in a subagent — Explore for retrieval, researcher for investigation (§IV). Their context dies with them; yours does not.")}}'
exit 0
