#!/usr/bin/env bash
# Test for ledger-decay.sh (M-21) — deterministic ledger decay.
#
# Tagged: AC-M21
#
# Runs the decay pass against a hermetic fixture TASKS.md (TASKS_FILE override) so
# the real repo ledger is never touched. Asserts, on a fixture holding four kinds
# of line:
#   (a) an OLD [x] task (completed > DECAY_AGE_DAYS ago) → collapsed to the terse
#       `- [x] T-.. | spec:.. | completed: <date>` form (verbose fields dropped).
#   (b) a RECENT [x] task (completed within the window) → BYTE-IDENTICAL.
#   (c) a live [ ]/[~]/[b] task → BYTE-IDENTICAL.
#   (d) the format-template line + section headers → untouched.
# Idempotent: a second run on the already-decayed file is a no-op.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DECAY="$ROOT/.claude/scripts/ledger-decay.sh"

pass=0
fail=0
fails=()

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expect() { local label="$1" rc="$2"; if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi; }

# JUSTIFIED: BSD/GNU date portability — the BSD form is tried first, the GNU form is the fallback; one always succeeds
old="$(date -v-200d +%Y-%m-%d 2>/dev/null || date -d '200 days ago' +%Y-%m-%d)"
recent="$(date -v-5d +%Y-%m-%d 2>/dev/null || date -d '5 days ago' +%Y-%m-%d)"

export TASKS_FILE="$TMP/TASKS.md"
export DECAY_AGE_DAYS=90

# Fixture: template line (inside a fenced block), a header, and four task lines.
{
  echo "# Tasks"
  echo
  echo '```'
  echo "- [ ] T-NNN  | spec:NNN  | phase:N  | priority: <P>  | created: <ISO>  | last_touched: <ISO>  | completed: <ISO>"
  echo '```'
  echo
  echo "## Active"
  echo
  echo "- [x] T-001 | spec:001 | phase:1 | priority: normal | created: $old | last_touched: $old | completed: $old"
  echo "      summary: an old finished task that should collapse"
  echo "      accept: true"
  echo "- [x] T-002 | spec:001 | phase:2 | priority: normal | created: $recent | last_touched: $recent | completed: $recent"
  echo "      summary: a recently finished task that must stay verbatim"
  echo "- [ ] T-003 | spec:001 | phase:3 | priority: P1-spec | created: $recent | last_touched: $recent | deps: | parallel: yes | est: 5m"
  echo "      summary: a live pending task that must stay verbatim"
  echo "- [~] T-004 | spec:001 | phase:4 | priority: normal | created: $recent | last_touched: $recent"
  echo "      summary: an in-progress task that must stay verbatim"
} >"$TASKS_FILE"

# Capture exact byte-copies of the lines that must survive unchanged. We compare
# line CONTENT (grep without -n), not line NUMBER: collapsing an earlier block
# legitimately shifts the line numbers of everything below it, but every surviving
# line's bytes must be identical.
recent_before="$(grep 'T-002' "$TASKS_FILE" | head -1)"
live_before="$(grep 'T-003' "$TASKS_FILE")"
inprog_before="$(grep 'T-004' "$TASKS_FILE")"
template_before="$(grep 'T-NNN' "$TASKS_FILE")"
header_before="$(grep '^## Active' "$TASKS_FILE")"

bash "$DECAY" >/dev/null 2>&1
decay_rc=$?
expect "ledger-decay exits 0" "$decay_rc"

# (a) OLD [x] collapsed to terse form: preserves id/status/spec/completed, drops the rest.
grep -qE '^- \[x\] T-001 \| spec:001 \| completed: '"$old"'$' "$TASKS_FILE"; expect "old done task collapsed to terse form" $?
# The verbose fields must be gone from the T-001 marker line.
! grep -qE '^- \[x\] T-001 .*priority:' "$TASKS_FILE"; expect "old done task verbose fields dropped" $?
# Its indented continuation (summary) is also collapsed away.
! grep -q 'an old finished task that should collapse' "$TASKS_FILE"; expect "old done task continuation dropped" $?

# (b) RECENT [x] BYTE-IDENTICAL.
[ "$(grep 'T-002' "$TASKS_FILE" | head -1)" = "$recent_before" ]; expect "recent done task byte-identical" $?
grep -q 'a recently finished task that must stay verbatim' "$TASKS_FILE"; expect "recent done continuation preserved" $?

# (c) live [ ] and [~] BYTE-IDENTICAL.
[ "$(grep 'T-003' "$TASKS_FILE")" = "$live_before" ]; expect "live pending task byte-identical" $?
[ "$(grep 'T-004' "$TASKS_FILE")" = "$inprog_before" ]; expect "in-progress task byte-identical" $?

# (d) template line + header untouched.
[ "$(grep 'T-NNN' "$TASKS_FILE")" = "$template_before" ]; expect "template line untouched" $?
[ "$(grep '^## Active' "$TASKS_FILE")" = "$header_before" ]; expect "section header untouched" $?

# Idempotent: second run is a no-op.
cp "$TASKS_FILE" "$TMP/after-1.md"
bash "$DECAY" >/dev/null 2>&1
diff -q "$TASKS_FILE" "$TMP/after-1.md" >/dev/null 2>&1; expect "ledger-decay is idempotent" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
