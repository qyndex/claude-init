#!/usr/bin/env bash
# TDD red→green ledger — Round 10 A, hardened by e2e-audit tdd-loop-1/-4.
#
# Captures the failing-then-passing transition as a durable artifact so the
# factory can PROVE a test went red before green.
#
# Usage:
#   bash .claude/scripts/tdd-ledger.sh red   <task-id> "<accept-command>"
#   bash .claude/scripts/tdd-ledger.sh green <task-id> "<accept-command>"
#
# red:   runs the command; REQUIRES non-zero exit (a passing test at red phase
#        means the test asserts nothing or the behavior already exists → error).
#        The failure output is classified: a tooling error (command not found,
#        syntax/import error in the RUNNER itself) is stamped
#        `red_reason: tooling-error` and REJECTED by check-tdd-ledger.sh — a
#        broken runner is not a failing test.
# green: runs the command; REQUIRES zero exit. TDD_GREEN_RUNS=2 re-runs it to
#        catch flakes (every run must pass).
#
# Both runs are bounded by TDD_LEDGER_TIMEOUT (default 300s) so a hung accept
# command cannot stall the loop forever.
#
# Writes verify/<date>/<task-id>/{red,green}.log with a versioned header:
#   ledger_format: 2
#   timestamp / command / exit_code / red_reason (red only)
# check-tdd-ledger.sh parses these headers — do not change field names without
# bumping ledger_format and teaching the checker both versions.

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

TDD_LEDGER_TIMEOUT="${TDD_LEDGER_TIMEOUT:-300}"

# Portable timeout: coreutils timeout, else gtimeout (brew), else run unbounded
# but say so loudly — a silent missing bound would let a hung command stall the
# autonomous loop, which is the exact failure this guards against.
timeout_bin=""
if command -v timeout >/dev/null 2>&1; then timeout_bin="timeout"
elif command -v gtimeout >/dev/null 2>&1; then timeout_bin="gtimeout"
else
  echo "⚠ tdd-ledger: no timeout/gtimeout found — accept command runs UNBOUNDED. brew install coreutils to fix." >&2
fi

run_cmd() {
  # JUSTIFIED: eval is the documented contract of this script — the accept: command from tasks/TASKS.md is a shell command line; it runs under the same permissions as the calling session and is bounded by the timeout above
  if [ -n "$timeout_bin" ]; then
    eval "$timeout_bin ${TDD_LEDGER_TIMEOUT} $cmd" 2>&1
  else
    eval "$cmd" 2>&1
  fi
}

ts=$(date -Iseconds)
output=$(run_cmd)
exit_code=$?

# Timeout exits 124 (coreutils contract).
timed_out=0
[ "$exit_code" -eq 124 ] && [ -n "$timeout_bin" ] && timed_out=1

# Classify a RED failure: real assertion failure vs broken tooling. Per-runner
# signatures — a tooling error means the test never ran, so it proves nothing.
red_reason="assertion-failure"
if [ "$phase" = "red" ]; then
  if [ "$timed_out" = "1" ]; then
    red_reason="timeout"
  elif printf '%s' "$output" | grep -qiE 'command not found|No such file or directory.*(npx|npm|pnpm|yarn|pytest|cargo|go)|ModuleNotFoundError|ImportError: cannot import|Cannot find module|SyntaxError: (Unexpected|invalid)|error: could not compile|no tests? (found|ran|collected)|collected 0 items|No tests found'; then
    red_reason="tooling-error"
  elif [ "$exit_code" -ge 126 ] && [ "$exit_code" -le 127 ]; then
    red_reason="tooling-error"
  fi
fi

write_log() {
  {
    echo "# TDD ledger — $phase — $task_id"
    echo "ledger_format: 2"
    echo "timestamp: $ts"
    echo "command: $cmd"
    echo "exit_code: $exit_code"
    [ "$phase" = "red" ] && echo "red_reason: $red_reason"
    echo "---"
    echo "$output" | tail -50
  } > "$log_file"
}

case "$phase" in
  red)
    if [ "$exit_code" -eq 0 ]; then
      echo "✗ RED phase FAILED: the test passed (exit 0) but should have FAILED."
      echo "  This means: the test asserts nothing, OR the behavior already exists."
      echo "  Fix the test so it fails for the RIGHT reason before implementing."
      rm -f "$log_file"  # don't record a false red
      exit 1
    fi
    write_log
    if [ "$red_reason" != "assertion-failure" ]; then
      echo "✗ RED phase REJECTED: failure classified as '$red_reason', not a failing assertion."
      echo "  A broken/missing runner (or a hang) is not a red test — fix the tooling, then re-run."
      echo "  Log kept for inspection at $log_file but it will NOT satisfy check-tdd-ledger.sh."
      exit 1
    fi
    echo "✓ RED captured: $log_file (exit $exit_code — correctly failing)"
    ;;
  green)
    if [ "$timed_out" = "1" ]; then
      echo "✗ GREEN phase FAILED: accept command timed out after ${TDD_LEDGER_TIMEOUT}s."
      write_log
      exit 1
    fi
    if [ "$exit_code" -ne 0 ]; then
      write_log
      echo "✗ GREEN phase FAILED: the test still fails (exit $exit_code)."
      echo "  Keep implementing until it passes. See $log_file"
      exit 1
    fi
    # Optional flake check: TDD_GREEN_RUNS=N requires N consecutive passes.
    green_runs="${TDD_GREEN_RUNS:-1}"
    if [ "$green_runs" -gt 1 ]; then
      i=2
      while [ "$i" -le "$green_runs" ]; do
        rerun_out=$(run_cmd); rerun_rc=$?
        if [ "$rerun_rc" -ne 0 ]; then
          output="$output
--- re-run $i (exit $rerun_rc) ---
$rerun_out"
          exit_code=$rerun_rc
          write_log
          echo "✗ GREEN phase FAILED: pass did not survive re-run $i/${green_runs} (exit $rerun_rc) — flaky test. See $log_file"
          exit 1
        fi
        i=$((i+1))
      done
    fi
    write_log
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
