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

# JUSTIFIED: the muted ls tolerates no matching spec file; an empty result triggers the explicit "Spec not found" error on the next line
spec=$(ls specs/active/${spec_id}*.md 2>/dev/null | head -1)
[ -z "$spec" ] && { echo "Spec not found: $spec_id"; exit 1; }

# results.json: explicit arg, or newest under verify/ FOR THIS SPEC ONLY —
# gap-audit G53: the old any-directory wildcard fallback let a different
# feature's results "prove" this spec's ACs.
results="${2:-}"
if [ -z "$results" ]; then
  # JUSTIFIED: the muted ls tolerates no results.json yet; emptiness is handled by the "No Playwright results.json" guard below
  results=$(ls -t verify/*-${spec_id}*/results.json 2>/dev/null | head -1)
fi
if [ -z "$results" ] || [ ! -f "$results" ]; then
  echo "✗ No Playwright results.json found for spec $spec_id (run the journey first)"
  exit 1
fi

# 1. Extract AC ids from the spec (AC-1, AC-2, AC-01 …), normalized to
#    unpadded AC-N — e2e-audit e2e-rig-3: specs write AC-01 while tests tag
#    @AC-1; the comparison must happen in ONE canonical form.
ac_ids=$(grep -oE '\*\*AC-[0-9]+\*\*|AC-[0-9]+' "$spec" | grep -oE 'AC-[0-9]+' | sed 's/AC-0*\([0-9]\)/AC-\1/' | sort -u)
[ -z "$ac_ids" ] && { echo "No AC ids in $spec — nothing to match"; exit 0; }

# 2. Extract tags from PASSING tests only — gap-audit G51 (critical): the old
#    jq collected tags from every spec object regardless of status, and a
#    status-blind grep fallback meant a 100%-failing journey still "proved"
#    every AC. Now a tag counts only when its spec object is ok==true (or
#    every test under it reported expected/passed).
jq_prog='
  [.. | objects | select(has("specs")) | .specs[]
   | select(
       .ok == true
       or ([.tests[]?.results[]?.status] | length > 0 and all(. == "expected" or . == "passed"))
     )
   | ((.tags // [])[]?, .title // empty)]
  | .[]
'
# JUSTIFIED: the redirect mutes jq on a malformed/partial results.json; empty passing_tags then correctly yields zero matched ACs rather than aborting
passing_tags=$(jq -r "$jq_prog" "$results" 2>/dev/null | grep -oE 'AC-[0-9]+' | sed 's/AC-0*\([0-9]\)/AC-\1/' | sort -u)

# e2e-audit greenfield-4: stack-aware AC proof — CLIs/APIs/libraries have no
# browser rig; their AC-tagged proof arrives as jest JSON or junit XML
# (pytest --junitxml / go-junit / jest --json). Accept those shapes too.
if [ -z "$passing_tags" ]; then
  case "$results" in
    *.xml)
      # junit: a PASSING testcase is self-closing (<testcase …/>); a failing one
      # wraps <failure>/<error> children. Extract AC-N from the name attribute.
      # JUSTIFIED: grep no-match exits 1 — empty set simply proves nothing
      passing_tags=$(grep -oE '<testcase[^>]*/>' "$results" 2>/dev/null | grep -oE 'AC-[0-9]+' | sed 's/AC-0*\([0-9]\)/AC-\1/' | sort -u)
      ;;
    *)
      # jest --json: .testResults[].assertionResults[] with status "passed"
      # JUSTIFIED: jq muted on non-jest JSON — empty set proves nothing, matching the playwright path's contract
      passing_tags=$(jq -r '.testResults[]?.assertionResults[]? | select(.status == "passed") | .fullName // .title // empty' "$results" 2>/dev/null | grep -oE 'AC-[0-9]+' | sed 's/AC-0*\([0-9]\)/AC-\1/' | sort -u)
      ;;
  esac
fi

# No silent fallback: if the file mentions AC tags but pass status could not be
# established, say so loudly — these ACs are UNPROVEN, not assumed proven.
if [ -z "$passing_tags" ] && grep -qE 'AC-[0-9]+' "$results"; then
  echo "⚠ $results contains AC tags but no test could be confirmed PASSING — cannot prove any AC from it (gap-audit G51)"
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
