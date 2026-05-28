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
  n="$(grep -cE '^- \[!\]' tasks/TASKS.md || echo 0)"
  echo
  echo "$n failed task(s). Retry one with: bash .claude/scripts/requeue-failed.sh --reset <T-id>"
  echo "Retry ONLY after addressing the root cause — these already exhausted 3 self-heal attempts."
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
with_tasks_lock _reset
echo "✓ Re-opened ${target} → [ ] (requeued_at ${now}). It re-enters the queue as an unblocked task."
