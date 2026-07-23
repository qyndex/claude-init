#!/usr/bin/env bash
# reverse-drift-check.sh (M-07-guard) — post-merge reverse-drift detector.
#
# Reverse drift = shipped work marked unshipped. The 2026-07 memory audit found
# spec-004 stuck `[ ]` in tasks/TASKS.md for six weeks AFTER PR #13 merged it,
# with no detection. This scans merged commits for `Task: T-NNN` trailers
# (commit_protocol §VI) whose referenced task is STILL `[ ]` (pending) in
# tasks/TASKS.md and reports each as advisory.
#
# ADVISORY ONLY: always exits 0. It is wired on `push: main` (post-merge) —
# NEVER on `pull_request`, because WIP branches legitimately carry `Task:`
# trailers for in-progress `[ ]` tasks and a PR-time check would false-positive.
#
# Range: REVERSE_DRIFT_SINCE (default: the range GitHub gives a push event,
# ${GITHUB_EVENT_BEFORE}..HEAD when set) or a fallback of the last commit.
set -uo pipefail

TASKS="${TASKS_FILE:-tasks/TASKS.md}"

# Determine the commit range to scan.
if [ -n "${REVERSE_DRIFT_SINCE:-}" ]; then
  range="${REVERSE_DRIFT_SINCE}..HEAD"
elif [ -n "${GITHUB_EVENT_BEFORE:-}" ] && \
     git rev-parse --quiet --verify "${GITHUB_EVENT_BEFORE}^{commit}" >/dev/null 2>&1; then
  range="${GITHUB_EVENT_BEFORE}..HEAD"
else
  range="HEAD~1..HEAD"
fi

if [ ! -f "$TASKS" ]; then
  echo "[reverse-drift] $TASKS not found — nothing to check (advisory)"
  exit 0
fi

# Collect every T-NNN referenced by a `Task:` trailer in the merged range.
# Trailers may be comma-separated: `Task: T-152, T-153, T-154`.
shipped_ids="$(
  git log --format='%b' "$range" 2>/dev/null \
    | grep -iE '^Task:' \
    | grep -oE 'T-[0-9]+' \
    | sort -u
)"

if [ -z "$shipped_ids" ]; then
  echo "[reverse-drift] no Task: trailers in $range — no drift (advisory)"
  exit 0
fi

drift=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  # Find this task's line in TASKS.md. A [ ] (pending) marker on a shipped
  # task is reverse drift; [s]/[x]/[~]/[!]/[b] are not.
  line="$(grep -E "^- \[.\] ${id}([^0-9]|$)" "$TASKS" 2>/dev/null | head -1)"
  [ -n "$line" ] || continue
  case "$line" in
    "- [ ] ${id}"*)
      drift=$((drift + 1))
      # Secondary signal: does the pending line even carry accept:/summary:?
      signal="no accept:/summary: fields"
      case "$line" in
        *accept:*|*summary:*) signal="has accept:/summary: fields" ;;
      esac
      echo "[reverse-drift] DRIFT: ${id} is [ ] (pending) in $TASKS but a merged commit ships it (${signal})"
      ;;
  esac
done <<< "$shipped_ids"

if [ "$drift" -eq 0 ]; then
  echo "[reverse-drift] no reverse drift in $range (advisory) ✓"
else
  echo "[reverse-drift] ${drift} drifted task(s) — shipped work still marked [ ]. Reconcile via SHIPPED.md / [s] marker (advisory, non-blocking)."
fi

# ADVISORY: never fail the build.
exit 0
