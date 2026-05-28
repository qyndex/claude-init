#!/usr/bin/env bash
# gc-verify.sh — archive then prune old verify/ evidence dirs.
#
# Moves dated verify/<YYYY-MM-DD>/ dirs older than GC_VERIFY_AGE_DAYS into
# verify/archive/, and prunes archived dirs older than GC_VERIFY_PRUNE_DAYS.
# Idempotent: already-archived dirs are not re-processed.
#
# Overridable for tests: VERIFY_DIR, VERIFY_ARCHIVE_DIR, GC_VERIFY_AGE_DAYS,
# GC_VERIFY_PRUNE_DAYS.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

VERIFY_DIR="${VERIFY_DIR:-$ROOT/verify}"
VERIFY_ARCHIVE_DIR="${VERIFY_ARCHIVE_DIR:-$VERIFY_DIR/archive}"
GC_VERIFY_AGE_DAYS="${GC_VERIFY_AGE_DAYS:-30}"
GC_VERIFY_PRUNE_DAYS="${GC_VERIFY_PRUNE_DAYS:-60}"

# JUSTIFIED: no verify dir means nothing to GC — exit cleanly.
[ -d "$VERIFY_DIR" ] || exit 0
mkdir -p "$VERIFY_ARCHIVE_DIR"

moved=0
# Top-level dated dirs (YYYY-MM-DD or YYYY-MM-DD-feature), excluding the archive.
for d in "$VERIFY_DIR"/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  [ "$name" = "archive" ] && continue
  # Only dirs whose name starts with a date.
  case "$name" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) ;;
    *) continue ;;
  esac
  # Age by directory mtime (portable: GNU find -mmin via days*1440, BSD find -mtime).
  # JUSTIFIED: the redirect drops find stderr (e.g. a vanished dir during the scan) — emptiness then means "not old enough / gone", which grep -q correctly treats as no-archive
  if find "$d" -maxdepth 0 -mtime +"$GC_VERIFY_AGE_DAYS" 2>/dev/null | grep -q .; then
    dest="$VERIFY_ARCHIVE_DIR/$name"
    if [ ! -e "$dest" ]; then
      mv "$d" "$dest"
      moved=$((moved+1))
    fi
  fi
done

# Prune archived dirs older than the prune window.
pruned=0
for d in "$VERIFY_ARCHIVE_DIR"/*/; do
  [ -d "$d" ] || continue
  # JUSTIFIED: the redirect drops find stderr (e.g. a vanished archive dir) — emptiness then means "not past the prune window", which grep -q correctly treats as keep
  if find "$d" -maxdepth 0 -mtime +"$GC_VERIFY_PRUNE_DAYS" 2>/dev/null | grep -q .; then
    rm -rf "$d"
    pruned=$((pruned+1))
  fi
done

echo "gc-verify: archived $moved dir(s), pruned $pruned dir(s)"
