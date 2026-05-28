#!/usr/bin/env bash
# gc-logs.sh — rotate oversized .log files.
#
# For each *.log under LOG_DIR larger than GC_LOG_MAX_BYTES, shift the rotation
# chain (.log.4→.5, .log.3→.4, ... .log→.log.1, keeping GC_LOG_KEEP backups) and
# truncate the live file. Idempotent: a log already under the cap is untouched.
#
# Overridable for tests: LOG_DIR, GC_LOG_MAX_BYTES, GC_LOG_KEEP.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

LOG_DIR="${LOG_DIR:-$ROOT/.claude/hooks/.log}"
GC_LOG_MAX_BYTES="${GC_LOG_MAX_BYTES:-52428800}"   # 50 MB
GC_LOG_KEEP="${GC_LOG_KEEP:-5}"

# JUSTIFIED: no log dir means nothing to rotate — exit cleanly.
[ -d "$LOG_DIR" ] || exit 0

file_size() { wc -c <"$1" | tr -d ' '; }

rotated=0
while IFS= read -r log; do
  [ -f "$log" ] || continue
  sz=$(file_size "$log")
  [ "$sz" -gt "$GC_LOG_MAX_BYTES" ] || continue

  # Drop the oldest, shift the chain up.
  rm -f "${log}.${GC_LOG_KEEP}"
  i=$(( GC_LOG_KEEP - 1 ))
  while [ "$i" -ge 1 ]; do
    [ -f "${log}.${i}" ] && mv -f "${log}.${i}" "${log}.$((i+1))"
    i=$(( i - 1 ))
  done
  mv -f "$log" "${log}.1"
  : >"$log"            # recreate an empty live log
  rotated=$((rotated+1))
# JUSTIFIED: the redirect drops find stderr when the log dir does not yet exist — the loop then iterates over nothing and gc-logs reports zero rotations
done < <(find "$LOG_DIR" -type f -name '*.log' 2>/dev/null)

echo "gc-logs: rotated $rotated log(s)"
