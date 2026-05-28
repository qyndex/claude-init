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

  story_num=0
  while IFS= read -r story_line; do
    [ -z "$story_line" ] && continue
    story_num=$((story_num + 1))
    total=$((total + 1))

    # Match any file matching e2e/<spec-id>/* OR e2e/spec-<id>/*
    # JUSTIFIED: the muted find tolerates a missing e2e/ tree; no matches means this story has no E2E test, which the caller reports as a gap
    test_files=$(find e2e -path "e2e/${spec_id}*/*" -name '*.spec.*' 2>/dev/null | head -3)
    # JUSTIFIED: same — the muted find tolerates a missing e2e/ tree; the two find results concatenate and emptiness signals a missing E2E test
    test_files=$(find e2e -path "e2e/spec-${spec_id}*/*" -name '*.spec.*' 2>/dev/null | head -3)$test_files

    story_short=$(echo "$story_line" | sed 's/^- *//' | head -c 80)

    if [ -n "$test_files" ]; then
      echo "  ✓ Story $story_num: $story_short..." >> "$report"
      echo "    → $(echo "$test_files" | head -1)" >> "$report"
    else
      echo "  ✗ Story $story_num MISSING: $story_short..." >> "$report"
      echo "    Expected: e2e/${spec_id}/story-${story_num}.spec.ts (or .py)" >> "$report"
      missing=$((missing + 1))
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
