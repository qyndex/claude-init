#!/usr/bin/env bash
# lint-trailers.sh — gap-audit G47.
# §VI mandates Confidence/Scope-risk/Not-tested trailers, but commitlint only
# checked the Conventional-Commits header — the trailers were never validated.
#
# Validates every commit in <base>..<head>:
#   - Confidence: high | medium | low | unknown   (required)
#   - Scope-risk: none | localized | broad        (required)
#   - Not-tested: <text>                          (warn if absent)
# Skipped: merge commits, WIP checkpoints (squashed before PR), bot authors
# (dependabot/renovate/github-actions), and revert commits.
#
# Usage: bash lint-trailers.sh <base> <head>     # defaults: main HEAD

set -uo pipefail

BASE="${1:-main}"
HEAD="${2:-HEAD}"

# JUSTIFIED: git stderr suppressed — an unresolvable range yields no SHAs; zero commits to lint is a clean pass, reported below
shas=$(git rev-list --no-merges "$BASE..$HEAD" 2>/dev/null)
if [ -z "$shas" ]; then
  echo "✓ No commits to lint in $BASE..$HEAD"
  exit 0
fi

fails=0
checked=0
for sha in $shas; do
  subject=$(git log -1 --format='%s' "$sha")
  author=$(git log -1 --format='%an <%ae>' "$sha")
  case "$subject" in
    WIP:*|Revert*) continue ;;
  esac
  case "$author" in
    *dependabot*|*renovate*|*github-actions*) continue ;;
  esac

  body=$(git log -1 --format='%B' "$sha")
  checked=$((checked + 1))
  short="${sha:0:7} ${subject:0:50}"

  conf=$(printf '%s\n' "$body" | grep -E '^Confidence:[[:space:]]*' | head -1 | sed -E 's/^Confidence:[[:space:]]*//' | tr -d ' ')
  risk=$(printf '%s\n' "$body" | grep -E '^Scope-risk:[[:space:]]*' | head -1 | sed -E 's/^Scope-risk:[[:space:]]*//' | tr -d ' ')

  if [ -z "$conf" ]; then
    echo "✗ $short — missing Confidence: trailer"
    fails=$((fails + 1))
  else
    case "$conf" in
      high|medium|low|unknown) : ;;
      *) echo "✗ $short — Confidence: '$conf' not in {high,medium,low,unknown}"; fails=$((fails + 1)) ;;
    esac
  fi

  if [ -z "$risk" ]; then
    echo "✗ $short — missing Scope-risk: trailer"
    fails=$((fails + 1))
  else
    case "$risk" in
      none|localized|broad) : ;;
      *) echo "✗ $short — Scope-risk: '$risk' not in {none,localized,broad}"; fails=$((fails + 1)) ;;
    esac
  fi

  if ! printf '%s\n' "$body" | grep -qE '^Not-tested:'; then
    echo "⚠ $short — no Not-tested: trailer (state what wasn't covered, or 'nothing')"
  fi
done

if [ "$fails" -gt 0 ]; then
  echo
  echo "✗ $fails trailer violation(s) across $checked commit(s). Required (CLAUDE.md §VI):"
  echo "    Confidence: high | medium | low | unknown"
  echo "    Scope-risk: none | localized | broad"
  exit 1
fi
echo "✓ $checked commit(s): Confidence + Scope-risk trailers valid"
