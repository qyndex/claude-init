#!/usr/bin/env bash
# Test for hot-cache.sh (M-22) — hot-context session cache generator.
#
# Tagged: AC-M22
#
# Runs the generator against a hermetic fixture tree (ROOT_OVERRIDE) so the real
# repo cache is never touched. Asserts:
#   - it writes .claude/memory/.cache/hot.md under the target root.
#   - it respects HOT_CAP (total lines <= cap).
#   - it captures the current in-progress ([~]) task and recent completed tasks.
#   - it is idempotent modulo a single timestamp line (second run byte-identical
#     after the timestamp line is stripped).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOT="$ROOT/.claude/scripts/hot-cache.sh"

pass=0
fail=0
fails=()

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expect() { local label="$1" rc="$2"; if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi; }

# JUSTIFIED: BSD/GNU date portability — BSD form first, GNU fallback; one succeeds
d1="$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '1 day ago' +%Y-%m-%d)"

# Build a fixture repo root with a TASKS.md holding an in-progress + several done tasks.
mkdir -p "$TMP/tasks" "$TMP/.claude/memory"
{
  echo "## Active"
  echo
  echo "- [~] T-500 | spec:009 | phase:1 | priority: normal | created: $d1 | last_touched: $d1"
  echo "      summary: the task currently in progress"
  for i in 1 2 3 4 5 6 7 8; do
    echo "- [x] T-4$i | spec:009 | phase:1 | priority: normal | completed: $d1"
    echo "      summary: completed task number $i"
  done
} >"$TMP/tasks/TASKS.md"

export ROOT_OVERRIDE="$TMP"
export HOT_CAP=20

bash "$HOT" >/dev/null 2>&1; expect "hot-cache exits 0" $?

cache="$TMP/.claude/memory/.cache/hot.md"
[ -f "$cache" ]; expect "hot.md was created" $?

lines=$(wc -l <"$cache" 2>/dev/null || echo 999)
[ "$lines" -le "$HOT_CAP" ]; expect "hot.md respects HOT_CAP line budget" $?

grep -q 'T-500' "$cache"; expect "hot.md captures the in-progress task" $?
grep -qE 'T-4[0-9]' "$cache"; expect "hot.md captures recent completed tasks" $?

# Idempotency modulo the timestamp line: strip any "generated:"/timestamp line,
# then the two runs must be byte-identical.
strip() { grep -vE '^(_?generated|<!-- generated|generated:)' "$1"; }
strip "$cache" >"$TMP/run1.txt"
bash "$HOT" >/dev/null 2>&1
strip "$cache" >"$TMP/run2.txt"
diff -q "$TMP/run1.txt" "$TMP/run2.txt" >/dev/null 2>&1; expect "hot-cache is idempotent (modulo timestamp)" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
