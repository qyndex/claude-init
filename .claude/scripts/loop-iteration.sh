#!/usr/bin/env bash
# One iteration of the auto-loop. Called by /loop.
# Returns 0 to continue, 1 to stop.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

# Consecutive-aborts state machine — guards against thrash by counting [!] aborts,
# triggering a PIVOT (researcher subagent) on the 2nd same-task abort, and
# hard-stopping at the cap. State persists in .claude/state/consecutive-aborts.json.
# shellcheck source=lib/loop-state.sh
. "$ROOT/.claude/scripts/lib/loop-state.sh"

iter_log=.claude/hooks/.log/loop.log
mkdir -p .claude/hooks/.log
ts=$(date -Iseconds)

# Subcommand: the caller reports the outcome of the task it just ran so the
# state machine can count aborts / reset on progress.
#   loop-iteration.sh record <task-id> <abort|progress>
if [ "${1:-}" = "record" ]; then
  rec_task="${2:?record needs a task id}"
  rec_status="${3:?record needs abort|progress}"
  loop_state_record "$rec_task" "$rec_status"
  echo "$ts RECORD $rec_task $rec_status (count=$(loop_state_count))" >> "$iter_log"
  exit 0
fi

# Before doing anything, honor a prior hard-stop: if the abort cap is already
# reached, refuse to iterate until a human resets the state.
if loop_state_should_stop; then
  echo "$ts STOP consecutive-abort cap reached (count=$(loop_state_count)); reset .claude/state/consecutive-aborts.json to resume" >> "$iter_log"
  echo "consecutive-abort cap reached — loop halted. Reset .claude/state/consecutive-aborts.json (or run a [x] progress) to resume."
  exit 2
fi

# Confirm we're in a worktree
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "$ts FAIL not in a git repo" >> "$iter_log"
  exit 1
fi

branch=$(git symbolic-ref --short HEAD)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  echo "$ts FAIL refusing to loop on $branch" >> "$iter_log"
  exit 1
fi

# Pick next unblocked task
# JUSTIFIED: the redirect drops grep stderr when TASKS.md is absent and the fallback yields empty on no-match (grep exit 1) — an empty next_task is handled by the "no pending tasks" stop below
next_task=$(grep -m1 '^- \[ \]' tasks/TASKS.md 2>/dev/null | head -1 || true)
if [ -z "$next_task" ]; then
  echo "$ts STOP no pending tasks" >> "$iter_log"
  exit 1
fi

task_id=$(echo "$next_task" | grep -oE 'T-[0-9]+' | head -1)
echo "$ts START $task_id" >> "$iter_log"

# Run verify pre-flight
if ! bash .claude/scripts/verify.sh >>"$iter_log" 2>&1; then
  echo "$ts FAIL verify pre-flight" >> "$iter_log"
  exit 1
fi

# If the same task has aborted twice in a row, a PIVOT is due: hand the main
# session the pivot prompt (researcher subagent) instead of a plain re-attempt.
if loop_state_should_pivot; then
  loop_state_mark_pivot
  echo "$ts PIVOT $task_id — 2nd consecutive abort; delegate to researcher with .claude/templates/pivot-prompt.md" >> "$iter_log"
  echo "PIVOT $task_id — this task aborted twice. Delegate to the researcher agent using .claude/templates/pivot-prompt.md to find a different approach before re-attempting."
  exit 0
fi

echo "$ts READY $task_id — main session should now delegate this task to the implementer agent"
exit 0
