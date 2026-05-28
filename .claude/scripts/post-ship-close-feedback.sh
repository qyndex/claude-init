#!/usr/bin/env bash
# Close feedback on ship — Round 13 Fix 3.
#
# The /feedback "Tuesday call → Friday shipped" chain documents this script as the final
# link (FB flips to shipped + spec back-link + moves to closed/), but it was never created
# — so the loop never closed and shipped feedback stayed "active" forever. This is it.
#
# For a just-shipped spec, finds every FB-* entry whose spec_refs include this spec,
# flips its status to shipped, notes the ship, and moves it to feedback/closed/.
# Idempotent: re-running after the entries have moved is a no-op.
#
# Usage: post-ship-close-feedback.sh <spec-id>     (call from /ship after a spec ships)

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

spec_id="${1:-}"
[ -z "$spec_id" ] && { echo "usage: post-ship-close-feedback.sh <spec-id>"; exit 1; }
num="${spec_id%%-*}"   # tolerate either "042" or "042-slug"

active=".claude/memory/feedback/active"
closed=".claude/memory/feedback/closed"
[ -d "$active" ] || { echo "no $active — nothing to close"; exit 0; }
mkdir -p "$closed"

shopt -s nullglob
closed_count=0
for fb in "$active"/FB-*.md; do
  [ -f "$fb" ] || continue
  # Match spec_refs containing the full id OR the numeric prefix (handles [042] / [042-slug]).
  if grep -qE "^spec_refs:.*(\b${spec_id}\b|\b${num}\b)" "$fb" 2>/dev/null; then
    sed -i.bak -E "s/^status:.*/status: shipped/" "$fb" && rm -f "${fb}.bak"
    printf '\n_Shipped via spec %s on %s._\n' "$spec_id" "$(date +%Y-%m-%d)" >> "$fb"
    mv "$fb" "$closed/"
    closed_count=$((closed_count + 1))
    echo "  ✓ closed $(basename "$fb") (shipped via $spec_id)"
  fi
done
echo "post-ship-close-feedback: closed $closed_count feedback entry(ies) for $spec_id"
