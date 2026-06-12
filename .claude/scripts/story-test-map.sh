#!/usr/bin/env bash
# Story → E2E test map enforcement — Round 8 D.
#
# For every spec in specs/active/ with `status: approved`, ensure every
# "As a <role> I want <X> so that <Y>" user story has at least one Playwright
# E2E test file. Maps via filename convention: e2e/<spec-id>/story-N.spec.ts
# (or Python equivalents).
#
# Exit 1 if any approved spec has stories without tests.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

[ -d specs/active ] || { echo "no specs/active/ — passing"; exit 0; }

mkdir -p verify/$(date +%Y-%m-%d)
report="verify/$(date +%Y-%m-%d)/story-coverage.md"

{
  echo "# Story → E2E test coverage"
  echo
  echo "Round 8 D — every approved spec's user story must have a Playwright E2E test."
  echo
  echo "Generated: $(date -Iseconds)"
  echo
} > "$report"

missing=0
total=0

for spec in specs/active/*.md; do
  [ -f "$spec" ] || continue

  # Only check approved specs
  status=$(grep -E '^status:' "$spec" | head -1 | sed 's/status:[[:space:]]*//' | sed 's/[[:space:]]*#.*$//' | tr -d ' "')
  [ "$status" = "approved" ] || continue

  spec_id=$(basename "$spec" .md | grep -oE '^[0-9]+' | head -1)
  [ -z "$spec_id" ] && continue

  # Extract user stories (lines starting with "- As a")
  stories=$(awk '
    /^## User stories/ { in_stories = 1; next }
    /^## / && in_stories { in_stories = 0 }
    in_stories && /^- As a / { print }
  ' "$spec")

  if [ -z "$stories" ]; then
    continue
  fi

  echo "## Spec $spec_id ($(basename "$spec" .md))" >> "$report"
  echo "" >> "$report"

  # Gap-audit G54: cross-check against the journey's pass status. When a
  # results.json exists for this spec, a story counts only if a PASSING test
  # carries its @story-N tag — same standard spec-match.sh applies to ACs.
  # JUSTIFIED: the muted ls tolerates no results.json — file-existence mapping then stands alone (pre-journey local use)
  results=$(ls -t verify/*-${spec_id}*/results.json 2>/dev/null | head -1)
  passing_story_tags=""
  if [ -n "$results" ]; then
    # JUSTIFIED: jq muted on malformed results — empty passing tags degrades to "exists but unproven", never a crash
    passing_story_tags=$(jq -r '
      [.. | objects | select(has("specs")) | .specs[]
       | select(.ok == true
           or ([.tests[]?.results[]?.status] | length > 0 and all(. == "expected" or . == "passed")))
       | ((.tags // [])[]?, .title // empty)] | .[]' "$results" 2>/dev/null \
      | grep -oE 'story-[0-9]+' | sort -u)
  fi

  story_num=0
  while IFS= read -r story_line; do
    [ -z "$story_line" ] && continue
    story_num=$((story_num + 1))
    total=$((total + 1))

    # Gap-audit G54: match THIS story's test, not any file in the spec's dir —
    # filename convention story-N.* first, @story-N tag inside test files second.
    # JUSTIFIED: the muted find tolerates a missing e2e/ tree; no matches falls through to the tag grep, then to "MISSING"
    test_files=$(find e2e \( -path "e2e/${spec_id}*/story-${story_num}.*" -o -path "e2e/spec-${spec_id}*/story-${story_num}.*" \) -type f 2>/dev/null | head -3)
    if [ -z "$test_files" ]; then
      # JUSTIFIED: the muted grep tolerates missing dirs/no matches — emptiness correctly reports the story as unmapped
      test_files=$(grep -rlE "@story-${story_num}([^0-9]|\$)" e2e/${spec_id}* e2e/spec-${spec_id}* 2>/dev/null | head -3)
    fi

    story_short=$(echo "$story_line" | sed 's/^- *//' | head -c 80)

    if [ -z "$test_files" ]; then
      echo "  ✗ Story $story_num MISSING: $story_short..." >> "$report"
      echo "    Expected: e2e/${spec_id}/story-${story_num}.spec.ts (or @story-${story_num} tag)" >> "$report"
      missing=$((missing + 1))
    elif [ -n "$results" ] && ! printf '%s\n' "$passing_story_tags" | grep -qx "story-${story_num}"; then
      echo "  ✗ Story $story_num UNPROVEN: $story_short..." >> "$report"
      echo "    Test exists ($(echo "$test_files" | head -1)) but no PASSING test tagged @story-${story_num} in $results" >> "$report"
      missing=$((missing + 1))
    else
      echo "  ✓ Story $story_num: $story_short..." >> "$report"
      echo "    → $(echo "$test_files" | head -1)" >> "$report"
    fi
  done <<< "$stories"

  echo "" >> "$report"
done

{
  echo
  echo "## Summary"
  echo
  echo "- Total stories scanned: $total"
  echo "- Stories with E2E tests: $((total - missing))"
  echo "- Stories MISSING tests: $missing"
} >> "$report"

if [ "$missing" -gt 0 ]; then
  echo "✗ $missing user stories lack E2E tests — see $report"
  echo "  Story coverage gate FAILS. Add Playwright tests for each missing story."
  exit 1
fi

echo "✓ All $total approved-spec user stories have E2E test coverage"
echo "  Report: $report"
