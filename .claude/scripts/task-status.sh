#!/usr/bin/env bash
# task-status.sh — the SANCTIONED write path for task state (e2e-audit failure-recovery-1).
#
# Write/Edit on tasks/TASKS.md is constitution-guarded (pre-edit-constitution-guard.sh
# denies it), yet every inner-loop agent must flip status markers. This CLI closes the
# contradiction: agents call it via Bash. It serializes under with_tasks_lock, verifies
# the flip landed, then runs the two side-effects that previously only fired on Write
# tool events and were therefore unreachable from Bash mutations:
#   1. spec-status-sync.sh   — spec advance (post-write-roadmap.sh's PostToolUse job)
#   2. loop-iteration.sh record <id> <abort|progress> on [!]/[x] flips (loop-control producer)
#
# Usage:
#   bash .claude/scripts/task-status.sh T-42 done
#   bash .claude/scripts/task-status.sh 42 '!' --note "accept command timed out"
#
# Status words map to canonical markers: pending=' ' doing='~' done='x' failed='!'
# blocked='b' skipped='s'. Raw single-char markers are accepted too.
# Exit codes: 0 flipped · 2 usage/bad marker · 3 unknown task id · 4 flip did not land
# · 75 lock busy (retry later — with-lock.sh contract).

set -uo pipefail

cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
. .claude/scripts/lib/tasks-lib.sh

id="${1:-}"
status_word="${2:-}"
note=""
if [ "${3:-}" = "--note" ]; then note="${4:-}"; fi

if [ -z "$id" ] || [ -z "$status_word" ]; then
  echo "usage: task-status.sh <T-id> <pending|doing|done|failed|blocked|skipped | ' '|~|x|!|b|s> [--note \"...\"]" >&2
  exit 2
fi

case "$status_word" in
  pending) marker=" " ;;
  doing|in-progress) marker="~" ;;
  done) marker="x" ;;
  failed) marker="!" ;;
  blocked) marker="b" ;;
  skipped) marker="s" ;;
  " "|"~"|"x"|"!"|"b"|"s") marker="$status_word" ;;
  *) echo "task-status.sh: unknown status '${status_word}'" >&2; exit 2 ;;
esac

_flip() { tasks_set_status "$id" "$marker"; }
with_tasks_lock _flip
rc=$?
if [ "$rc" -ne 0 ]; then
  if [ "$rc" -eq 75 ]; then
    echo "task-status.sh: TASKS.md lock busy — retry" >&2
  fi
  exit "$rc"
fi

# Optional audit note — appended to the task line's pipe fields would corrupt the
# grammar, so notes go to the loop log instead (greppable, never load-bearing).
if [ -n "$note" ]; then
  mkdir -p .claude/state 2>/dev/null
  printf '%s\tT-%s\t[%s]\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${id#T-}" "$marker" "$note" \
    >> .claude/state/task-status-notes.log 2>/dev/null || true
fi

# TASK_STATUS_NO_SYNC=1 (rig/tests only): skip side-effects so a sandboxed
# TASKS_FILE flip never touches the real specs/ or loop state.
if [ "${TASK_STATUS_NO_SYNC:-0}" != "1" ]; then
  # Side-effect 1: spec advance (same call post-write-roadmap.sh makes on Write events).
  # JUSTIFIED: output suppressed and failure tolerated — sync is best-effort projection; the flip above is the source of truth and already verified
  bash .claude/scripts/spec-status-sync.sh >/dev/null 2>&1 || true

  # Side-effect 2: loop-control producer — keep the consecutive-aborts machine truthful.
  case "$marker" in
    x) bash .claude/scripts/loop-iteration.sh record "T-${id#T-}" progress >/dev/null 2>&1 || true ;;
    !) bash .claude/scripts/loop-iteration.sh record "T-${id#T-}" abort >/dev/null 2>&1 || true ;;
  esac

  # Side-effect 3: refresh the loop's TASKS.md snapshot so this sanctioned flip
  # is not mistaken for an external edit (record above already refreshes on x/!).
  # JUSTIFIED: snapshot is best-effort loop telemetry — a write failure must not fail the flip
  { shasum -a 256 "$TASKS_FILE" 2>/dev/null | awk '{print $1}' || echo absent; } \
    > .claude/state/tasks-md.snapshot 2>/dev/null || true
fi

echo "T-${id#T-} -> [${marker}]"
