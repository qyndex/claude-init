#!/usr/bin/env bash
# check-tdd-ledger.sh — TDD-ledger gate (Spec 003 AC-3).
#
# For every task marked [x] in tasks/TASKS.md, a paired red.log + green.log must
# exist under verify/ ON DISK. Per the operator directive (2026-05-29) ALL .log
# files are gitignored — including nested ledger evidence — so this gate verifies
# ON-DISK presence rather than git-tracking. It runs as the local verify.sh §2
# gate and in the overnight sandbox (where the files exist); a fresh CI checkout
# will not contain gitignored logs, so in a bare-checkout context the gate degrades
# to warn-only (it cannot see evidence that was never committed).
#
# Enforcement floor: hard-fail only for tasks at/after LEDGER_ENFORCE_FROM (default
# T-111 — spec-003). Older tasks predate this gate and are warn-only so prior-session
# work is not penalized. Raise the floor as older specs are back-filled.
#
# Exit 0 = clean, 1 = an enforced [x] task is missing its on-disk ledger.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

[ -f tasks/TASKS.md ] || { echo "no tasks/TASKS.md — nothing to gate"; exit 0; }

LEDGER_ENFORCE_FROM="${LEDGER_ENFORCE_FROM:-111}"

# If verify/ has no on-disk logs at all (e.g. a bare CI checkout where they're
# gitignored), degrade to warn-only — we cannot enforce evidence that isn't here.
have_any_logs=0
# JUSTIFIED: find error muted — absent verify/ simply means zero logs (have_any_logs stays 0)
[ -n "$(find verify -name '*.log' 2>/dev/null | head -1)" ] && have_any_logs=1

fails=0
warns=0
legacy=0
while IFS= read -r task_id; do
  [ -z "$task_id" ] && continue
  tnum="${task_id#T-}"; tnum="${tnum##0}"; [ -n "$tnum" ] || tnum=0
  enforce=1
  case "$tnum" in (''|*[!0-9]*) enforce=0 ;; (*) [ "$tnum" -lt "$LEDGER_ENFORCE_FROM" ] && enforce=0 ;; esac

  red="$(find verify -path "*/${task_id}/red.log" 2>/dev/null | head -1)"
  green="$(find verify -path "*/${task_id}/green.log" 2>/dev/null | head -1)"

  if [ -n "$red" ] && [ -n "$green" ]; then
    echo "✓ $task_id: red+green ledger present on disk"
    continue
  fi

  if [ "$have_any_logs" = "0" ]; then
    # Bare checkout — no logs visible anywhere; cannot enforce.
    warns=$((warns + 1)); continue
  fi
  if [ "$enforce" = "1" ]; then
    echo "✗ $task_id: marked [x] but missing on-disk red.log and/or green.log under verify/"
    fails=$((fails + 1))
  else
    echo "⚠ $task_id: legacy (pre-T-${LEDGER_ENFORCE_FROM}) incomplete ledger — warn only"
    legacy=$((legacy + 1))
  fi
# JUSTIFIED: grep error muted — a missing/empty TASKS.md yields zero ids; the loop runs zero times
done < <(grep -oE '^- \[x\] T-[0-9]+' tasks/TASKS.md 2>/dev/null | grep -oE 'T-[0-9]+')

if [ "$have_any_logs" = "0" ]; then
  echo "tdd-ledger: no on-disk logs (bare checkout?) — gate degraded to warn-only"
  exit 0
fi
echo "tdd-ledger: $fails fail(s), $warns warn(s), $legacy legacy-incomplete (pre-T-${LEDGER_ENFORCE_FROM}, not enforced)"
[ "$fails" -eq 0 ] || exit 1
exit 0
