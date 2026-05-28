#!/usr/bin/env bash
# loop-state.sh — consecutive-aborts state machine for the autopilot loop.
#
# Sourced by loop-iteration.sh and by the test (.claude/scripts/test/loop-control.sh).
# Backing store is a JSON file at $STATE_FILE (defaults to the committed
# .claude/state/consecutive-aborts.json); tests override STATE_FILE to a tempfile.
#
# Semantics (Spec 001 AC-5):
#   - count increments on each abort, resets to 0 on the first progress.
#   - a PIVOT is due when the SAME task aborts a 2nd consecutive time.
#   - the loop hard-stops when count >= LOOP_ABORT_CAP (default 3).
#
# No side effects on source beyond defining functions + defaults.

: "${STATE_FILE:=${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/state/consecutive-aborts.json}"
: "${LOOP_ABORT_CAP:=3}"

# Atomic write: render to a tempfile in the same dir, then mv (rename is atomic
# on the same filesystem) so a crashed write never leaves a half-file.
write_atomic() {
  # write_atomic <target-file> <content>
  local target="$1" content="$2" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.$(basename "$target").XXXXXX")"
  printf '%s\n' "$content" >"$tmp"
  mv -f "$tmp" "$target"
}

loop_state_init() {
  write_atomic "$STATE_FILE" "$(jq -n --arg ts "$(date -Iseconds)" '{
    count: 0,
    same_task_streak: 0,
    last_task: null,
    last_error_hash: null,
    last_pivot_attempt: 0,
    updated: $ts
  }')"
}

# Ensure a readable state file exists before any read.
_loop_state_ensure() {
  if [ ! -f "$STATE_FILE" ] || ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    loop_state_init
  fi
}

loop_state_count() {
  _loop_state_ensure
  jq -r '.count' "$STATE_FILE"
}

# loop_state_record <task-id> <status>   status in {abort, progress}
loop_state_record() {
  local task="$1" status="$2"
  _loop_state_ensure
  local cur prev_task streak next next_streak ts
  cur=$(jq -r '.count' "$STATE_FILE")
  prev_task=$(jq -r '.last_task // ""' "$STATE_FILE")
  streak=$(jq -r '.same_task_streak // 0' "$STATE_FILE")
  ts=$(date -Iseconds)
  case "$status" in
    abort)
      next=$((cur + 1))
      if [ "$task" = "$prev_task" ]; then
        next_streak=$((streak + 1))
      else
        next_streak=1
      fi
      ;;
    progress) next=0; next_streak=0 ;;
    *) echo "loop_state_record: unknown status '$status'" >&2; return 2 ;;
  esac
  write_atomic "$STATE_FILE" "$(jq \
    --argjson n "$next" --argjson s "$next_streak" --arg t "$task" --arg ts "$ts" \
    '.count = $n | .same_task_streak = $s | .last_task = $t | .updated = $ts' "$STATE_FILE")"
}

# Exit 0 if a pivot is due: the same task has aborted a 2nd consecutive time and
# we haven't already pivoted at this count.
loop_state_should_pivot() {
  _loop_state_ensure
  jq -e '.same_task_streak == 2 and .last_pivot_attempt != .count' "$STATE_FILE" >/dev/null 2>&1
}

# Record that a pivot was attempted at the current count (prevents re-pivoting).
loop_state_mark_pivot() {
  _loop_state_ensure
  local ts; ts=$(date -Iseconds)
  write_atomic "$STATE_FILE" "$(jq --arg ts "$ts" \
    '.last_pivot_attempt = .count | .updated = $ts' "$STATE_FILE")"
}

# Exit 0 if the loop must hard-stop (count >= cap).
loop_state_should_stop() {
  _loop_state_ensure
  jq -e --argjson cap "$LOOP_ABORT_CAP" '.count >= $cap' "$STATE_FILE" >/dev/null 2>&1
}
