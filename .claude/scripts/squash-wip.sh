#!/usr/bin/env bash
# Squash WIP commits into a single clean Conventional Commit.
# Called by autopilot Phase 5 and by /ship.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Find the base — last non-WIP commit
base=$(git log --format='%H %s' | grep -m1 -v '^[0-9a-f]\+ WIP:' | awk '{print $1}')
if [ -z "$base" ]; then
  echo "No non-WIP base commit found. Aborting."
  exit 1
fi

# JUSTIFIED: grep -c exits 1 when zero WIP commits match; under set -e the `|| echo 0` makes "none" a clean count, handled by the == "0" branch below
wip_count=$(git log --oneline "${base}..HEAD" | grep -c '^[0-9a-f]\+ WIP:' || echo 0)
if [ "$wip_count" = "0" ]; then
  echo "No WIP commits to squash."
  exit 0
fi

echo "Squashing $wip_count WIP commits into one"

# Capture all WIP messages into a single body
bodies=$(git log --format='%B' "${base}..HEAD" | grep -v '^WIP:' | grep -v '^\[gstack-context\]')

# Reset to base, keeping changes staged
git reset --soft "$base"

# Build final commit message — user supplies the Conventional Commits subject
final_subject="${1:-feat: squashed WIP commits — fill in subject before pushing}"

git commit -m "$final_subject" -m "Squashed $wip_count WIP commits.

$bodies

Co-Authored-By: Claude <noreply@anthropic.com>"

echo "Squashed. Edit the commit message with: git commit --amend"
