#!/usr/bin/env bash
# TDD red→green ledger — Round 10 A.
#
# Captures the failing-then-passing transition as a durable artifact so the
# factory can PROVE a test went red before green.
#
# Usage:
#   bash .claude/scripts/tdd-ledger.sh red   <task-id> "<accept-command>"
#   bash .claude/scripts/tdd-ledger.sh green <task-id> "<accept-command>"
#
# red:   runs the command; REQUIRES non-zero exit (a passing test at red phase
#        means the test asserts nothing or the behavior already exists → error)
# green: runs the command; REQUIRES zero exit
#
# Writes verify/<date>/<task-id>/{red,green}.log with command + exit + output.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

phase="${1:-}"
task_id="${2:-}"
cmd="${3:-}"

if [ -z "$phase" ] || [ -z "$task_id" ] || [ -z "$cmd" ]; then
  echo "Usage: tdd-ledger.sh <red|green> <task-id> \"<accept-command>\""
  exit 1
fi

date_dir="verify/$(date +%Y-%m-%d)/${task_id}"
mkdir -p "$date_dir"
log_file="$date_dir/${phase}.log"

# Run the command, capture everything
ts=$(date -Iseconds)
output=$(eval "$cmd" 2>&1)
exit_code=$?

{
  echo "# TDD ledger — $phase — $task_id"
  echo "timestamp: $ts"
  echo "command: $cmd"
  echo "exit_code: $exit_code"
  echo "---"
  echo "$output" | tail -50
} > "$log_file"

case "$phase" in
  red)
    if [ "$exit_code" -eq 0 ]; then
      echo "✗ RED phase FAILED: the test passed (exit 0) but should have FAILED."
      echo "  This means: the test asserts nothing, OR the behavior already exists."
      echo "  Fix the test so it fails for the RIGHT reason before implementing."
      rm -f "$log_file"  # don't record a false red
      exit 1
    fi
    echo "✓ RED captured: $log_file (exit $exit_code — correctly failing)"
    ;;
  green)
    if [ "$exit_code" -ne 0 ]; then
      echo "✗ GREEN phase FAILED: the test still fails (exit $exit_code)."
      echo "  Keep implementing until it passes. See $log_file"
      exit 1
    fi
    # Confirm a red.log preceded this green
    if [ ! -f "$date_dir/red.log" ]; then
      echo "⚠ GREEN captured but NO red.log exists for $task_id."
      echo "  TDD requires red BEFORE green. This task will fail verify.sh's TDD gate."
    fi
    echo "✓ GREEN captured: $log_file (exit 0 — passing)"
    ;;
  *)
    echo "phase must be 'red' or 'green'"
    exit 1
    ;;
esac
