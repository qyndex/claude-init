#!/usr/bin/env bash
# Test for the GC suite — gc-tasks.sh, gc-verify.sh, gc-logs.sh (Spec 001 AC, Phase 3).
#
# Tagged: AC-08
#
# Each GC script is exercised against a hermetic fixture tree (env overrides) so
# the real repo is never touched. Asserts: gc-tasks archives old done/skipped
# tasks when TASKS.md exceeds the line cap; gc-verify moves verify/ dirs older
# than the retention window into an archive; gc-logs rotates oversized .log files.
# Each is asserted idempotent (a second run is a no-op on already-archived state).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GC_TASKS="$ROOT/.claude/scripts/gc-tasks.sh"
GC_VERIFY="$ROOT/.claude/scripts/gc-verify.sh"
GC_LOGS="$ROOT/.claude/scripts/gc-logs.sh"

pass=0
fail=0
fails=()

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expect() { local label="$1" rc="$2"; if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi; }

# ───────────────────────── gc-tasks ─────────────────────────
# Build a TASKS.md over the line cap with old done/skipped tasks to archive.
export TASKS_FILE="$TMP/TASKS.md"
export TASKS_ARCHIVE_DIR="$TMP/tasks-archive"
export GC_TASKS_LINE_CAP=50            # small cap so the fixture trips it
export GC_TASKS_DONE_AGE_DAYS=30
# JUSTIFIED: BSD/GNU date portability in the fixture — the BSD form is tried first, the GNU form is the fallback; one always succeeds
old="$(date -v-40d +%Y-%m-%d 2>/dev/null || date -d '40 days ago' +%Y-%m-%d)"
{
  echo "# Tasks"
  echo
  echo "## Active"
  for i in $(seq 1 40); do
    echo "- [x] T-$i | priority: P2 | completed: $old"
    echo "      summary: old finished task $i"
  done
  echo "- [ ] T-99 | priority: P1 | created: $(date +%Y-%m-%d)"
  echo "      summary: a live pending task that must stay"
  echo
  echo "## Backlog"
} >"$TASKS_FILE"

before_lines=$(wc -l <"$TASKS_FILE")
bash "$GC_TASKS" >/dev/null 2>&1

[ "$before_lines" -gt "$GC_TASKS_LINE_CAP" ]; expect "fixture TASKS.md exceeds the cap" $?
[ -d "$TASKS_ARCHIVE_DIR" ] && ls "$TASKS_ARCHIVE_DIR"/TASKS-*.md >/dev/null 2>&1; expect "gc-tasks created an archive file" $?
grep -q 'T-99' "$TASKS_FILE"; expect "gc-tasks kept the live pending task" $?
! grep -q 'T-1 |' "$TASKS_FILE"; expect "gc-tasks removed an old done task from the live file" $?
# JUSTIFIED: test assertion — the suppressed grep stderr/exit is captured as the rc that `expect` checks; suppression keeps the test output clean
grep -rq 'T-1 |' "$TASKS_ARCHIVE_DIR" 2>/dev/null; expect "the old done task landed in the archive" $?

# Idempotent: second run does not re-archive / corrupt.
cp "$TASKS_FILE" "$TMP/tasks-after-1.md"
bash "$GC_TASKS" >/dev/null 2>&1
diff -q "$TASKS_FILE" "$TMP/tasks-after-1.md" >/dev/null 2>&1; expect "gc-tasks is idempotent" $?

# ───────────────────────── gc-verify ─────────────────────────
export VERIFY_DIR="$TMP/verify"
export VERIFY_ARCHIVE_DIR="$TMP/verify/archive"
export GC_VERIFY_AGE_DAYS=30
mkdir -p "$VERIFY_DIR/2020-01-01/T-1" "$VERIFY_DIR/$(date +%Y-%m-%d)/T-2"
echo old >"$VERIFY_DIR/2020-01-01/T-1/red.log"
echo new >"$VERIFY_DIR/$(date +%Y-%m-%d)/T-2/red.log"
# Backdate the old dir's mtime well past the window.
# JUSTIFIED: fixture setup — the redirect and fallback tolerate touch failing on filesystems that reject explicit mtimes; the age test below still drives the assertion
touch -t 202001010000 "$VERIFY_DIR/2020-01-01" 2>/dev/null || true

bash "$GC_VERIFY" >/dev/null 2>&1
[ ! -d "$VERIFY_DIR/2020-01-01" ] || [ -d "$VERIFY_ARCHIVE_DIR/2020-01-01" ]; expect "gc-verify moved the old verify dir to archive" $?
[ -d "$VERIFY_DIR/$(date +%Y-%m-%d)" ]; expect "gc-verify kept the recent verify dir" $?
bash "$GC_VERIFY" >/dev/null 2>&1; expect "gc-verify second run exits clean (idempotent)" $?

# ───────────────────────── gc-logs ─────────────────────────
export LOG_DIR="$TMP/logs"
export GC_LOG_MAX_BYTES=1024            # 1KB cap so the fixture trips it
mkdir -p "$LOG_DIR"
# A >1KB log and a small one.
head -c 4096 /dev/zero | tr '\0' 'x' >"$LOG_DIR/big.log"
echo "small" >"$LOG_DIR/small.log"

bash "$GC_LOGS" >/dev/null 2>&1
[ -f "$LOG_DIR/big.log.1" ]; expect "gc-logs rotated the oversized log to .log.1" $?
[ "$(wc -c <"$LOG_DIR/big.log")" -lt 4096 ]; expect "gc-logs truncated the live log after rotation" $?
[ ! -f "$LOG_DIR/small.log.1" ]; expect "gc-logs left the small log alone" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
