#!/usr/bin/env bash
# Stop hook. Triggers /dream when:
#   - >24h since last dream
#   - >=5 sessions accumulated since last dream
# Otherwise no-op. Cron at 3 AM is the backstop.

set -uo pipefail

mkdir -p .claude/memory/.cache
state_file=".claude/memory/.cache/.dream-state.json"
lock_file=".claude/memory/.cache/.dream.lock"

now_epoch=$(date +%s)

# Read state
if [ -f "$state_file" ]; then
  last_run=$(jq -r '.last_run_epoch // 0' "$state_file" 2>/dev/null)
  session_count=$(jq -r '.session_count // 0' "$state_file" 2>/dev/null)
else
  last_run=0
  session_count=0
fi

# Increment session count
session_count=$((session_count + 1))

# Compute elapsed
elapsed=$((now_epoch - last_run))
twenty_four_hours=$((24 * 3600))

# Should we dream?
if [ "$elapsed" -lt "$twenty_four_hours" ]; then
  # Just persist the session count and exit
  printf '{"last_run_epoch":%d,"session_count":%d}' "$last_run" "$session_count" > "$state_file"
  exit 0
fi

if [ "$session_count" -lt 5 ]; then
  printf '{"last_run_epoch":%d,"session_count":%d}' "$last_run" "$session_count" > "$state_file"
  exit 0
fi

# Lock to prevent concurrent dreams
if [ -f "$lock_file" ]; then
  exit 0
fi

# Round 5 E5: refuse to dream when an UN-REVIEWED proposal exists. Previously
# a second dream would silently overwrite the first one's proposal, dropping
# the human-review gate. Now the operator MUST clear the queue via /dream-review
# (approve OR discard) before a new dream can run.
if [ -d .claude/memory.proposed ] && [ "$(ls -A .claude/memory.proposed 2>/dev/null)" ]; then
  awaiting_review=$(jq -r '.awaiting_review // false' "$state_file" 2>/dev/null)
  if [ "$awaiting_review" = "true" ]; then
    echo "[$(date -Iseconds)] dream skipped: .claude/memory.proposed/ awaiting review (run /dream-review)" \
      >> .claude/hooks/.log/dream.log
    # Re-arm session count to 0 so we don't re-spawn next session
    printf '{"last_run_epoch":%d,"session_count":0,"awaiting_review":true}' "$last_run" > "$state_file"
    exit 0
  fi
fi

# Try to take the lock
echo "$$" > "$lock_file"

# Spawn dream in background — writes to .claude/memory.proposed/ NOT canonical.
# User reviews via /dream-review before applying. Adds the supervision gate
# the Round 4 audit flagged was missing.
if command -v claude >/dev/null 2>&1; then
  # Mirror canonical → proposed for the dream to mutate
  rm -rf .claude/memory.proposed 2>/dev/null
  cp -r .claude/memory .claude/memory.proposed

  nohup bash -c "
    set -uo pipefail
    claude -p --bare 'Invoke the dream skill: consolidate .claude/memory.proposed/ and .claude/memory/.cache/checkpoints/ since $last_run. Keep .claude/memory.proposed/MEMORY.md under 200 lines. Do NOT touch .claude/memory/ (canonical) — only the .proposed copy.' 2>&1 \
      > .claude/hooks/.log/dream-$(date +%Y%m%d-%H%M%S).log
    # Update state on success
    printf '{\"last_run_epoch\":%d,\"session_count\":0,\"awaiting_review\":true}' \"\$(date +%s)\" > '$state_file'
    rm -f '$lock_file'
  " > /dev/null 2>&1 &

  echo "[$(date -Iseconds)] Spawned background /dream (pid $!)" >> .claude/hooks/.log/dream.log
else
  rm -f "$lock_file"
fi

exit 0
