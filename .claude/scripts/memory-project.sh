#!/usr/bin/env bash
# memory-project.sh — M-12. Project the Decisions/Patterns catalogue into
# MEMORY.md, strictly BETWEEN the `<!-- BEGIN:auto-* -->` / `<!-- END:auto-* -->`
# markers, from the typed index. Single-writer, locked (shares "memory-plane" with
# the other memory writers so a dream/gc can't interleave). Everything OUTSIDE the
# markers — the hand-written taxonomy prose — is preserved byte-for-byte.
#
# Rows come from index.jsonl so this stays consistent with recall/supersession:
# superseded decisions (superseded_by set) are excluded, matching recall's -5.
#
# Failures are LOUD (memory-plane writes must not fail silently).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# shellcheck source=lib/with-lock.sh
. "$(dirname "$0")/lib/with-lock.sh"

INDEX=".claude/memory/index.jsonl"
MEMORY=".claude/memory/MEMORY.md"

die() { echo "memory-project: $*" >&2; exit 1; }

[ -f "$MEMORY" ] || die "no MEMORY.md at $MEMORY"
[ -f "$INDEX" ]  || die "no index at $INDEX — run memory-index.sh rebuild"

# _rows <type> — emit projected markdown rows for one memory type (empty → placeholder).
_rows() {
  local type="$1" out
  # decisions: exclude superseded (superseded_by non-empty). patterns: all.
  # Hook = description if the index carries one, else the em-dash is dropped so we
  # never emit a dangling "— " (the index doesn't yet store descriptions for every
  # type; enriching build_entry is M-13-14 scope, not M-12).
  out=$(jq -r --arg t "$type" '
    select(.type == $t)
    | select($t != "decision" or ((.superseded_by // "") == ""))
    | (.description // "" | gsub("^\\s+|\\s+$";"")) as $d
    | if $d == "" then "- [\(.id)](\(.path))" else "- [\(.id)](\(.path)) — \($d)" end
  ' "$INDEX" 2>/dev/null)
  if [ -z "$out" ]; then echo "_(none yet)_"; else echo "$out"; fi
}

_project() {
  local decf patf tmp
  # Rows go to files, not `awk -v` (awk -v can't carry embedded newlines — a
  # multi-row block would abort with "newline in string" on real data).
  decf=$(mktemp); patf=$(mktemp); tmp=$(mktemp)
  _rows decision > "$decf"
  _rows pattern  > "$patf"

  # Replace ONLY the lines between each marker pair; pass everything else through
  # verbatim. awk keeps the marker lines themselves, swapping the interior by
  # streaming the row-file at the BEGIN marker.
  awk -v decf="$decf" -v patf="$patf" '
    /<!-- BEGIN:auto-decisions/ { print; while ((getline l < decf) > 0) print l; close(decf); skip=1; next }
    /<!-- END:auto-decisions/   { skip=0; print; next }
    /<!-- BEGIN:auto-patterns/  { print; while ((getline l < patf) > 0) print l; close(patf); skip=1; next }
    /<!-- END:auto-patterns/    { skip=0; print; next }
    !skip { print }
  ' "$MEMORY" > "$tmp" || { rm -f "$decf" "$patf" "$tmp"; die "projection failed"; }
  mv "$tmp" "$MEMORY" || { rm -f "$decf" "$patf"; die "failed installing $MEMORY"; }
  local dcount pcount
  dcount=$(grep -c '^- ' "$decf" || true); pcount=$(grep -c '^- ' "$patf" || true)
  rm -f "$decf" "$patf"
  echo "✓ projected $dcount decisions, $pcount patterns → $MEMORY"
}

with_lock "memory-plane" _project
