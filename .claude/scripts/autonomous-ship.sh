#!/usr/bin/env bash
# Request protected factory integration. This process has no merge authority.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PR="${1:-}"
case "$PR" in ''|*[!0-9]*) echo 'usage: autonomous-ship.sh <pr-number> [--dry-run]' >&2; exit 5 ;; esac
[ "$PR" -gt 0 ] || exit 5
[ "$#" -le 2 ] && { [ "$#" -eq 1 ] || [ "$2" = '--dry-run' ]; } || exit 5
command -v gh >/dev/null || { echo 'gh CLI required' >&2; exit 5; }
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
[ -n "$REPO" ] || exit 5
if [ "${2:-}" = '--dry-run' ]; then
  echo "DRY-RUN: request factory-merge.yml for $REPO PR #$PR; eligibility is determined by protected coordinator"
  exit 0
fi
gh workflow run factory-merge.yml --repo "$REPO" -f "pr=$PR" -f mode=merge
echo "Factory integration requested for #$PR. This is not a merge receipt."
