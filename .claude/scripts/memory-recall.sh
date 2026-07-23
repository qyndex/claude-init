#!/usr/bin/env bash
# memory-recall.sh — the missing READ path for the memory index.
#
# Memory-system review (docs/research/memory-system-review.md §7.3): index.jsonl
# supports rich queries but had ZERO callers. This script surfaces the top-K
# most relevant memory entries for the current work by intersecting each
# entry's paths_touched with recently-changed files, plus recency and
# lifecycle-status weighting. Output is injection-safe (≤K short lines, empty
# when nothing relevant).
#
# Usage:
#   bash .claude/scripts/memory-recall.sh                  # derive paths from git
#   bash .claude/scripts/memory-recall.sh --paths "src/a src/b" --limit 3
#
# Scoring per index entry:
#   +10 per path-prefix intersection with the working set
#   +2  status=established, +1 status=accepted
#   +2  touched in last 30 days, +1 in last 90
#   -5  status=quarantined or superseded_by set (still shown, marked, if it
#       intersects — knowing what NOT to do is recall too)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

INDEX=".claude/memory/index.jsonl"
[ -s "$INDEX" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

limit=5
paths=""
grep_term=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paths) paths="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --grep) grep_term="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# M-16: --grep <term> content search. Complementary to the --paths working-set
# match: collect ids of indexed entries whose FILE BODY contains the term, then
# feed that id set into the scorer as a content-hit (unions with path-hits). Read
# only — we grep the already-indexed files, never write. Empty when the term is
# absent everywhere, so a bogus term surfaces nothing.
grep_ids="[]"
if [ -n "$grep_term" ]; then
  grep_ids=$(
    # JUSTIFIED: a term matched in no indexed file makes grep exit 1 — the id
    # list is then correctly empty, and content-recall surfaces nothing.
    jq -r '.path' "$INDEX" 2>/dev/null \
      | while IFS= read -r p; do
          [ -f "$p" ] || continue
          if grep -qF -- "$grep_term" "$p" 2>/dev/null; then
            basename "$p" .md
          fi
        done \
      | sort -u | jq -R . | jq -sc .
  )
  [ -n "$grep_ids" ] || grep_ids="[]"
fi

if [ -z "$paths" ]; then
  # Working set: uncommitted changes + files in the last 3 commits.
  # JUSTIFIED: outside a repo / empty repo both commands fail — empty working set means recency-only scoring below
  paths=$( { git status --porcelain 2>/dev/null | awk '{print $NF}'; \
             git log -3 --name-only --format='' 2>/dev/null; } | sort -u | head -40 | tr '\n' ' ')
fi

now=$(date +%s)

# Build a JSON array of the working-set paths once, then score every entry.
jq -cs --arg paths "$paths" --argjson now "$now" --argjson limit "$limit" --argjson grepids "$grep_ids" '
  ($paths | split(" ") | map(select(length > 0))) as $ws
  | map(
      . as $e
      | ([ $e.paths_touched[]? as $pt
           | select(($pt | length) > 0)
           | $ws[] as $w
           # bind both sides explicitly — a bare `.` inside `x | startswith(.)`
           # rebinds to x and matches everything
           | select(($w | startswith($pt)) or ($pt | startswith($w)))
         ] | length) as $pathhits
      # M-16: content-hit from --grep. An id in $grepids counts as a hit so the
      # entry clears the hits>0 noise floor and is surfaced (unions with paths).
      | (if ($grepids | index($e.id)) then 1 else 0 end) as $grephit
      | ($pathhits + $grephit) as $hits
      | ($e.status // "unknown") as $st
      | (if ($now - ($e.mtime // 0)) < 2592000 then 2
         elif ($now - ($e.mtime // 0)) < 7776000 then 1
         else 0 end) as $recency
      | (if $st == "established" then 2 elif $st == "accepted" then 1 else 0 end) as $stbonus
      | (if $st == "quarantined" or (($e.superseded_by // "") != "") then -5 else 0 end) as $penalty
      | $e + {score: ($hits * 10 + $recency + $stbonus + $penalty), hits: $hits}
    )
  # M-13: noise floor. Surface an entry only when it actually MATCHES the working
  # set (hits > 0). Recency/status are tiebreakers among matches, never enough to
  # surface a bonus-only entry — that made an unrelated path return ~20 noise lines.
  # A superseded/quarantined match (penalty -5) is also dropped: -5 outweighs a
  # single hit (+10) only past 2 hits, so keep the explicit score guard too.
  | map(select(.hits > 0 and .score > 0))
  | sort_by(-.score)
  | .[0:$limit]
  | .[]
  | "[recall] \(.type)/\(.id) (\(.status // "unknown"))\(if .hits > 0 then " — matches working set" else "" end) — \(.path)"
' "$INDEX" 2>/dev/null | jq -r . 2>/dev/null || true

exit 0
