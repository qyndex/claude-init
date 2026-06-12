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
  # JUSTIFIED: jq error output discarded — a corrupt state file yields jq's empty output; the // 0 default plus the else-branch keep last_run/session_count well-defined
  last_run=$(jq -r '.last_run_epoch // 0' "$state_file" 2>/dev/null)
  # JUSTIFIED: jq error output discarded — same; a corrupt state file degrades to a session_count of 0 rather than crashing the Stop hook
  session_count=$(jq -r '.session_count // 0' "$state_file" 2>/dev/null)
else
  last_run=0
  session_count=0
fi

# Increment session count
session_count=$((session_count + 1))

# ─── Gap-audit G25: instinct extraction (the previously-dead middle stage) ──
# Self-gates on ≥ INSTINCT_EXTRACT_MIN new observations, so calling it on every
# Stop costs one wc -l when below threshold. Runs detached — extraction must
# never delay the user's stop.
if [ -x .claude/scripts/instinct-extract.sh ]; then
  # JUSTIFIED: detached best-effort spawn — extraction failure is logged by the script itself to .claude/hooks/.log/instinct.log
  nohup bash .claude/scripts/instinct-extract.sh >/dev/null 2>&1 &
fi

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
# JUSTIFIED: ls error output discarded — an unreadable proposed dir yields empty output, treated as "no pending proposals", which safely allows the dream to proceed
if [ -d .claude/memory.proposed ] && [ "$(ls -A .claude/memory.proposed 2>/dev/null)" ]; then
  # JUSTIFIED: jq error output discarded — a corrupt state file degrades awaiting_review to empty (not "true"), so the review gate fails open and the dream proceeds
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
  # Gap-audit G13: the skill-creation queue (skills/ proposals + _candidates.jsonl)
  # lives in the same .proposed dir the dream mirror rebuilds — preserve it across
  # the rm/cp or pending proposals are silently destroyed.
  skills_keep=""
  if [ -d .claude/memory.proposed/skills ]; then
    skills_keep=$(mktemp -d 2>/dev/null || echo "")
    if [ -n "$skills_keep" ]; then
      cp -r .claude/memory.proposed/skills "$skills_keep/skills" 2>/dev/null || skills_keep=""
    fi
  fi

  # Mirror canonical → proposed for the dream to mutate
  # JUSTIFIED: rm error output discarded — clearing the prior mirror is best-effort cleanup; the dir may legitimately not exist before the cp below recreates it
  rm -rf .claude/memory.proposed 2>/dev/null
  cp -r .claude/memory .claude/memory.proposed

  if [ -n "$skills_keep" ] && [ -d "$skills_keep/skills" ]; then
    rm -rf .claude/memory.proposed/skills 2>/dev/null
    cp -r "$skills_keep/skills" .claude/memory.proposed/skills
    rm -rf "$skills_keep" 2>/dev/null
  fi

  # Gap-audit G12: consume task-signature candidates — previously written by
  # task-signature-detector.sh but read by nothing. The dream session drafts a
  # proposal per fresh candidate via skill-creator (still human-gated at
  # /dream-review --approve-skill).
  cand_note=""
  cand_file=.claude/memory.proposed/skills/_candidates.jsonl
  if [ -s "$cand_file" ]; then
    cand_note=" ALSO: read ${cand_file}; for each candidate without consumed:true, invoke the skill-creator skill to draft a proposal under .claude/memory.proposed/skills/<suggested_slug>/ (proposal only — never activate), then rewrite that candidate line adding consumed:true."
  fi

  nohup bash -c "
    set -uo pipefail
    claude -p --bare 'Invoke the dream skill: consolidate .claude/memory.proposed/ and .claude/memory/.cache/checkpoints/ since $last_run. Keep .claude/memory.proposed/MEMORY.md under 200 lines. Do NOT touch .claude/memory/ (canonical) — only the .proposed copy.${cand_note}' 2>&1 \
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
