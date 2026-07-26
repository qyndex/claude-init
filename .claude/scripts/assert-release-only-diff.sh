#!/usr/bin/env bash
# assert-release-only-diff.sh — the single verification behind every required
# check on a release-please PR (run by .github/workflows/release-pr-gate.yml).
#
# A release PR changes ONLY version + changelog files, so each per-PR gate's
# verdict on it is vacuous — this script PROVES the vacuity instead of assuming
# it: the gate job passes iff (a) the PR was authored by github-actions[bot],
# (b) its head branch is release-please--*, and (c) every file in the diff is
# on the release allowlist. Any other file fails EVERY gate job (fail-safe:
# nothing can ride into main inside a release PR).
#
# Env: GH_TOKEN (read), REPO (owner/name), RELEASE_BRANCH (head branch to check)
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN required}"
: "${REPO:?REPO required}"
: "${RELEASE_BRANCH:?RELEASE_BRANCH required}"

case "$RELEASE_BRANCH" in
  release-please--*) ;;
  *) echo "FAIL: branch '$RELEASE_BRANCH' is not a release-please branch"; exit 1 ;;
esac

pr_json=$(gh pr list --repo "$REPO" --state open --head "$RELEASE_BRANCH" \
            --json number,author --jq '.[0]')
[ -n "$pr_json" ] || { echo "FAIL: no open PR for $RELEASE_BRANCH"; exit 1; }

author=$(printf '%s' "$pr_json" | jq -r '.author.login')
case "$author" in
  app/github-actions|github-actions) ;;
  *) echo "FAIL: PR author '$author' is not github-actions[bot]"; exit 1 ;;
esac

pr=$(printf '%s' "$pr_json" | jq -r '.number')
allow='^(CHANGELOG\.md|\.release-please-manifest\.json|release-please-config\.json|.*/CHANGELOG\.md)$'
files=$(gh pr view "$pr" --repo "$REPO" --json files --jq '.files[].path')
[ -n "$files" ] || { echo "FAIL: PR #$pr has an empty diff"; exit 1; }

bad=$(printf '%s\n' "$files" | grep -vE "$allow" || true) # JUSTIFIED: grep exits 1 when every file matches the allowlist (the PASS case); non-empty $bad fails below. ISSUE: #34
if [ -n "$bad" ]; then
  echo "FAIL: PR #$pr touches non-release files:"
  printf '%s\n' "$bad"
  exit 1
fi

echo "PASS: PR #$pr by $author changes only release files:"
printf '%s\n' "$files"
