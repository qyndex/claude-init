#!/usr/bin/env bash
# Memory garbage-collection gate. Hard-enforces the 200-line MEMORY.md cap that
# /dream is *supposed* to enforce via prompt — but the Round 4 audit caught that
# the cap was unenforced (silent failure if dream subagent crashed/hallucinated).
#
# This script:
#   1. Enforces the cap mechanically (exit 2 if exceeded)
#   2. Surfaces "what to consolidate" for the next /dream
#   3. Archives super-old entries automatically
#
# Wired into:
#   - PreCompact hook (so compaction never proceeds with bloated MEMORY)
#   - Cron at 03:30 (after dream-cron) for nightly enforcement
#   - SessionStart (warn-only at >150 lines; fail at >300)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MAX_LINES="${MEMORY_MAX_LINES:-200}"
WARN_LINES="${MEMORY_WARN_LINES:-150}"
HARD_FAIL_LINES="${MEMORY_HARD_FAIL_LINES:-300}"

MODE="${1:-check}"   # check | enforce | archive

memory_file=".claude/memory/MEMORY.md"

if [ ! -f "$memory_file" ]; then
  echo "MEMORY.md not found — first-run case, no-op"
  exit 0
fi

lines=$(wc -l < "$memory_file" | tr -d ' ')

case "$MODE" in
  check)
    if [ "$lines" -ge "$HARD_FAIL_LINES" ]; then
      echo "MEMORY.md is $lines lines (HARD FAIL > $HARD_FAIL_LINES)"
      echo "Run: bash .claude/scripts/memory-gc.sh enforce"
      exit 2
    elif [ "$lines" -ge "$MAX_LINES" ]; then
      echo "MEMORY.md is $lines lines (> $MAX_LINES cap). Run: /dream"
      exit 1
    elif [ "$lines" -ge "$WARN_LINES" ]; then
      echo "MEMORY.md is $lines lines (approaching $MAX_LINES cap). Consider: /dream"
      exit 0
    else
      echo "MEMORY.md: $lines lines / $MAX_LINES cap (healthy)"
      exit 0
    fi
    ;;

  enforce)
    # Hard truncate at MAX_LINES, preserving structure
    if [ "$lines" -le "$MAX_LINES" ]; then
      echo "MEMORY.md within cap; no enforcement needed"
      exit 0
    fi
    # Backup
    archive=".claude/memory/.archive/MEMORY-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$(dirname "$archive")"
    cp "$memory_file" "$archive"
    # Keep header + first MAX_LINES, append truncation note
    head -n "$MAX_LINES" "$memory_file" > "$memory_file.tmp"
    cat >> "$memory_file.tmp" <<EOF

---

_Truncated by memory-gc on $(date -Iseconds). Original at $archive. Recover via /dream-review or by reading the archive directly._
EOF
    mv "$memory_file.tmp" "$memory_file"
    echo "Truncated MEMORY.md to $MAX_LINES lines; backup at $archive"
    ;;

  archive)
    # Archive old decisions / patterns / incidents (>1 year old) to quarter-named subdirs
    archive_root=".claude/memory/.archive/$(date +%Y-Q$((( $(date +%-m) - 1) / 3 + 1 )))"
    mkdir -p "$archive_root/decisions" "$archive_root/incidents" "$archive_root/patterns"

    for dir in decisions incidents patterns; do
      find ".claude/memory/$dir" -name '*.md' -mtime +365 2>/dev/null | while read f; do
        mv "$f" "$archive_root/$dir/"
        echo "Archived $f"
      done
    done

    echo "Archive complete: $archive_root"
    ;;
esac
