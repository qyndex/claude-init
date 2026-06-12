#!/usr/bin/env bash
# Orphan reconciler (e2e-audit failure-recovery-3).
#
# A session killed mid-task leaves its [~] marker forever — the picker skips it,
# requeue ignores it, the loop-control cap never hears about it. This flips
# stale [~] tasks to [!] (with an orphaned_at note) via task-status.sh — the
# sanctioned mutator — which also feeds `loop-iteration.sh record abort` so the
# consecutive-aborts machine stays truthful.
#
# "Stale" = no live heartbeat anywhere: every session heartbeat file
# (.claude/memory/.cache/current-session.json + .claude/sessions/*/*.json) has
# last_heartbeat_at older than ORPHAN_MINUTES (default 120). A fresh heartbeat
# from ANY session means tasks may legitimately be in flight — touch nothing
# (task blocks carry no session attribution, so the rule must be global).
#
# Callers: loop-iteration.sh pre-flight; session-start-context.sh (surface).
# Usage: orphan-reconcile.sh [--dry-run]

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

ORPHAN_MINUTES="${ORPHAN_MINUTES:-120}"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

[ -f tasks/TASKS.md ] || exit 0
in_progress=$(grep -oE '^- \[~\] T-[0-9]+' tasks/TASKS.md | grep -oE 'T-[0-9]+' || true)
[ -n "$in_progress" ] || exit 0

# Freshest heartbeat across all session state files
now=$(date +%s)
freshest=0
for hb in .claude/memory/.cache/current-session.json .claude/sessions/*/*.json; do
  [ -f "$hb" ] || continue
  # JUSTIFIED: jq muted — a partially-written heartbeat from a killed session yields empty, treated as no signal
  ts=$(jq -r '.last_heartbeat_at // empty' "$hb" 2>/dev/null)
  [ -n "$ts" ] || continue
  # JUSTIFIED: both date dialects probed (BSD then GNU); an unparsable timestamp contributes 0 (ancient)
  epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "${ts%%[+Z]*}" +%s 2>/dev/null || date -d "$ts" +%s 2>/dev/null || echo 0)
  [ "$epoch" -gt "$freshest" ] && freshest=$epoch
done

age_min=$(( (now - freshest) / 60 ))
if [ "$freshest" -gt 0 ] && [ "$age_min" -lt "$ORPHAN_MINUTES" ]; then
  echo "live heartbeat ${age_min}m ago — [~] tasks may be in flight; nothing reconciled"
  exit 0
fi

flipped=0
for tid in $in_progress; do
  if [ "$DRY" = 1 ]; then
    echo "DRY: would flip $tid [~] -> [!] (orphaned; freshest heartbeat ${age_min}m ago)"
    continue
  fi
  if bash .claude/scripts/task-status.sh "$tid" failed --note "orphaned_at=$(date -Iseconds) (no live session heartbeat for ${age_min}m)" >/dev/null; then
    echo "reconciled: $tid [~] -> [!] (orphaned)"
    flipped=$((flipped + 1))
  else
    echo "WARN: failed to flip $tid (lock busy or id missing)" >&2
  fi
done
[ "$flipped" -gt 0 ] && echo "$flipped orphaned task(s) flipped to [!] — surface via requeue-failed.sh"
exit 0
