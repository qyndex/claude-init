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

# TASKS.md snapshot (e2e-audit autopilot-5): the loop's sanctioned mutation
# paths (task-status.sh, record below) refresh this hash; an iteration that
# finds a DIFFERENT hash knows TASKS.md was edited outside the loop and stops.
tasks_snapshot=.claude/state/tasks-md.snapshot
snapshot_tasks() {
  mkdir -p .claude/state
  # JUSTIFIED: a missing TASKS.md hashes to the literal "absent" sentinel
  { shasum -a 256 tasks/TASKS.md 2>/dev/null | awk '{print $1}' || echo absent; } > "$tasks_snapshot"
}

# Subcommand: the caller reports the outcome of the task it just ran so the
# state machine can count aborts / reset on progress.
#   loop-iteration.sh record <task-id> <abort|progress>
if [ "${1:-}" = "record" ]; then
  rec_task="${2:?record needs a task id}"
  rec_status="${3:?record needs abort|progress}"
  loop_state_record "$rec_task" "$rec_status"
  snapshot_tasks
  echo "$ts RECORD $rec_task $rec_status (count=$(loop_state_count))" >> "$iter_log"
  exit 0
fi

# Subcommand: initialize run metadata so --until/--max-iter budgets are real.
#   loop-iteration.sh start [--until <ISO>] [--max-iter <N>]
if [ "${1:-}" = "start" ]; then
  shift
  deadline="" max_iter=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --until) deadline="${2:?--until needs an ISO timestamp}"; shift 2 ;;
      --max-iter) max_iter="${2:?--max-iter needs a number}"; shift 2 ;;
      *) echo "loop-iteration.sh start: unknown flag $1" >&2; exit 64 ;;
    esac
  done
  loop_state_start "$deadline" "$max_iter"
  snapshot_tasks
  echo "$ts START-RUN deadline=${deadline:-none} max_iter=$max_iter" >> "$iter_log"
  echo "loop run started (deadline=${deadline:-none}, max_iter=$max_iter)"
  exit 0
fi

# Before doing anything, honor a prior hard-stop: if the abort cap is already
# reached, refuse to iterate until a human resets the state.
if loop_state_should_stop; then
  echo "$ts STOP consecutive-abort cap reached (count=$(loop_state_count)); reset .claude/state/consecutive-aborts.json to resume" >> "$iter_log"
  echo "consecutive-abort cap reached — loop halted. Reset .claude/state/consecutive-aborts.json (or run a [x] progress) to resume."
  exit 2
fi

# Run budget (e2e-audit autopilot-5): refuse once past --until or --max-iter.
if reason=$(loop_state_run_exceeded); then
  echo "$ts STOP run budget spent — $reason" >> "$iter_log"
  echo "STOP: loop run budget spent — $reason. Start a new run with \`loop-iteration.sh start\` to continue."
  exit 2
fi

# External-edit check (e2e-audit autopilot-5): if TASKS.md changed since the
# loop's last sanctioned touch (start/record/task-status.sh all refresh the
# snapshot), a human or another session edited it mid-run — stop and re-read.
if [ -f "$tasks_snapshot" ]; then
  # JUSTIFIED: a missing TASKS.md hashes to the same "absent" sentinel the snapshot uses
  cur_hash=$({ shasum -a 256 tasks/TASKS.md 2>/dev/null | awk '{print $1}'; } || echo absent)
  [ -z "$cur_hash" ] && cur_hash=absent
  if [ "$cur_hash" != "$(cat "$tasks_snapshot")" ]; then
    snapshot_tasks
    echo "$ts STOP tasks/TASKS.md changed outside the loop (external edit)" >> "$iter_log"
    echo "STOP: tasks/TASKS.md was edited outside the loop's sanctioned paths — re-read the backlog before continuing (snapshot refreshed)."
    exit 2
  fi
fi

loop_state_iterate

# Orphan reconciliation (e2e-audit failure-recovery-3): flip [~] tasks whose
# sessions died (no live heartbeat) to [!] before picking — a dead session's
# task must re-enter the queue as failed work, not haunt the board as "doing".
# JUSTIFIED: best-effort pre-flight — reconciler failure must not block the iteration
bash .claude/scripts/orphan-reconcile.sh >>"$iter_log" 2>&1 || true

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

# Pick next task via the canonical picker (e2e-audit spec-pipeline-2): dep-aware,
# priority-ordered, operator/RESOLVE-blind, immune to the Format template line.
# The autonomous loop also enforces the /analyze gate (spec-pipeline-1): tasks of
# a spec without a PASS analyze marker are ineligible. ANALYZE_GATE=0 opts out
# (interactive/brownfield sessions where /analyze hasn't been adopted yet).
analyze_flag="--require-analyze"
[ "${ANALYZE_GATE:-1}" = "0" ] && analyze_flag=""
# shellcheck disable=SC2086  # JUSTIFICATION: $analyze_flag is our own literal flag or empty (no spaces) ISSUE: #0
next_task=$(bash .claude/scripts/next-task.sh $analyze_flag 2>/dev/null)
pick_rc=$?
if [ "$pick_rc" -eq 1 ]; then
  # ─── Gap-audit G58: empty backlog → ideation branch, not a dead stop ────
  # The loop used to just exit; product momentum died silently. Signal the
  # caller to propose (never auto-promote) the next feature, grounded in the
  # feedback registry + OKR gaps.
  echo "$ts STOP backlog empty → ideation branch" >> "$iter_log"
  mkdir -p .claude/state
  date -Iseconds > .claude/state/ideation-pending
  echo "IDEATE: backlog is empty. Run \`bash .claude/scripts/feedback-score.sh\` + read .claude/memory/feedback/_triage-latest.md and the OKR gap table (/okrs status), then spawn roadmap-architect (plan mode) to write ONE proposal to .claude/memory.proposed/next-feature-$(date +%Y-%m-%d).md citing FB-### / KR-### evidence. PROPOSE ONLY — a human promotes it via /specify."
  exit 1
elif [ "$pick_rc" -ne 0 ]; then
  # rc 3: pending tasks exist but every one is dep-blocked or operator-owned.
  # NOT the ideation branch — surface the block reasons and stop.
  echo "$ts STOP backlog blocked — no eligible task" >> "$iter_log"
  bash .claude/scripts/next-task.sh --why >>"$iter_log" 2>&1 || true
  echo "BLOCKED: pending tasks exist but none is eligible (deps unmet or operator-owned). Run \`bash .claude/scripts/next-task.sh --why\` — operator action or dep completion needed."
  exit 1
fi
# Backlog non-empty → clear any stale ideation flag
rm -f .claude/state/ideation-pending

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
