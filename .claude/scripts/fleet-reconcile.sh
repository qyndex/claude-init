#!/usr/bin/env bash
# fleet-reconcile.sh — crash reconciliation for the swarm fleet (e2e-audit swarm-4).
#
# fleet.json says "running"; reality is whatever `claude agents --json` reports.
# A daemon crash previously left phantom running/respawned entries that wedged
# redispatch forever (dispatch skips streams with non-terminal status). This
# diffs the two, marks vanished sessions crashed (with decisions.log entries),
# and — with --respawn — re-launches each crashed stream via swarm-respawn.sh,
# budget-guarded by MAX_RESPAWNS (default 3 per invocation).
#
# Usage: fleet-reconcile.sh [--respawn] [--dry-run]
# Exit: 0 = reconciled (possibly zero changes) · 1 = environment error

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

FLEET=.swarms/coordinator/fleet.json
RESPAWN=0 DRY=0
for arg in "$@"; do
  case "$arg" in
    --respawn) RESPAWN=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 64 ;;
  esac
done

[ -f "$FLEET" ] || { echo "no fleet.json — nothing to reconcile"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

# Live session ids as the daemon reports them. An unavailable CLI or daemon
# yields an EMPTY live set — every running entry would be marked crashed, which
# is wrong when the daemon is merely restarting. Fail safe: require the command
# to SUCCEED; on failure, report and exit without touching the fleet.
if ! agents_json=$(claude agents --json 2>/dev/null); then
  echo "claude agents --json unavailable — refusing to reconcile against an unknown live set" >&2
  exit 1
fi
# JUSTIFIED: jq muted — an unexpected agents payload shape yields an empty live set, but the command above already proved the daemon is reachable
live_ids=$(printf '%s' "$agents_json" | jq -r '.. | .session_id? // .sessionId? // empty' 2>/dev/null | sort -u)

active=$(jq -r '.fleet | to_entries[] | select(.value.status == "running" or .value.status == "respawned") | "\(.key)\t\(.value.sessionId // "")"' "$FLEET")
[ -n "$active" ] || { echo "no running/respawned entries — fleet clean"; exit 0; }

crashed=0
respawned=0
while IFS=$'\t' read -r stream sid; do
  [ -n "$stream" ] || continue
  if [ -n "$sid" ] && printf '%s\n' "$live_ids" | grep -qx "$sid"; then
    continue  # session is live
  fi
  if [ "$DRY" = 1 ]; then
    echo "DRY: $stream (session ${sid:-none}) vanished — would mark crashed"
    continue
  fi
  tmp=$(mktemp "$(dirname "$FLEET")/.fleet.json.XXXXXX")
  if jq --arg id "$stream" '.fleet[$id].status = "crashed" | .fleet[$id].crashed_at = (now|todate)' "$FLEET" > "$tmp"; then
    mv -f "$tmp" "$FLEET"
  else
    rm -f "$tmp"
  fi
  echo "$(date -Iseconds) $stream     CRASHED (session ${sid:-unknown} not in claude agents) — fleet-reconcile" >> .swarms/coordinator/decisions.log
  echo "reconciled: $stream running -> crashed (session ${sid:-none} vanished)"
  crashed=$((crashed + 1))
  if [ "$RESPAWN" = 1 ] && [ "$respawned" -lt "${MAX_RESPAWNS:-3}" ]; then
    if bash .claude/scripts/swarm-respawn.sh "$stream"; then
      respawned=$((respawned + 1))
    else
      echo "WARN: respawn failed for $stream — left crashed for manual triage" >&2
    fi
  fi
done <<EOF_ACTIVE
$active
EOF_ACTIVE

echo "fleet-reconcile: $crashed crashed, $respawned respawned"
exit 0
