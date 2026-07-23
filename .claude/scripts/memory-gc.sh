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
# Wired into (gap-audit G10 — header now matches the real wiring):
#   - gc-nightly.yml (02:30 routine, step 4) — nightly `enforce`
#   - quarterly-archive.yml — quarterly `enforce`
#   - session-start-context.sh — warn-only when MEMORY.md >200 lines
#   - validate.sh [memory] — warn + remediation pointer when over cap

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
    # Evict by last_accessed date (oldest-first) rather than by file position.
    # Entries without last_accessed frontmatter are treated as epoch 0 (oldest).
    if [ "$lines" -le "$MAX_LINES" ]; then
      echo "MEMORY.md within cap; no enforcement needed"
      exit 0
    fi
    archive=".claude/memory/.archive/MEMORY-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$(dirname "$archive")"
    cp "$memory_file" "$archive"

    # Split MEMORY.md into entries delimited by blank lines between list items.
    # Each "- [Title](file.md) — hook" line is one entry; we sort by last_accessed
    # from the linked file's frontmatter, then keep the MAX_LINES most-recent entries.

    # Build a temp dir for sorted fragments
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    # Read all entry lines (lines starting with "- [")
    grep -n '^- \[' "$memory_file" | while IFS=: read -r lineno rest; do
      # Extract the linked file path from the markdown link, e.g. [Title](decisions/foo.md)
      linked_file=$(echo "$rest" | grep -oE '\([^)]+\.md\)' | tr -d '()' | head -1)
      # Get last_accessed from the linked file's frontmatter (YYYY-MM-DD or epoch 0).
      # M-03: no script ever WRITES last_accessed: — so it was absent everywhere and
      # every entry sorted as "0000-00-00" (all equally oldest), making the LRU
      # eviction inert. Fall back to the file's real recency: git last-commit date,
      # then filesystem mtime, so eviction is genuinely oldest-first even without
      # an explicit last_accessed: stamp.
      last_accessed="0000-00-00"
      if [ -n "$linked_file" ] && [ -f ".claude/memory/$linked_file" ]; then
        la=$(grep -m1 '^last_accessed:' ".claude/memory/$linked_file" 2>/dev/null \
             | sed 's/last_accessed:[[:space:]]*//' | tr -d '"' | xargs)
        if [ -n "$la" ]; then
          last_accessed="$la"
        else
          # JUSTIFIED: git log may be empty for an uncommitted file → fall back to mtime;
          # stderr muted because both fallbacks are best-effort recency signals
          la=$(git log -1 --format=%cs -- ".claude/memory/$linked_file" 2>/dev/null)
          if [ -z "$la" ]; then
            # BSD stat (-f %Sm) then GNU stat (-c %y); take the date portion
            la=$(stat -f '%Sm' -t '%Y-%m-%d' ".claude/memory/$linked_file" 2>/dev/null \
                 || stat -c '%y' ".claude/memory/$linked_file" 2>/dev/null | cut -d' ' -f1)
          fi
          [ -n "$la" ] && last_accessed="$la"
        fi
      fi
      printf '%s\t%s\t%s\n' "$last_accessed" "$lineno" "$rest"
    done | sort -t$'\t' -k1,1r -k2,2n > "$tmp_dir/sorted.tsv"

    # Count header lines (everything before the first "- [" entry)
    header_end=$(grep -n '^- \[' "$memory_file" | head -1 | cut -d: -f1)
    header_end=$(( ${header_end:-1} - 1 ))
    [ "$header_end" -lt 0 ] && header_end=0

    # How many entry lines can we keep within MAX_LINES (minus header lines)?
    available=$(( MAX_LINES - header_end - 2 ))   # 2 = truncation note lines
    [ "$available" -lt 1 ] && available=1

    # Keep the `available` most-recent entries; evict the rest
    keep_tsv="$tmp_dir/keep.tsv"
    evict_tsv="$tmp_dir/evict.tsv"
    head -n "$available" "$tmp_dir/sorted.tsv" > "$keep_tsv"
    tail -n +$(( available + 1 )) "$tmp_dir/sorted.tsv" > "$evict_tsv"

    evicted=$(wc -l < "$evict_tsv" | tr -d ' ')
    echo "Evicting $evicted oldest entries (by last_accessed) to $archive"

    # Rebuild MEMORY.md: header + kept entries (sorted back by original line number)
    {
      [ "$header_end" -gt 0 ] && head -n "$header_end" "$memory_file"
      sort -t$'\t' -k2,2n "$keep_tsv" | cut -f3-
      echo ""
      echo "---"
      echo ""
      echo "_$evicted entries evicted by memory-gc on $(date -Iseconds) (oldest last_accessed). Originals at $archive. Recover via /dream-review._"
    } > "$memory_file.tmp"

    # JUSTIFIED: atomic rename prevents a partial write leaving MEMORY.md empty
    mv "$memory_file.tmp" "$memory_file"
    echo "Enforced MEMORY.md cap: kept $available entries, evicted $evicted; backup at $archive"
    ;;

  archive)
    # Archive old decisions / patterns / incidents (>1 year old) to quarter-named subdirs
    archive_root=".claude/memory/.archive/$(date +%Y-Q$((( $(date +%-m) - 1) / 3 + 1 )))"
    mkdir -p "$archive_root/decisions" "$archive_root/incidents" "$archive_root/patterns"

    for dir in decisions incidents patterns; do
      # JUSTIFIED: the redirect drops find stderr when a memory subdir does not exist — the loop then archives nothing for that category, which is correct
      find ".claude/memory/$dir" -name '*.md' -mtime +365 2>/dev/null | while read f; do
        mv "$f" "$archive_root/$dir/"
        echo "Archived $f"
      done
    done

    echo "Archive complete: $archive_root"
    ;;
esac
