#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects task state every turn and detects loops.
# Pattern from fengshao1227/ccg-workflow/templates/hooks/workflow-state.js.

set -uo pipefail

# shellcheck source=../scripts/lib/atomic-write.sh
. "$(cd "$(dirname "$0")/../scripts/lib" && pwd)/atomic-write.sh"

mkdir -p .claude/hooks/.log .swarms/coordinator
state_file=".swarms/coordinator/workflow-state.json"

# Read prompt from stdin (best-effort — we don't actually need it; we inject state)
# JUSTIFIED: we drain stdin only to avoid a broken pipe; the prompt content is unused, so a read error is irrelevant
cat > /dev/null 2>&1 || true

# Build current state
ctx=""
phase=""
next_task=""
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  # Not a git repo — write a valid no-op state and exit cleanly
  replace_atomic "$state_file" '{"phase":null,"next":null,"streak":0,"warned_at":0}'
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}\n'
  exit 0
fi
if true; then
  # JUSTIFIED: detached HEAD makes symbolic-ref exit non-zero — the explicit "detached" fallback is the intended value, not a hidden failure
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")

  # Active spec / plan
  # JUSTIFIED: no active spec/plan yet (early in the workflow) makes the glob fail — "none" is the documented sentinel the phase logic below keys on
  spec=$(ls -t specs/active/*.md 2>/dev/null | head -1 || echo "none")
  plan=$(ls -t plans/active/*.md 2>/dev/null | head -1 || echo "none")

  # Pending task. The T-[0-9]+ guard is load-bearing: TASKS.md's format section
  # contains a literal "- [ ] T-NNN | spec:NNN ..." template line that the bare
  # '^- \[ \]' pattern matched, producing a placeholder "next task" for dozens
  # of consecutive turns (memory-system review, 2026-06-12).
  # JUSTIFIED: no pending tasks (or no TASKS.md) makes grep exit 1 — "none" is the intended sentinel shown in the injected state line
  next_task=$(grep -m1 -E '^- \[ \] T-[0-9]+' tasks/TASKS.md 2>/dev/null | sed 's/^- \[ \]//' | head -c 100 || echo "none")
  [ -z "$next_task" ] && next_task="none"

  # Current phase derived from artifact state — all 8 phases (AC-19)
  # JUSTIFIED: grep-as-boolean for phase detection — missing files or non-matching lines advance phase, all errors are intentional false-negatives
  if [ "$spec" = "none" ] && [ ! -f .claude/skills/constitution/SKILL.md ] && [ ! -f .claude/CLAUDE.md ]; then
    phase="constitute"
  elif [ "$spec" = "none" ]; then
    phase="specify"
  elif grep -q 'status: draft' "$spec" 2>/dev/null && grep -q '\[OQ' "$spec" 2>/dev/null; then
    phase="clarify"
  elif grep -q 'status: draft' "$spec" 2>/dev/null; then
    phase="specifying"
  elif [ "$plan" = "none" ] || grep -q 'status: draft' "$plan" 2>/dev/null; then
    phase="planning"
  elif ! grep -qE '^- \[ \] T-[0-9]+' tasks/TASKS.md 2>/dev/null && ! grep -qE '^- \[~\] T-[0-9]+' tasks/TASKS.md 2>/dev/null; then
    # No tasks at all — check if analyze marker present
    spec_id=$(basename "$spec" .md 2>/dev/null | grep -oE '^[0-9]+')
    if [ -n "$spec_id" ] && [ ! -f ".claude/state/analyze-${spec_id}.json" ]; then
      phase="tasks"
    else
      phase="verify-review-ship"
    fi
  else
    # Tasks exist — check if analyze step done
    spec_id=$(basename "$spec" .md 2>/dev/null | grep -oE '^[0-9]+')
    if [ -n "$spec_id" ] && ! [ -f ".claude/state/analyze-${spec_id}.json" ] && ! grep -qE '^- \[x\] T-[0-9]+' tasks/TASKS.md 2>/dev/null; then
      phase="analyze"
    elif grep -qE '^- \[ \] T-[0-9]+' tasks/TASKS.md 2>/dev/null || grep -qE '^- \[~\] T-[0-9]+' tasks/TASKS.md 2>/dev/null; then
      phase="implementing"
    else
      phase="verify-review-ship"
    fi
  fi

  # JUSTIFIED: basename is purely cosmetic for the state banner — any odd path value degrades to a blank field, never an error
  ctx="<state>Branch: $branch | Phase: $phase | Spec: $(basename "$spec" .md 2>/dev/null) | Plan: $(basename "$plan" .md 2>/dev/null) | Next: $next_task</state>"
fi

# Loop detection — if same phase+next_task appears 3+ turns in a row, warn
# JUSTIFIED: first turn has no prior state file — `|| echo '{}'` gives a valid empty object so the jq reads below all resolve to their // defaults (fresh loop-detection state)
prev_state=$(cat "$state_file" 2>/dev/null || echo '{}')
prev_phase=$(printf '%s' "$prev_state" | jq -r '.phase // ""' 2>/dev/null)
prev_next=$(printf '%s' "$prev_state" | jq -r '.next // ""' 2>/dev/null)
# JUSTIFIED: same fresh/empty state object — jq // defaults give streak/warned_at of 0 when absent; suppression only hides parse noise on a corrupt state file (also reset to 0)
streak=$(printf '%s' "$prev_state" | jq -r '.streak // 0' 2>/dev/null)
warned_at=$(printf '%s' "$prev_state" | jq -r '.warned_at // 0' 2>/dev/null)

if [ "$phase" = "$prev_phase" ] && [ "$next_task" = "$prev_next" ]; then
  streak=$((streak + 1))
else
  streak=1
  warned_at=0  # reset warning state when phase/task changes
fi

# Persist
# JUSTIFIED: jq -R only JSON-string-escapes a value; if jq is somehow unavailable the `|| echo '""'` writes an empty JSON string, keeping the state file valid JSON rather than emitting a raw unescaped value
state_json=$(printf '{"phase":%s,"next":%s,"streak":%d,"warned_at":%d}' \
  "$(printf '%s' "$phase" | jq -R . 2>/dev/null || echo '""')" \
  "$(printf '%s' "$next_task" | jq -R . 2>/dev/null || echo '""')" \
  "$streak" \
  "$warned_at")
replace_atomic "$state_file" "$state_json"

# Round 5 D5: emit full BREAK-LOOP block ONCE per stuck-phase, not every turn.
# Previously re-emitted ~150 tokens every turn during loops — exactly when the
# context cache is most valuable.
if [ "$streak" -ge 3 ] && [ "$warned_at" = "0" ]; then
  # First time hitting streak≥3 in this phase — emit the full protocol once
  ctx="$ctx <warn>LOOP DETECTED: phase=\"$phase\" repeated $streak turns. BREAK-LOOP PROTOCOL: (1) /rewind to drop the last failed approach; (2) try a different angle — re-read the spec, ask the user a sharpening question; (3) if 2 doesn't unblock, invoke .claude/skills/self-heal (debugger → implementer); (4) if 3 cycles fail, escalate — mark task [!] in tasks/TASKS.md and surface in handoff.</warn>"
  # Mark warned so subsequent turns in this loop are quiet
  # JUSTIFIED: same JSON-string escaping of phase/next — `|| echo '""'` keeps the persisted warned-state valid JSON even with jq absent
  warned_json=$(printf '{"phase":%s,"next":%s,"streak":%d,"warned_at":%d}' \
    "$(printf '%s' "$phase" | jq -R . 2>/dev/null || echo '""')" \
    "$(printf '%s' "$next_task" | jq -R . 2>/dev/null || echo '""')" \
    "$streak" \
    "$streak")
  replace_atomic "$state_file" "$warned_json"
elif [ "$streak" -ge 3 ]; then
  # Already warned this phase — short reminder only, no full protocol.
  # Gap-audit G4: no streak integer — an incrementing number makes the injected
  # string unique every turn, exactly during loops (the worst time for cache churn).
  ctx="$ctx <warn>still stuck in this phase; see BREAK-LOOP above</warn>"
fi

# Emit
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "$ctx"
  }
}
EOF

exit 0
