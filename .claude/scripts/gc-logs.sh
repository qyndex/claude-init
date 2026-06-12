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
# e2e-audit failure-recovery-5: jsonl event streams (instinct observations,
# lane events) grow unbounded across multi-night runs — rotate them too.
JSONL_DIR="${JSONL_DIR:-$ROOT/.claude/memory/.cache}"
GC_LOG_MAX_BYTES="${GC_LOG_MAX_BYTES:-52428800}"   # 50 MB
GC_LOG_KEEP="${GC_LOG_KEEP:-5}"

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

  # Offset translation (failure-recovery-5): instinct-extract.sh tracks a
  # LINE-COUNT offset into observations.jsonl. After truncation the live file
  # restarts at 0 lines, so a stale offset makes `new = total - last` negative
  # and extraction silently halts forever. Reset it with the rotation.
  if [ "$(basename "$log")" = "observations.jsonl" ]; then
    state="$ROOT/.claude/memory/.cache/.instinct-extract.state"
    [ -f "$state" ] && printf '0\n' > "$state"
  fi
# JUSTIFIED: the redirect drops find stderr when a scanned dir does not yet exist — the loop then iterates over nothing and gc-logs reports zero rotations
done < <({ find "$LOG_DIR" -type f -name '*.log' 2>/dev/null; find "$LOG_DIR" "$JSONL_DIR" "$ROOT/.swarms" -type f -name '*.jsonl' 2>/dev/null; } | sort -u)

echo "gc-logs: rotated $rotated log(s)"
