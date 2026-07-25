#!/usr/bin/env bash
# T-P2 / AC-2 (spec:005, gap G2) — analyze-coverage.sh writes a structural
# spec→task coverage marker (.claude/state/analyze-<id>.json). Hermetic: runs
# the script against a fixture spec + fixture TASKS.md in a temp tree via the
# ANALYZE_* env hooks, asserting the marker shape, ac_total, the uncovered path,
# and idempotence.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GEN="$ROOT/.claude/scripts/analyze-coverage.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL: $1"; fi; }

test -f "$GEN" || { echo "script missing: $GEN"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/specs" "$tmp/state"

# Fixture spec 042 with three ACs and a distractor AC-9 outside the AC section.
cat > "$tmp/specs/042-fixture.md" <<'MD'
---
id: 042
status: approved
---
# Spec 042: fixture

## Goals
Something referencing AC-9 that must NOT be counted (outside AC section).

## Acceptance criteria

1. **AC-1**: first criterion.
2. **AC-2**: second criterion.
3. **AC-3**: third criterion.

## Constraints
None.
MD

# Fixture TASKS.md: two tasks reference spec:042, one done, one pending.
cat > "$tmp/TASKS.md" <<'MD'
# Tasks
- [x] T-900 | spec:042 | phase:1 | est: 3m
  summary: covered task
- [ ] T-901 | spec:042 | phase:1 | est: 3m
  summary: pending task
- [x] T-902 | spec:003 | phase:1 | est: 3m
  summary: unrelated spec, must not be counted
MD

run() {
  ANALYZE_SPECS_DIR="$tmp/specs" ANALYZE_TASKS="$tmp/TASKS.md" \
    ANALYZE_STATE_DIR="$tmp/state" bash "$GEN" "$@"
}

# --- Covered case: spec 042 has 3 ACs and 2 referencing tasks ---
run 042 >/dev/null 2>&1
rc=$?
check "exit 0 on covered spec" "$rc"

MARK="$tmp/state/analyze-042.json"
test -f "$MARK"; check "writes .claude/state/analyze-042.json" $?

jq -e . "$MARK" >/dev/null 2>&1; check "marker is valid JSON" $?

got_total=$(jq -r '.ac_total' "$MARK" 2>/dev/null)
[ "$got_total" = "3" ]; check "ac_total = 3 (AC-9 outside section excluded)" $?

got_tasks=$(jq -r '.tasks_for_spec' "$MARK" 2>/dev/null)
[ "$got_tasks" = "2" ]; check "tasks_for_spec = 2" $?

got_done=$(jq -r '.tasks_done' "$MARK" 2>/dev/null)
[ "$got_done" = "1" ]; check "tasks_done = 1" $?

acs_len=$(jq -r '.acs | length' "$MARK" 2>/dev/null)
[ "$acs_len" = "3" ]; check "acs array lists all 3 ACs" $?

jq -e '.spec == "042"' "$MARK" >/dev/null 2>&1; check "spec field = 042" $?

# --- Idempotence: re-run produces valid JSON with same ac_total/tasks ---
run 042 >/dev/null 2>&1
total2=$(jq -r '.ac_total' "$MARK" 2>/dev/null)
tasks2=$(jq -r '.tasks_for_spec' "$MARK" 2>/dev/null)
[ "$total2" = "3" ] && [ "$tasks2" = "2" ]; check "idempotent on re-run" $?

# --- Uncovered case: a spec with ACs but zero referencing tasks ---
cat > "$tmp/specs/077-lonely.md" <<'MD'
---
id: 077
status: approved
---
# Spec 077

## Acceptance criteria

1. **AC-1**: only criterion.

## Constraints
MD

out=$(run 077 2>&1); rc=$?
check "exit 0 (advisory) on uncovered spec by default" "$rc"
printf '%s' "$out" | grep -q 'UNCOVERED: spec 077'
check "prints UNCOVERED note for spec with ACs but no tasks" $?

# --check must exit 1 on the uncovered spec.
run --check 077 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ]; check "--check exits 1 on uncovered spec" $?

# --check must exit 0 on the covered spec.
run --check 042 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; check "--check exits 0 on covered spec" $?

echo "analyze-coverage: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
