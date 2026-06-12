#!/usr/bin/env bash
# swarm-respawn.sh — restart a crashed/stopped stream (e2e-audit swarm-4).
#
# Extracted from commands/swarm/respawn.md so the coordinator (and
# fleet-reconcile.sh --respawn) can invoke it programmatically. Atomic fleet
# writes (same-dir tempfile + mv) replace the old fixed /tmp/fleet.json.
#
# Usage: swarm-respawn.sh <stream-id> [--budget <usd>] [--max-turns <n>]

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

STREAM="${1:-}"
[ -z "$STREAM" ] && { echo "Usage: $0 <stream-id> [--budget <usd>] [--max-turns <n>]" >&2; exit 2; }
shift
BUDGET=5; MAX_TURNS=200
while [ $# -gt 0 ]; do
  case "$1" in
    --budget) BUDGET="${2:?--budget needs a value}"; shift 2 ;;
    --max-turns) MAX_TURNS="${2:?--max-turns needs a value}"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

FLEET=.swarms/coordinator/fleet.json
[ -d ".swarms/streams/$STREAM" ] || { echo "No such stream: .swarms/streams/$STREAM" >&2; exit 1; }
[ -f "$FLEET" ] || { echo "fleet.json missing" >&2; exit 1; }

fleet_write() { # fleet_write <jq-program> [jq args...]
  local prog="$1"; shift
  local tmp
  tmp=$(mktemp "$(dirname "$FLEET")/.fleet.json.XXXXXX")
  if jq "$@" "$prog" "$FLEET" > "$tmp"; then
    mv -f "$tmp" "$FLEET"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Try native respawn first — preserves session state if the daemon held it
if claude respawn "$STREAM" 2>/dev/null; then
  echo "Native respawn succeeded for $STREAM"
  fleet_write '.fleet[$id].status = "respawned" | .fleet[$id].respawned_at = (now|todate)' --arg id "$STREAM"
  echo "$(date -Iseconds) $STREAM     Native respawn" >> .swarms/coordinator/decisions.log
  exit 0
fi

echo "Native respawn failed; spawning fresh session..."
resume_prompt=$(cat <<EOF
Resume stream $STREAM. The previous session may have made partial progress.

BEFORE starting any task:
1. Read .swarms/streams/$STREAM/brief.md (your scope and allocation)
2. Read .swarms/streams/$STREAM/task.json (current task + qa_attempts counter)
3. Read .swarms/streams/$STREAM/progress.md (what was done)
4. Read the latest .swarms/streams/$STREAM/handoff-*.yaml (state at last checkpoint)
5. Inspect WIP commits on the branch: \`git log --oneline | grep '^[0-9a-f]\+ WIP:'\` — they hold step-level state

Then continue from where the prior session left off. Use .claude/skills/wip-checkpoint to checkpoint as you go.
EOF
)

# JUSTIFIED: claude --bg stderr suppressed — a failed spawn yields an empty session id, handled by the guard below
sid=$(claude --bg \
     -n "$STREAM" \
     -w "$STREAM" \
     --agent feature-stream \
     --append-system-prompt-file ".swarms/streams/$STREAM/brief.md" \
     --max-turns "$MAX_TURNS" \
     --max-budget-usd "$BUDGET" \
     --output-format stream-json \
     -p "$resume_prompt" 2>/dev/null | jq -r '.session_id // empty' | head -1)

if [ -z "$sid" ]; then
  echo "FAILED to spawn fresh session for $STREAM" >&2
  exit 1
fi

fleet_write '.fleet[$id] = {sessionId: $sid, status: "respawned", spawned: (now|todate), worktree: (".claude/worktrees/" + $id), branch: $id}' \
  --arg id "$STREAM" --arg sid "$sid"

echo "Respawned $STREAM as fresh session $sid"
echo "$(date -Iseconds) $STREAM     Respawned (fresh session $sid, native respawn unavailable)" >> .swarms/coordinator/decisions.log
exit 0
