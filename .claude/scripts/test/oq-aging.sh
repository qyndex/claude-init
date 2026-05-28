#!/usr/bin/env bash
# Test for oq-aging.sh (Spec 001 AC-5, OQ-aging half).
#
# Tagged: AC-05
#
# Seeds an [OQ-1] item in a spec backdated >7 days, runs oq-aging.sh against a
# hermetic specs dir + tasks file, and asserts a P1-spec RESOLVE task appears
# with a last_touched date and a back-link to the spec. Also asserts idempotency
# (a second run does not append a duplicate) and that a fresh (<7d) OQ is skipped.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/.claude/scripts/oq-aging.sh"

pass=0
fail=0
fails=()

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export SPECS_DIR="$TMP/specs/active"
export TASKS_FILE="$TMP/TASKS.md"
mkdir -p "$SPECS_DIR/007-aged" "$SPECS_DIR/008-fresh"

# A minimal TASKS.md with the Active section the append helper targets.
cat >"$TASKS_FILE" <<'EOF'
# Tasks

## Active

## Backlog
EOF

old_date="$(date -v-8d +%Y-%m-%d 2>/dev/null || date -d '8 days ago' +%Y-%m-%d)"
new_date="$(date +%Y-%m-%d)"

# Aged spec — should escalate.
cat >"$SPECS_DIR/007-aged/spec.md" <<EOF
# Aged feature
created: $old_date

## Open questions
- [OQ-1] Should the widget support dark mode? created: $old_date
EOF

# Fresh spec — should be skipped.
cat >"$SPECS_DIR/008-fresh/spec.md" <<EOF
# Fresh feature
created: $new_date

## Open questions
- [OQ-1] Which colour palette? created: $new_date
EOF

expect() { # expect <label> <condition-rc>
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi
}

# ---- run 1 ----
bash "$SCRIPT" >/dev/null 2>&1

grep -qE 'RESOLVE: .*007-aged.*OQ-1' "$TASKS_FILE"
expect "aged OQ escalated to a RESOLVE task" $?

grep -E 'RESOLVE: .*007-aged.*OQ-1' "$TASKS_FILE" | grep -q 'P1-spec'
expect "escalated task is priority P1-spec" $?

grep -A2 -E 'RESOLVE: .*007-aged' "$TASKS_FILE" | grep -q 'last_touched'
expect "escalated task carries last_touched" $?

grep -A3 -E 'RESOLVE: .*007-aged' "$TASKS_FILE" | grep -qE 'specs/active/007-aged|007-aged/spec.md'
expect "escalated task back-links the spec" $?

! grep -qE 'RESOLVE: .*008-fresh' "$TASKS_FILE"
expect "fresh OQ (<7d) is NOT escalated" $?

# ---- run 2 — idempotent ----
bash "$SCRIPT" >/dev/null 2>&1
count=$(grep -cE 'RESOLVE: .*007-aged.*OQ-1' "$TASKS_FILE")
[ "$count" -eq 1 ]
expect "second run does not duplicate the RESOLVE task" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
