#!/usr/bin/env bash
# Failed-task requeue / surface — Round 13 Fix 3.
#
# Tasks marked [!] (self-heal exhausted its 3 attempts, or a gate hard-failed) were
# INVISIBLE: /triage only listed [ ] tasks and the overnight build only picks
# status-pending work. So [!] tasks rotted with no path back into the queue.
#
# This surfaces them, and — with --reset — deliberately re-opens ONE to [ ] with a
# requeued_at stamp, so a human (or a fresh autopilot pass trying a DIFFERENT approach)
# retries on purpose. We never auto-requeue every [!] on a timer: that would just loop
# the same failure forever. Re-opening is always an explicit decision.
#
# Usage:
#   requeue-failed.sh                 # report: list all [!] tasks (default)
#   requeue-failed.sh --reset T-42    # re-open T-42 → [ ], stamp requeued_at

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
. "$ROOT/.claude/scripts/lib/tasks-lib.sh"
[ -f tasks/TASKS.md ] || { echo "no tasks/TASKS.md"; exit 0; }

mode="report"; target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reset) mode="reset"; target="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

if [ "$mode" = "report" ]; then
  echo "# Failed tasks ([!]) awaiting a requeue decision"
  echo
  awk '
    /^- \[!\]/ { print; insummary=1; next }
    insummary && /^[[:space:]]+summary:/ { print "    " $0; insummary=0 }
    /^- \[/ && !/^- \[!\]/ { insummary=0 }
  ' tasks/TASKS.md
  # JUSTIFIED: the fallback yields a zero count when grep finds no failed-task markers (exit 1) — reporting zero failed tasks is the correct outcome, not an abort
  n="$(grep -cE '^- \[!\]' tasks/TASKS.md || echo 0)"
  echo
  echo "$n failed task(s). Retry one with: bash .claude/scripts/requeue-failed.sh --reset <T-id>"
  echo "Retry ONLY after addressing the root cause — these already exhausted 3 self-heal attempts."

  # e2e-audit failure-recovery-3: surface stale [~] (possible orphans the
  # reconciler hasn't caught) and [b] tasks whose deps are ALL [x] (unblockable).
  STALE_HOURS="${STALE_HOURS:-12}"
  stale=$(awk -v cutoff="$(date -v-"${STALE_HOURS}"H +%Y-%m-%d 2>/dev/null || date -d "-${STALE_HOURS} hours" +%Y-%m-%d 2>/dev/null)" '
    /^- \[~\] T-[0-9]+/ {
      lt = ""
      if (match($0, /last_touched: *[0-9-]+/)) { lt = substr($0, RSTART, RLENGTH); sub(/last_touched: */, "", lt) }
      if (lt == "" || lt <= cutoff) print "  " $0
    }
  ' tasks/TASKS.md)
  if [ -n "$stale" ]; then
    echo ""
    echo "# In-progress [~] older than ${STALE_HOURS}h (possible orphans — run orphan-reconcile.sh)"
    printf '%s\n' "$stale"
  fi
  done_ids=" $(grep -oE '^- \[x\] T-[0-9]+' tasks/TASKS.md | grep -oE 'T-[0-9]+' | tr '\n' ' ')"
  unblockable=""
  while IFS= read -r bline; do
    deps=$(printf '%s' "$bline" | grep -oE 'deps: *T-[0-9]+( *, *T-[0-9]+)*' | sed 's/deps: *//; s/ //g')
    [ -n "$deps" ] || continue
    all_done=1
    for dep in ${deps//,/ }; do
      case "$done_ids" in *" $dep "*) ;; *) all_done=0; break ;; esac
    done
    [ "$all_done" = 1 ] && unblockable="${unblockable}  ${bline}\n"
    # JUSTIFIED: grep exit 1 when no [b] tasks exist — zero loop iterations is the correct empty report
  done < <(grep -E '^- \[b\] T-[0-9]+' tasks/TASKS.md 2>/dev/null)
  if [ -n "$unblockable" ]; then
    echo ""
    echo "# Blocked [b] tasks whose deps are ALL [x] — unblock with task-status.sh <id> pending"
    printf '%b' "$unblockable"
  fi

  # AC-32: also show recent lane.error events from swarm JSONL logs
  if [ -d .swarms/events ] && command -v jq >/dev/null 2>&1; then
    echo ""
    echo "# Recent lane.error events from swarm JSONL"
    # JUSTIFIED: find errors muted — .swarms/events may not exist yet; an empty dir produces no output, which is the correct zero-error report
    find .swarms/events -name '*.jsonl' -type f 2>/dev/null | while read -r evfile; do
      stream_id=$(basename "$evfile" .jsonl)
      jq -r --arg sid "$stream_id" \
        'select(.event == "lane.error") |
         "  [\(.ts // "?")] stream=\($sid) exit=\(.payload.exit_code // "?") kind=\(.payload.error_kind // "unknown") retryable=\(.payload.retryable // false)"' \
        "$evfile" 2>/dev/null | tail -5
    done
  fi
  exit 0
fi

[ -z "$target" ] && { echo "usage: requeue-failed.sh --reset T-<id>"; exit 1; }
grep -qE "^- \[!\] ${target}([^0-9]|\$)" tasks/TASKS.md || { echo "No failed task ${target} found ([!])."; exit 1; }

now="$(date -Iseconds)"
_reset() {
  local tmp="tasks/TASKS.md.tmp.$$"
  awk -v t="$target" -v now="$now" '
    $0 ~ ("^- \\[!\\] " t "([^0-9]|$)") {
      sub(/^- \[!\]/, "- [ ]")
      print
      print "  requeued_at: " now
      next
    }
    { print }
  ' tasks/TASKS.md > "$tmp" && mv "$tmp" tasks/TASKS.md
}
# e2e-audit failure-recovery-6: check the lock rc and re-grep the flip before
# claiming success — a busy lock or failed awk must not print ✓ for a reset
# that never happened (hotfix-to-task.sh pattern).
with_tasks_lock _reset
lock_rc=$?
if [ "$lock_rc" -eq 75 ]; then
  echo "requeue-failed: TASKS.md lock busy — nothing changed; retry"; exit 75
fi
if ! grep -qE "^- \[ \] ${target}([^0-9]|\$)" tasks/TASKS.md; then
  echo "requeue-failed: reset did NOT take (rc=$lock_rc) — ${target} is not [ ] in tasks/TASKS.md"; exit 1
fi
echo "✓ Re-opened ${target} → [ ] (requeued_at ${now}). It re-enters the queue as an unblocked task."
