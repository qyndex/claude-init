#!/usr/bin/env bash
# Session heartbeat — UserPromptSubmit hook (Round 6 B).
#
# Writes .claude/memory/.cache/current-session.json every turn so that if the
# session is killed (SIGKILL, terminal close, network drop), the NEXT session-start
# can detect "previous session crashed" and recover.
#
# session-end.sh is the GRACEFUL counterpart — it deletes this file at clean exit.
# So the file's PRESENCE at session-start = "previous session was killed".
#
# Cost: ~5ms per turn. Free heartbeat.

set -uo pipefail

mkdir -p .claude/memory/.cache
state_file=".claude/memory/.cache/current-session.json"
tmp="${state_file}.tmp"

# CLAUDE_SESSION_ID is set by Claude Code in hook env (if available).
# Fall back to PPID-based marker for older versions.
session_id="${CLAUDE_SESSION_ID:-pid-$PPID}"

# Read previous state to compute turn count
prev_turn=0
prev_started_at=""
if [ -f "$state_file" ]; then
  # JUSTIFIED: jq error muted + fallback — a partially-written heartbeat file yields 0, correctly restarting the turn counter rather than crashing the per-turn hook
  prev_turn=$(jq -r '.turn_count // 0' "$state_file" 2>/dev/null || echo 0)
  # JUSTIFIED: jq error muted + empty fallback — a corrupt file yields empty start time, recomputed fresh below; never fatal to the hook
  prev_started_at=$(jq -r '.started_at // ""' "$state_file" 2>/dev/null || echo "")
  # JUSTIFIED: jq error muted + empty fallback — empty session id forces the "new session" branch below, the safe default on a corrupt file
  prev_session=$(jq -r '.session_id // ""' "$state_file" 2>/dev/null || echo "")
  # If session_id changed, treat as new session
  if [ "$prev_session" != "$session_id" ]; then
    prev_turn=0
    prev_started_at=""
  fi
fi

turn=$((prev_turn + 1))
now_iso=$(date -Iseconds)
started_at="${prev_started_at:-$now_iso}"

branch="unknown"
cwd_val="$(pwd)"
uncommitted=0
if git rev-parse --git-dir >/dev/null 2>&1; then
  # JUSTIFIED: git error muted — a detached HEAD has no symbolic ref; "detached" is the intended recorded value
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  # JUSTIFIED: git error muted — inside the rev-parse success branch; any residual noise just yields a 0 uncommitted count for the heartbeat
  uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
fi

# Atomic write
jq -nc \
  --arg session_id "$session_id" \
  --arg pid "$PPID" \
  --arg started_at "$started_at" \
  --arg last_heartbeat_at "$now_iso" \
  --arg branch "$branch" \
  --arg cwd "$cwd_val" \
  --argjson turn_count "$turn" \
  --argjson uncommitted "$uncommitted" \
  '{
    session_id: $session_id,
    pid: ($pid | tonumber),
    started_at: $started_at,
    last_heartbeat_at: $last_heartbeat_at,
    branch: $branch,
    cwd: $cwd,
    turn_count: $turn_count,
    uncommitted: $uncommitted
  # JUSTIFIED: jq + mv errors muted — the heartbeat is a per-turn side effect; a transient write failure must never block the user's prompt, and the next turn simply re-writes it
  }' > "$tmp" 2>/dev/null && mv "$tmp" "$state_file" 2>/dev/null

# This hook does not emit additionalContext — it's purely a side effect.
exit 0
