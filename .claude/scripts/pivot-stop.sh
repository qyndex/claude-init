#!/usr/bin/env bash
# /pivot stop — Round 7 E.
#
# Halts in-flight work safely before a strategic pivot. Lists every active
# stream + scheduled task + tonight's Cloud Routine; preserves WIP via
# squash-wip.sh with a PIVOT-STOPPED marker; logs structured stop reason.
#
# Usage: bash .claude/scripts/pivot-stop.sh <reason-or-new-initiative-id>

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

reason="${1:-pivot-pending}"

echo "→ /pivot stop — preparing safe halt of in-flight work"
echo "  Reason: $reason"
echo

mkdir -p .claude/state/pause-flags

# ─── 1. List active streams ─────────────────────────────────────────────
echo "[Active swarm streams]"
if [ -f .swarms/coordinator/fleet.json ] && command -v jq >/dev/null; then
  running=$(jq -r '.fleet | to_entries[] | select(.value.status == "running" or .value.status == "respawned") | .key' .swarms/coordinator/fleet.json)
  if [ -n "$running" ]; then
    echo "$running" | sed 's/^/  - /'
  else
    echo "  (none)"
  fi
else
  running=""
  echo "  (no fleet.json)"
fi

# ─── 2. List scheduled tasks ────────────────────────────────────────────
echo
echo "[Scheduled tasks]"
scheduled=$(find .claude/state/pause-flags -name '*.flag' 2>/dev/null | wc -l | tr -d ' ')
echo "  $scheduled tasks currently flagged paused"
echo "  Run \`claude\` and use /tasks list to enumerate all registered tasks"

# ─── 3. Cloud Routine state ─────────────────────────────────────────────
echo
echo "[Cloud Routine (overnight-build)]"
today_skip=".claude/state/skip-overnight-$(date +%Y-%m-%d)"
if [ -f "$today_skip" ]; then
  echo "  already skipped for $(date +%Y-%m-%d)"
else
  echo "  scheduled to run tonight at 23:00 UTC"
fi

# ─── 4. Decide what to stop ─────────────────────────────────────────────
echo
echo "→ Stopping all in-flight work for pivot ($reason)"
echo

stopped_streams=""
stopped_tasks=0
skipped_routine="no"

# Stop streams
if [ -n "$running" ]; then
  for s in $running; do
    echo "  → stopping stream $s"

    # Squash WIP commits with PIVOT-STOPPED marker
    if [ -d ".claude/worktrees/$s" ]; then
      (
        cd ".claude/worktrees/$s"
        if git log --oneline -5 --grep='^WIP:' >/dev/null 2>&1; then
          wip_count=$(git log --oneline --grep='^WIP:' main..HEAD 2>/dev/null | wc -l | tr -d ' ')
          if [ "$wip_count" -gt 0 ]; then
            echo "    squashing $wip_count WIP commits with PIVOT-STOPPED marker"
            bash "$ROOT/.claude/scripts/squash-wip.sh" "PIVOT-STOPPED($reason): squash of $wip_count WIPs" 2>/dev/null || true
          fi
        fi
      )
    fi

    # Update fleet.json
    jq --arg s "$s" --arg r "$reason" --arg ts "$(date -Iseconds)" \
      '.fleet[$s].status = "stopped_for_pivot" |
       .fleet[$s].pivot_reason = $r |
       .fleet[$s].stopped_at = $ts |
       ._schema_version = 3' \
      .swarms/coordinator/fleet.json > /tmp/f && mv /tmp/f .swarms/coordinator/fleet.json

    stopped_streams="$stopped_streams,$s"
  done
  stopped_streams=$(echo "$stopped_streams" | sed 's/^,//')
fi

# Skip tonight's Cloud Routine
touch "$today_skip"
echo "$reason" > "$today_skip"
skipped_routine="yes"
echo "  → touched $today_skip (Cloud Routine pre_flight will see this and abort)"

# Note: scheduled-task pause is operator-driven (claude tasks pause <name>)
# we can't actually pause them from a hook; we leave a state-flag the operator
# can check when re-enabling
cat > .claude/state/pause-flags/_pivot-pending.flag <<EOF
Pivot in progress: $reason
Stopped at: $(date -Iseconds)
Re-enable scheduled tasks via: claude tasks resume <name>
EOF

# ─── 5. Log decision ────────────────────────────────────────────────────
mkdir -p .swarms/coordinator
{
  printf '%s PIVOT-STOP reason="%s" streams=[%s] tasks_flagged=%d routine_skipped=%s\n' \
    "$(date -Iseconds)" "$reason" "$stopped_streams" "$stopped_tasks" "$skipped_routine"
} >> .swarms/coordinator/decisions.log

# ─── 6. Surface to operator ─────────────────────────────────────────────
echo
echo "✓ Pivot stop complete"
echo
echo "  Streams stopped:        [$stopped_streams]"
echo "  Cloud Routine tonight:  $skipped_routine (touched $today_skip)"
echo "  Pause flag set:         .claude/state/pause-flags/_pivot-pending.flag"
echo
echo "Next:"
echo "  1. Decide the pivot verb: /pivot drop|pause|supersede <target-id>"
echo "  2. Sunk-cost report:     bash .claude/scripts/cost-report.sh --by-initiative <id>"
echo "  3. Resume (if pause):    rm $today_skip && rm .claude/state/pause-flags/_pivot-pending.flag"
echo "  4. Restart streams:      bash .claude/scripts/swarm-dispatch.sh --only <stream-ids>"
