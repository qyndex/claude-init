#!/usr/bin/env bash
# Branch-freshness preflight (Spec 001 AC-19).
#
# Warns — never blocks — when the current branch has drifted far from main:
# more than 50 commits behind, or older than 7 days since it diverged. A stale
# branch is the usual root cause of "passes locally, conflicts on merge"; this
# surfaces it before verify.sh runs the expensive gates. Honors SKIP_BRANCH_CHECK=1
# (CI sets this — the merge queue already enforces freshness at the GitHub layer).
#
# Always exits 0: this is advisory. It emits a `branch.stale_against_main` warning
# line to stdout so verify.sh / the status line can surface it.

set -uo pipefail

if [ "${SKIP_BRANCH_CHECK:-0}" = "1" ]; then
  exit 0
fi

# Not a git repo → nothing to check.
# JUSTIFIED: the redirect drops git stderr outside a work tree; a non-"true" result skips the check, which is the intended no-op
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  exit 0
fi

MAX_COMMITS="${BRANCH_MAX_COMMITS:-50}"
MAX_DAYS="${BRANCH_MAX_DAYS:-7}"

# Resolve the base ref: prefer origin/main, fall back to local main.
base=""
if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  base="origin/main"
elif git rev-parse --verify --quiet main >/dev/null 2>&1; then
  base="main"
else
  # No main to compare against (fresh repo) — nothing to warn about.
  exit 0
fi

# JUSTIFIED: 2>/dev/null + echo HEAD fallback — a detached HEAD has no symbolic ref; "HEAD" is a sentinel that fails the main/base guard below and proceeds harmlessly
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

# On main itself there is nothing to be stale against.
if [ "$branch" = "main" ] || [ "$branch" = "$base" ]; then
  exit 0
fi

# Commits on base not yet in HEAD (how far behind we are).
# JUSTIFIED: 2>/dev/null + echo 0 fallback — if rev-list can't resolve the range (shallow clone, missing ref) we treat "behind" as 0; over-warning on a count error would be worse than under-warning on an advisory check
behind="$(git rev-list --count "HEAD..${base}" 2>/dev/null || echo 0)"

# Age of the merge-base (when this branch diverged from base), in days.
# JUSTIFIED: 2>/dev/null + || true — no common ancestor (unrelated histories) yields an empty mb, which the guard below skips; an absent merge-base is not an error for an advisory check
mb="$(git merge-base HEAD "$base" 2>/dev/null || true)"
age_days=0
if [ -n "$mb" ]; then
  # JUSTIFIED: 2>/dev/null + echo 0 fallback — a missing/corrupt commit object yields epoch 0, which the `-gt 0` guard treats as "unknown age"; never fatal to the preflight
  mb_epoch="$(git show -s --format=%ct "$mb" 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  if [ "$mb_epoch" -gt 0 ]; then
    age_days=$(( (now_epoch - mb_epoch) / 86400 ))
  fi
fi

if [ "$behind" -gt "$MAX_COMMITS" ] || [ "$age_days" -gt "$MAX_DAYS" ]; then
  printf 'branch.stale_against_main: %s is %s commits behind %s and diverged %s days ago (thresholds: %s commits / %s days). Consider rebasing.\n' \
    "$branch" "$behind" "$base" "$age_days" "$MAX_COMMITS" "$MAX_DAYS"
fi

exit 0
