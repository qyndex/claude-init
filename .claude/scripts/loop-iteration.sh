#!/usr/bin/env bash
# One iteration of the auto-loop. Called by /loop.
# Returns 0 to continue, 1 to stop.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

iter_log=.claude/hooks/.log/loop.log
mkdir -p .claude/hooks/.log
ts=$(date -Iseconds)

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

echo "$ts READY $task_id — main session should now delegate this task to the implementer agent"
exit 0
