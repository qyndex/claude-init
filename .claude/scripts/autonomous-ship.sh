#!/usr/bin/env bash
# autonomous-ship.sh — arm native auto-merge for a PR, but ONLY when every
# required check is GREEN. This is the agent-side trigger for hands-off shipping:
# the agent (or the overnight routine) calls this after opening a PR + running its
# own reviewer/security preflight; GitHub then squash-merges when CI passes.
#
# HARD RULE (operator decision 2026-07-24): never merge without green checks. If
# ANY check is pending, failing, skipped-but-required, or has not run at all
# (e.g. the current Actions billing outage), this refuses — exit non-zero, arms
# nothing, merges nothing. No override flag exists on purpose.
#
# It NEVER force-merges and NEVER bypasses the ruleset: it applies the
# `auto-merge-ok` label and calls `gh pr merge --auto`, so the server-side branch
# ruleset (0 approvals + all required checks) remains the real gate. If no live
# ruleset is present, `--auto` would merge on empty checks — so we also refuse
# when the repo has zero rulesets (mirrors ship/SKILL.md step 0).
#
# Usage:
#   autonomous-ship.sh <pr-number>            # arm auto-merge if all checks green
#   autonomous-ship.sh <pr-number> --dry-run  # report the gate decision, change nothing
#   AUTOSHIP_LABEL=auto-merge-ok  AUTOSHIP_REPO=owner/name   # overridable for tests
#
# Exit codes: 0 armed (or dry-run would-arm) · 3 checks not green · 4 no live
# ruleset · 5 gh/preconditions missing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PR="${1:-}"
DRY=0; [ "${2:-}" = "--dry-run" ] && DRY=1
LABEL="${AUTOSHIP_LABEL:-auto-merge-ok}"

log() { printf '[autonomous-ship] %s\n' "$*"; }
die() { log "$*"; exit "${2:-5}"; }

[ -n "$PR" ] || die "usage: autonomous-ship.sh <pr-number> [--dry-run]" 5
command -v gh >/dev/null 2>&1 || die "gh CLI required" 5
command -v jq >/dev/null 2>&1 || die "jq required" 5

# Resolve repo (test hook: AUTOSHIP_REPO). Fail loud rather than merge the wrong repo.
REPO="${AUTOSHIP_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
[ -n "$REPO" ] || die "cannot resolve repo (set AUTOSHIP_REPO or run inside a gh repo)" 5

# ── Gate 1: a live server-side ruleset must exist (else --auto merges on empty). ──
# Test hook AUTOSHIP_SKIP_RULESET=1 lets unit tests exercise the check-gate logic
# without a live ruleset; it is NOT an operational override (checks still gate).
if [ "${AUTOSHIP_SKIP_RULESET:-0}" != "1" ]; then
  ruleset_count=$(gh api "repos/$REPO/rulesets" --jq 'length' 2>/dev/null || echo 0)
  if [ "${ruleset_count:-0}" -eq 0 ]; then
    die "no live branch ruleset on $REPO — refusing to arm auto-merge (a --auto with no required checks merges immediately). Apply .github/rulesets/main-protection.json first: gh api repos/$REPO/rulesets --method POST --input .github/rulesets/main-protection.json" 4
  fi
fi

# ── Gate 2: the PR must be OPEN, not draft, not already merged. ──
pr_json=$(gh pr view "$PR" --repo "$REPO" --json state,isDraft,mergeStateStatus,title 2>/dev/null) \
  || die "cannot read PR #$PR on $REPO" 5
state=$(printf '%s' "$pr_json" | jq -r '.state')
draft=$(printf '%s' "$pr_json" | jq -r '.isDraft')
title=$(printf '%s' "$pr_json" | jq -r '.title')
[ "$state" = "OPEN" ] || die "PR #$PR is $state (not OPEN) — nothing to arm" 3
[ "$draft" = "false" ] || die "PR #$PR is a draft — mark ready first" 3

# ── Gate 3 (THE hard rule): EVERY check must be green. ──
# gh pr checks buckets: pass | fail | pending | skipping | cancel. We require that
# at least one check ran AND no check is in a non-pass bucket. A required check
# that is "skipping" is still not "pass" → refuse (billing outage / not-run shows
# up as fail or pending). This is the fail-CLOSED posture: unknown == not green.
checks=$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket 2>/dev/null || echo '[]')
total=$(printf '%s' "$checks" | jq 'length')
if [ "${total:-0}" -eq 0 ]; then
  die "PR #$PR has NO checks reporting — refusing (fail-closed; likely CI not running / billing-blocked)" 3
fi
not_green=$(printf '%s' "$checks" | jq -r '[.[] | select(.bucket != "pass")] | length')
if [ "${not_green:-1}" -ne 0 ]; then
  log "PR #$PR — $not_green of $total checks are NOT green (fail-closed). Not merging:"
  printf '%s' "$checks" | jq -r '.[] | select(.bucket != "pass") | "    \(.bucket | ascii_upcase)  \(.name)  (\(.state))"'
  exit 3
fi

log "PR #$PR \"$title\" — all $total checks GREEN."

if [ "$DRY" -eq 1 ]; then
  log "DRY-RUN: would label '$LABEL' and run: gh pr merge $PR --auto --squash --delete-branch"
  exit 0
fi

# Arm: label (so auto-merge.yml also recognizes it) + native auto-merge. --auto
# still waits on the ruleset's required checks server-side, so this is safe even
# if a check flips between our poll and GitHub's evaluation.
gh pr edit "$PR" --repo "$REPO" --add-label "$LABEL" 2>/dev/null \
  || log "warn: could not add label '$LABEL' (auto-merge.yml overnight-branch path still applies)"
if gh pr merge "$PR" --repo "$REPO" --auto --squash --delete-branch; then
  log "armed native auto-merge for #$PR — GitHub squash-merges when all required checks pass"
  exit 0
else
  die "gh pr merge --auto failed for #$PR (permissions? ruleset?)" 5
fi
