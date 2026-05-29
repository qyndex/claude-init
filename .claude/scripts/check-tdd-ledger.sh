#!/usr/bin/env bash
# check-tdd-ledger.sh — server-side TDD-ledger gate (Spec 003 AC-3).
#
# Runs in CI (harness-validate job) where an agent cannot set SKIP_* env vars,
# so it is the authoritative re-check of the client-side gate in verify.sh §2.
# For every task marked [x] in tasks/TASKS.md, a paired red.log + green.log must
# exist under verify/.
#
# R-1 mitigation: only FAIL for tasks whose verify/ evidence directory is
# git-TRACKED (so legitimately-gitignored local evidence can't false-fail CI).
# A tracked task missing a log is a hard fail; an untracked one only warns.
#
# Exit 0 = clean, 1 = at least one tracked [x] task missing its ledger.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

[ -f tasks/TASKS.md ] || { echo "no tasks/TASKS.md — nothing to gate"; exit 0; }

# Set of git-tracked paths under verify/ (empty if not a git repo / nothing tracked).
# JUSTIFIED: git ls-files error muted — outside a repo we fall back to treating all as untracked (warn-only), never a false CI fail
tracked="$(git ls-files 'verify/*' 2>/dev/null || true)"

# Enforcement floor: hard-fail only for tasks at/after this id. Tasks before it
# predate the ledger-tracking fix (Spec 003 — *.log was gitignored, so historical
# red/green evidence was never committable) and are reported warn-only to avoid
# penalizing prior-session work that legitimately ran TDD but couldn't persist the
# logs. Raise this floor as older specs are back-filled. Override: LEDGER_ENFORCE_FROM.
LEDGER_ENFORCE_FROM="${LEDGER_ENFORCE_FROM:-111}"

fails=0
warns=0
legacy=0
while IFS= read -r task_id; do
  [ -z "$task_id" ] && continue
  # Numeric id for the floor comparison (T-093 → 93).
  tnum="${task_id#T-}"; tnum="${tnum##0}"; [ -n "$tnum" ] || tnum=0
  enforce=1
  case "$tnum" in (''|*[!0-9]*) enforce=0 ;; (*) [ "$tnum" -lt "$LEDGER_ENFORCE_FROM" ] && enforce=0 ;; esac
  red="$(find verify -path "*/${task_id}/red.log" 2>/dev/null | head -1)"
  green="$(find verify -path "*/${task_id}/green.log" 2>/dev/null | head -1)"

  if [ -n "$red" ] && [ -n "$green" ]; then
    # Both present — confirm at least one is tracked (real evidence, not a local stub).
    if printf '%s\n' "$tracked" | grep -q "${task_id}/green.log"; then
      echo "✓ $task_id: red+green ledger present (tracked)"
    else
      echo "⚠ $task_id: ledger present but untracked — warn only"
      warns=$((warns + 1))
    fi
    continue
  fi

  # Missing a log. Hard-fail only if the task's evidence dir is tracked AND the
  # task is at/after the enforcement floor.
  if printf '%s\n' "$tracked" | grep -q "/${task_id}/"; then
    if [ "$enforce" = "1" ]; then
      echo "✗ $task_id: marked [x] with tracked verify/ dir but missing red.log and/or green.log"
      fails=$((fails + 1))
    else
      echo "⚠ $task_id: legacy (pre-T-${LEDGER_ENFORCE_FROM}) incomplete ledger — warn only"
      legacy=$((legacy + 1))
    fi
  else
    echo "⚠ $task_id: marked [x], no tracked ledger (evidence gitignored?) — warn only"
    warns=$((warns + 1))
  fi
# JUSTIFIED: grep error muted — a missing/empty TASKS.md yields zero ids; the loop simply runs zero times
done < <(grep -oE '^- \[x\] T-[0-9]+' tasks/TASKS.md 2>/dev/null | grep -oE 'T-[0-9]+')

echo "tdd-ledger: $fails fail(s), $warns warn(s), $legacy legacy-incomplete (pre-T-${LEDGER_ENFORCE_FROM}, not enforced)"
[ "$fails" -eq 0 ] || exit 1
exit 0
