#!/usr/bin/env bash
# ledger-decay.sh — deterministic decay of old completed task history (M-21).
#
# Over time, tasks/TASKS.md accumulates verbose multi-field entries for tasks that
# finished long ago. This pass COLLAPSES old completed ([x]) / skipped ([s]) task
# blocks — whose completed:/last_touched: date is older than DECAY_AGE_DAYS — into a
# terse one-liner that keeps only the task ID, status marker, spec, and completion
# date. LIVE tasks ([ ] pending, [~] in_progress, [b] blocked) and recently-completed
# tasks stay BYTE-IDENTICAL. Section headers, the format-template line, and all
# preamble are untouched.
#
# Collapse: `- [x] T-001 | spec:001 | phase:1 | priority: ... | completed: <date>`
#        →  `- [x] T-001 | spec:001 | completed: <date>`
#           (indented continuation lines of a collapsed block are dropped)
#
# Idempotent: an already-terse line re-parses to the same terse line, so a second
# run is a no-op.
#
# Overridable for tests: TASKS_FILE, DECAY_AGE_DAYS.
# tasks/TASKS.md is memory-plane → the rewrite is serialized under with_lock.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/with-lock.sh
. "$(dirname "$0")/lib/with-lock.sh"

TASKS_FILE="${TASKS_FILE:-$ROOT/tasks/TASKS.md}"
DECAY_AGE_DAYS="${DECAY_AGE_DAYS:-90}"

# JUSTIFIED: missing TASKS.md means nothing to decay — exit cleanly, not an error.
[ -f "$TASKS_FILE" ] || exit 0

cutoff_epoch=$(( $(date +%s) - DECAY_AGE_DAYS * 86400 ))

_decay() {
  local out_tmp; out_tmp="$(mktemp)"

  # Per task block: a `- [..] T-..` marker line plus its indented continuation
  # lines. A block is collapse-eligible only when the marker is [x]/[s] AND carries
  # a YYYY-MM-DD (completed:/last_touched:) older than the cutoff. Non-task preamble
  # (template line, headers, blank lines) is emitted verbatim.
  awk -v cutoff="$cutoff_epoch" '
    function flush(block, marker,    ds, cmd, ep, id, spec, comp, terse) {
      if (block == "") return
      if (marker ~ /^- \[[xs]\]/ && match(marker, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
        ds = substr(marker, RSTART, RLENGTH)
        # JUSTIFIED: BSD/GNU date portability as an awk-built command; the muted
        # error is the expected miss on the absent date flavor, and a 0 result
        # (unparseable) leaves the block verbatim (not collapsed).
        cmd = "date -j -f %Y-%m-%d \"" ds "\" +%s 2>/dev/null || date -d \"" ds "\" +%s 2>/dev/null || echo 0"
        cmd | getline ep; close(cmd)
        if (ep != "" && ep+0 > 0 && ep+0 < cutoff) {
          # Extract id (T-NNN), spec:NNN, and the completion date for the terse line.
          id = ""; spec = ""; comp = ds
          if (match(marker, /T-[0-9A-Za-z]+/))            id   = substr(marker, RSTART, RLENGTH)
          if (match(marker, /spec:[0-9A-Za-z]+/))         spec = substr(marker, RSTART, RLENGTH)
          # Prefer an explicit completed: date if present; else fall back to the
          # first date found (last_touched:).
          if (match(marker, /completed:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
            comp = substr(marker, RSTART, RLENGTH); sub(/completed:[[:space:]]*/, "", comp)
          }
          mstatus = substr(marker, 1, 6)               # "- [x] " / "- [s] "
          terse = mstatus id " | " spec " | completed: " comp
          print terse
          return
        }
      }
      printf "%s", block
    }
    /^- \[/ {
      flush(block, marker)
      block = $0 "\n"; marker = $0; next
    }
    {
      if (marker != "") { block = block $0 "\n" }
      else { print }
    }
    END { flush(block, marker) }
  ' "$TASKS_FILE" > "$out_tmp"

  # Idempotency: if decay changed nothing, leave the original byte-identical.
  if diff -q "$TASKS_FILE" "$out_tmp" >/dev/null 2>&1; then
    rm -f "$out_tmp"
    return 0
  fi

  local collapsed
  # JUSTIFIED: diff count is informational only; a formatting hiccup must not fail decay
  collapsed=$(diff "$TASKS_FILE" "$out_tmp" 2>/dev/null | grep -cE '^> - \[[xs]\]' || true)
  mv -f "$out_tmp" "$TASKS_FILE"
  echo "ledger-decay: collapsed $collapsed old completed task block(s) in $TASKS_FILE"
}

with_lock "memory-plane" _decay
