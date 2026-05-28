#!/usr/bin/env bash
# Dream trigger — invoked by the 3 AM cron backstop from .claude/routines/dream-cron.yml.
# Equivalent of `/dream` but callable from cron (the cron context has no slash-command resolver).
#
# Reads the dream-state, decides whether to run, and spawns a fresh claude -p session
# with the dream-skill prompt. Background-safe; multiple invocations lock-out.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

state_file=".claude/memory/.cache/.dream-state.json"
lock_file=".claude/memory/.cache/.dream.lock"
log_dir=".claude/hooks/.log"
mkdir -p .claude/memories "$log_dir"

now_epoch=$(date +%s)
twenty_four_hours=$((24 * 3600))

# Read state
if [ -f "$state_file" ]; then
  last_run=$(jq -r '.last_run_epoch // 0' "$state_file" 2>/dev/null || echo 0)
else
  last_run=0
fi

elapsed=$((now_epoch - last_run))

# Bail if less than 24h since last dream — unless --force
if [ "${1:-}" != "--force" ] && [ "$elapsed" -lt "$twenty_four_hours" ]; then
  hrs_left=$(( (twenty_four_hours - elapsed) / 3600 ))
  echo "$(date -Iseconds) dream-trigger: skipping; last dream ${elapsed}s ago (${hrs_left}h until next)" >> "$log_dir/dream.log"
  exit 0
fi

# Take the lock
if [ -f "$lock_file" ]; then
  echo "$(date -Iseconds) dream-trigger: locked, another dream in progress" >> "$log_dir/dream.log"
  exit 0
fi
echo "$$" > "$lock_file"

# Spawn the dream subagent
if ! command -v claude >/dev/null 2>&1; then
  echo "$(date -Iseconds) dream-trigger: claude CLI not found; cannot run dream" >> "$log_dir/dream.log"
  rm -f "$lock_file"
  exit 1
fi

log_file="$log_dir/dream-$(date +%Y%m%d-%H%M%S).log"

claude -p --bare \
  --max-turns 30 \
  --max-budget-usd 1 \
  "Invoke the dream skill. Read .claude/memory/ topic files and .claude/memory/.cache/checkpoints/ since epoch $last_run. Consolidate: dedupe, compress verbose entries, absolutize relative dates, drop contradictions. Enforce 200-line cap on .claude/memory/MEMORY.md. Move processed checkpoints to .claude/memory/.cache/archive/$(date +%Y-%m)/. Update .claude/memory/.cache/.dream-state.json with new last_run_epoch and session_count: 0. Exit cleanly. No PRs, no source-file commits." \
  > "$log_file" 2>&1

rc=$?

# Update state on success
if [ "$rc" -eq 0 ]; then
  printf '{"last_run_epoch":%d,"session_count":0,"last_log":"%s"}' "$now_epoch" "$log_file" > "$state_file"
  echo "$(date -Iseconds) dream-trigger: completed; log=$log_file" >> "$log_dir/dream.log"
else
  echo "$(date -Iseconds) dream-trigger: FAILED (rc=$rc); log=$log_file" >> "$log_dir/dream.log"
fi

rm -f "$lock_file"
exit $rc
