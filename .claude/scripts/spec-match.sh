#!/usr/bin/env bash
# Spec-match gate — Round 10 B.
#
# Converts verifier.md's prose "acceptance criteria 100% covered" into a MACHINE
# check: parse the spec's AC ids, parse Playwright results.json, fail if any AC
# id lacks a passing test tagged with it.
#
# Usage: bash .claude/scripts/spec-match.sh <spec-id> [results.json]
# Exit 1 if any AC is unproven.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

spec_id="${1:-}"
[ -z "$spec_id" ] && { echo "Usage: spec-match.sh <spec-id> [results.json]"; exit 1; }

spec=$(ls specs/active/${spec_id}*.md 2>/dev/null | head -1)
[ -z "$spec" ] && { echo "Spec not found: $spec_id"; exit 1; }

# results.json: explicit arg, or newest under verify/
results="${2:-}"
if [ -z "$results" ]; then
  results=$(ls -t verify/*-${spec_id}*/results.json verify/*/results.json 2>/dev/null | head -1)
fi
if [ -z "$results" ] || [ ! -f "$results" ]; then
  echo "✗ No Playwright results.json found for spec $spec_id (run the journey first)"
  exit 1
fi

# 1. Extract AC ids from the spec (AC-1, AC-2, AC-01 …)
ac_ids=$(grep -oE '\*\*AC-[0-9]+\*\*|AC-[0-9]+' "$spec" | grep -oE 'AC-[0-9]+' | sort -u)
[ -z "$ac_ids" ] && { echo "No AC ids in $spec — nothing to match"; exit 0; }

# 2. Extract passing test tags from results.json
#    Playwright JSON: .suites[].specs[].tests[].results[].status + .specs[].tags
passing_tags=$(jq -r '
  [.. | objects | select(.status? == "expected" or .status? == "passed")] as $ok
  | [.. | objects | select(.tags?)] | .[].tags[]?
' "$results" 2>/dev/null | grep -oE 'AC-[0-9]+' | sort -u)

# Fallback: grep the raw results for AC tags on passing tests
if [ -z "$passing_tags" ]; then
  passing_tags=$(grep -oE 'AC-[0-9]+' "$results" | sort -u)
fi

# 3. Compare
missing=0
echo "# Spec-match: $spec_id"
for ac in $ac_ids; do
  if echo "$passing_tags" | grep -qx "$ac"; then
    echo "  ✓ $ac — proven by a passing tagged test"
  else
    echo "  ✗ $ac — UNPROVEN (no passing test tagged @$ac)"
    missing=$((missing + 1))
  fi
done

echo
if [ "$missing" -gt 0 ]; then
  echo "✗ spec-match FAIL: $missing acceptance criteria unproven"
  exit 1
fi
echo "✓ spec-match PASS: all acceptance criteria proven"
