#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects task state every turn and detects loops.
# Pattern from fengshao1227/ccg-workflow/templates/hooks/workflow-state.js.

set -uo pipefail

mkdir -p .claude/hooks/.log .swarms/coordinator
state_file=".swarms/coordinator/workflow-state.json"

# Read prompt from stdin (best-effort — we don't actually need it; we inject state)
cat > /dev/null 2>&1 || true

# Build current state
ctx=""
phase=""
next_task=""
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  # Not a git repo — write a valid no-op state and exit cleanly
  printf '{"phase":null,"next":null,"streak":0,"warned_at":0}' > "$state_file"
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}\n'
  exit 0
fi
if true; then
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")

  # Active spec / plan
  spec=$(ls -t specs/active/*.md 2>/dev/null | head -1 || echo "none")
  plan=$(ls -t plans/active/*.md 2>/dev/null | head -1 || echo "none")

  # Pending task
  next_task=$(grep -m1 '^- \[ \]' tasks/TASKS.md 2>/dev/null | sed 's/^- \[ \]//' | head -c 100 || echo "none")

  # Current phase derived from artifact state
  if [ "$spec" = "none" ]; then phase="constitute-or-specify"
  elif grep -q 'status: draft' "$spec" 2>/dev/null; then phase="specifying"
  elif [ "$plan" = "none" ]; then phase="planning"
  elif grep -q 'status: draft' "$plan" 2>/dev/null; then phase="planning"
  elif grep -q '^- \[ \]' tasks/TASKS.md 2>/dev/null; then phase="implementing"
  else phase="verifying-or-shipping"; fi

  ctx="<state>Branch: $branch | Phase: $phase | Spec: $(basename "$spec" .md 2>/dev/null) | Plan: $(basename "$plan" .md 2>/dev/null) | Next: $next_task</state>"
fi

# Loop detection — if same phase+next_task appears 3+ turns in a row, warn
prev_state=$(cat "$state_file" 2>/dev/null || echo '{}')
prev_phase=$(printf '%s' "$prev_state" | jq -r '.phase // ""' 2>/dev/null)
prev_next=$(printf '%s' "$prev_state" | jq -r '.next // ""' 2>/dev/null)
streak=$(printf '%s' "$prev_state" | jq -r '.streak // 0' 2>/dev/null)
warned_at=$(printf '%s' "$prev_state" | jq -r '.warned_at // 0' 2>/dev/null)

if [ "$phase" = "$prev_phase" ] && [ "$next_task" = "$prev_next" ]; then
  streak=$((streak + 1))
else
  streak=1
  warned_at=0  # reset warning state when phase/task changes
fi

# Persist
printf '{"phase":%s,"next":%s,"streak":%d,"warned_at":%d}' \
  "$(printf '%s' "$phase" | jq -R . 2>/dev/null || echo '""')" \
  "$(printf '%s' "$next_task" | jq -R . 2>/dev/null || echo '""')" \
  "$streak" \
  "$warned_at" > "$state_file"

# Round 5 D5: emit full BREAK-LOOP block ONCE per stuck-phase, not every turn.
# Previously re-emitted ~150 tokens every turn during loops — exactly when the
# context cache is most valuable.
if [ "$streak" -ge 3 ] && [ "$warned_at" = "0" ]; then
  # First time hitting streak≥3 in this phase — emit the full protocol once
  ctx="$ctx <warn>LOOP DETECTED: phase=\"$phase\" repeated $streak turns. BREAK-LOOP PROTOCOL: (1) /rewind to drop the last failed approach; (2) try a different angle — re-read the spec, ask the user a sharpening question; (3) if 2 doesn't unblock, invoke .claude/skills/self-heal (debugger → implementer); (4) if 3 cycles fail, escalate — mark task [!] in tasks/TASKS.md and surface in handoff.</warn>"
  # Mark warned so subsequent turns in this loop are quiet
  printf '{"phase":%s,"next":%s,"streak":%d,"warned_at":%d}' \
    "$(printf '%s' "$phase" | jq -R . 2>/dev/null || echo '""')" \
    "$(printf '%s' "$next_task" | jq -R . 2>/dev/null || echo '""')" \
    "$streak" \
    "$streak" > "$state_file"
elif [ "$streak" -ge 3 ]; then
  # Already warned this phase — short reminder only, no full protocol
  ctx="$ctx <warn>still stuck (streak=$streak); see BREAK-LOOP above</warn>"
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
