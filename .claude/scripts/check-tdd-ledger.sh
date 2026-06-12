#!/usr/bin/env bash
# check-tdd-ledger.sh — TDD-ledger gate (Spec 003 AC-3; e2e-audit tdd-loop-1/-2,
# brownfield-6). THE single implementation — verify.sh §2 calls this script.
#
# For every task marked [x] in tasks/TASKS.md, a paired red.log + green.log must
# exist under verify/. Since the e2e-audit P2.1 decision (2026-06-12) red/green
# logs are git-COMMITTED (scoped .gitignore negation), so this gate enforces in
# CI checkouts too. If verify/ has no logs at all (pre-P2.1 history) the gate
# degrades to warn-only — it cannot enforce evidence that was never committed.
#
# CONTENT checks (ledger_format: 2 headers written by tdd-ledger.sh):
#   - red.log  exit_code != 0, red_reason == assertion-failure
#   - green.log exit_code == 0
#   - command: identical (whitespace-normalized) in red and green; when the
#     task line carries `accept:`, the ledger command must match it too
#   - red timestamp strictly before green timestamp
# Format-1 logs (no ledger_format line) get existence + what fields they have.
#
# Characterization exemption (brownfield-6): a green.log carrying
# `characterization: true` (or a `characterization` marker file in the task
# dir) is accepted WITHOUT red.log — golden-master tests pin existing behavior,
# so there is no red phase. Applies only to that task, loudly noted.
#
# Enforcement floor: hard-fail only for tasks at/after LEDGER_ENFORCE_FROM
# (default T-111 — spec-003). Older tasks are warn-only.
#
# Exit 0 = clean, 1 = an enforced [x] task fails the gate.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

[ -f tasks/TASKS.md ] || { echo "no tasks/TASKS.md — nothing to gate"; exit 0; }

LEDGER_ENFORCE_FROM="${LEDGER_ENFORCE_FROM:-111}"

have_any_logs=0
# JUSTIFIED: find error muted — absent verify/ simply means zero logs (have_any_logs stays 0)
[ -n "$(find verify -name '*.log' 2>/dev/null | head -1)" ] && have_any_logs=1

hdr() { # hdr <file> <field> — first value of "field: ..." in the header block
  sed -n "s/^${2}: //p" "$1" 2>/dev/null | head -1
}
norm() { # squeeze whitespace for command comparison
  printf '%s' "$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
}

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

  # Characterization exemption (brownfield-6): green-only is legitimate when
  # the green log (or a marker file beside it) declares characterization.
  if [ -z "$red" ] && [ -n "$green" ]; then
    if grep -qiE '^characterization: *true' "$green" 2>/dev/null \
       || [ -f "$(dirname "$green")/characterization" ]; then
      echo "✓ $task_id: characterization task — green-only ledger accepted (no red phase for golden-master tests)"
      continue
    fi
  fi

  if [ -z "$red" ] || [ -z "$green" ]; then
    if [ "$have_any_logs" = "0" ]; then
      warns=$((warns + 1)); continue
    fi
    if [ "$enforce" = "1" ]; then
      echo "✗ $task_id: marked [x] but missing red.log and/or green.log under verify/"
      fails=$((fails + 1))
    else
      echo "⚠ $task_id: legacy (pre-T-${LEDGER_ENFORCE_FROM}) incomplete ledger — warn only"
      legacy=$((legacy + 1))
    fi
    continue
  fi

  # ── Content checks (tdd-loop-1: existence alone is forgeable) ──
  bad=""
  red_exit="$(hdr "$red" exit_code)"
  green_exit="$(hdr "$green" exit_code)"
  red_ts="$(hdr "$red" timestamp)"
  green_ts="$(hdr "$green" timestamp)"
  red_cmd="$(norm "$(hdr "$red" command)")"
  green_cmd="$(norm "$(hdr "$green" command)")"
  red_reason="$(hdr "$red" red_reason)"

  if [ -n "$red_exit" ] && [ "$red_exit" = "0" ]; then
    bad="$bad red.log exit_code=0 (red phase must FAIL);"
  fi
  if [ -n "$green_exit" ] && [ "$green_exit" != "0" ]; then
    bad="$bad green.log exit_code=$green_exit (green phase must PASS);"
  fi
  if [ -n "$red_reason" ] && [ "$red_reason" != "assertion-failure" ]; then
    bad="$bad red_reason=$red_reason (a broken runner/hang is not a failing test);"
  fi
  if [ -n "$red_cmd" ] && [ -n "$green_cmd" ] && [ "$red_cmd" != "$green_cmd" ]; then
    bad="$bad command differs between red and green (must prove the SAME test);"
  fi
  if [ -n "$red_ts" ] && [ -n "$green_ts" ] && ! [ "$red_ts" \< "$green_ts" ]; then
    bad="$bad red timestamp ($red_ts) not before green ($green_ts);"
  fi
  # Cross-check against the task's accept: command when present.
  task_line="$(grep -E "^- \[x\] ${task_id}([^0-9]|\$)" tasks/TASKS.md 2>/dev/null | head -1)"
  accept_cmd="$(printf '%s' "$task_line" | sed -n 's/.*accept: *//p' | sed 's/ *|.*$//')"
  if [ -n "$accept_cmd" ] && [ -n "$green_cmd" ]; then
    accept_norm="$(norm "$accept_cmd")"
    if [ "$green_cmd" != "$accept_norm" ]; then
      # Warn-strength: ledgers may legitimately run a scoped subset of accept.
      echo "⚠ $task_id: ledger command ('$green_cmd') != task accept: ('$accept_norm')"
      warns=$((warns + 1))
    fi
  fi

  if [ -n "$bad" ]; then
    if [ "$enforce" = "1" ]; then
      echo "✗ $task_id: ledger content invalid —${bad}"
      fails=$((fails + 1))
    else
      echo "⚠ $task_id: legacy ledger content invalid (warn only) —${bad}"
      legacy=$((legacy + 1))
    fi
  else
    echo "✓ $task_id: red+green ledger present and content-valid"
  fi
# JUSTIFIED: grep error muted — a missing/empty TASKS.md yields zero ids; the loop runs zero times
done < <(grep -oE '^- \[x\] T-[0-9]+' tasks/TASKS.md 2>/dev/null | grep -oE 'T-[0-9]+')

if [ "$have_any_logs" = "0" ]; then
  echo "tdd-ledger: no on-disk logs (pre-P2.1 history or bare checkout) — gate degraded to warn-only"
  exit 0
fi
echo "tdd-ledger: $fails fail(s), $warns warn(s), $legacy legacy-incomplete (pre-T-${LEDGER_ENFORCE_FROM}, not enforced)"
[ "$fails" -eq 0 ] || exit 1
exit 0
