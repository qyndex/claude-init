#!/usr/bin/env bash
# gc-tasks.sh — archive old finished tasks when TASKS.md grows past the cap.
#
# When tasks/TASKS.md exceeds GC_TASKS_LINE_CAP lines, move [x]/[s] tasks whose
# completed/last_touched date is older than GC_TASKS_DONE_AGE_DAYS into
# tasks/archive/TASKS-YYYY-MM.md. Live ([ ]/[~]/[!]/[b]) tasks always stay.
# Idempotent: if nothing qualifies (already under cap, or no old done tasks),
# the file is left byte-identical.
#
# Overridable for tests: TASKS_FILE, TASKS_ARCHIVE_DIR, GC_TASKS_LINE_CAP,
# GC_TASKS_DONE_AGE_DAYS.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TASKS_FILE="${TASKS_FILE:-$ROOT/tasks/TASKS.md}"
TASKS_ARCHIVE_DIR="${TASKS_ARCHIVE_DIR:-$ROOT/tasks/archive}"
GC_TASKS_LINE_CAP="${GC_TASKS_LINE_CAP:-2000}"
GC_TASKS_DONE_AGE_DAYS="${GC_TASKS_DONE_AGE_DAYS:-30}"

# JUSTIFIED: missing TASKS.md means nothing to GC — exit cleanly, not an error.
[ -f "$TASKS_FILE" ] || exit 0

lines=$(wc -l <"$TASKS_FILE")
[ "$lines" -gt "$GC_TASKS_LINE_CAP" ] || exit 0   # under cap → nothing to do

cutoff_epoch=$(( $(date +%s) - GC_TASKS_DONE_AGE_DAYS * 86400 ))
# JUSTIFIED: BSD/GNU date portability — the BSD form is tried first, the GNU form is the fallback, and the final echo yields 0 (treated as "undatable, do not archive") for an unparseable date. The suppressed errors are the expected miss on whichever date flavor isn't installed.
date_to_epoch() { date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo 0; }

archive_month="$(date +%Y-%m)"
mkdir -p "$TASKS_ARCHIVE_DIR"
archive_file="$TASKS_ARCHIVE_DIR/TASKS-${archive_month}.md"

live_tmp="$(mktemp)"
arch_tmp="$(mktemp)"
trap 'rm -f "$live_tmp" "$arch_tmp"' EXIT

# A task block is the `- [..] T-..` marker line plus its indented continuation
# lines (summary/accept/etc). We decide per block: archive it (old + done/skipped)
# or keep it.
awk -v cutoff="$cutoff_epoch" -v age="$GC_TASKS_DONE_AGE_DAYS" \
    -v live="$live_tmp" -v arch="$arch_tmp" '
  function flush(block, marker,    d, ds, cmd, ep, archived) {
    if (block == "") return
    archived = 0
    # Only [x] done or [s] skipped blocks are archive candidates.
    if (marker ~ /^- \[[xs]\]/) {
      # Find a YYYY-MM-DD on the marker line (completed: or last_touched:).
      # JUSTIFIED: the date command below is built as an awk string for the same BSD/GNU portability fallback as date_to_epoch; the suppressed errors are the expected miss on the absent date flavor, and a 0 result means "undatable, keep the task".
      if (match(marker, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
        ds = substr(marker, RSTART, RLENGTH)
        cmd = "date -j -f %Y-%m-%d \"" ds "\" +%s 2>/dev/null || date -d \"" ds "\" +%s 2>/dev/null || echo 0"
        cmd | getline ep; close(cmd)
        if (ep != "" && ep+0 > 0 && ep+0 < cutoff) archived = 1
      }
    }
    if (archived) printf "%s", block >> arch
    else          printf "%s", block >> live
  }
  /^- \[/ {
    flush(block, marker)
    block = $0 "\n"; marker = $0; next
  }
  {
    if (marker != "") { block = block $0 "\n" }
    else { print >> live }   # preamble / headers before any task marker
  }
  END { flush(block, marker) }
' "$TASKS_FILE"

# If nothing was archived, leave the original untouched (idempotency).
if [ ! -s "$arch_tmp" ]; then
  exit 0
fi

# Append archived blocks (with a run header) to the month archive.
{
  echo
  echo "<!-- archived $(date -Iseconds) by gc-tasks.sh -->"
  cat "$arch_tmp"
} >>"$archive_file"

# Replace the live file atomically.
mv -f "$live_tmp" "$TASKS_FILE"
echo "gc-tasks: archived $(grep -cE '^- \[' "$arch_tmp") task(s) to $archive_file"
