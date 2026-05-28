#!/usr/bin/env bash
# Session-start banner that surfaces a warning if the overnight routine appears
# to have missed its window. Compares OVERNIGHT_REPORT.md mtime vs expected
# schedule (default: daily at 23:00).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Was a routine expected last night?
# Heuristic: if it's after 09:00 today and the report mtime is > 36h old, alert.
report_file="OVERNIGHT_REPORT.md"

if [ ! -f "$report_file" ]; then
  # Never ran — silent (could be first day)
  exit 0
fi

# Cross-platform mtime in seconds since epoch
if stat -c %Y "$report_file" >/dev/null 2>&1; then
  mtime=$(stat -c %Y "$report_file")
elif stat -f %m "$report_file" >/dev/null 2>&1; then
  mtime=$(stat -f %m "$report_file")
else
  exit 0
fi

now=$(date +%s)
age_h=$(( (now - mtime) / 3600 ))

# Output as additionalContext for SessionStart
if [ "$age_h" -ge 36 ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "[overnight watchdog] WARNING: last OVERNIGHT_REPORT.md is ${age_h}h old. The Cloud Routine may have missed its window. Check: (1) https://claude.ai/code/routines for last-run status; (2) Anthropic status page; (3) try bash .claude/scripts/local-overnight-build.sh as fallback."
  }
}
EOF
fi

exit 0
