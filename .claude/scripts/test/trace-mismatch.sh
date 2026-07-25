#!/usr/bin/env bash
# T-P4 / AC-4 (spec:005, gap G4) — trace-mismatch.sh surfaces specs whose tasks
# read done but whose SHIPPED.md evidence verdict is FAIL/UNPROVEN. Hermetic:
# fixture SHIPPED.md (one FAIL spec, one PASS spec) + fixture TASKS.md (both
# specs' tasks all [x]) via the TRACE_* env hooks. Asserts exactly one
# TRACE-MISMATCH (the FAIL-but-done spec), none for the PASS spec, and --check
# exit code.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GEN="$ROOT/.claude/scripts/trace-mismatch.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL: $1"; fi; }

test -f "$GEN" || { echo "script missing: $GEN"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Fixture SHIPPED.md in the real generated format (pipe table, BEGIN/END markers).
cat > "$tmp/SHIPPED.md" <<'MD'
# SHIPPED registry

<!-- BEGIN:shipped-registry (generated) -->

| Spec | Verdict | AC proven | Shipped (evidence) | Commit | PR / merge |
| ---- | ------- | --------- | ------------------ | ------ | ---------- |
| 011 | FAIL | 0/27 | 2026-06-14 (verify/x) | 2e8727a9d | — |
| 022 | PASS | 18/18 | 2026-06-14 (verify/y) | 5ab984753 | #13 |

<!-- END:shipped-registry -->
MD

# Fixture TASKS.md: spec 011's tasks all [x]; spec 022's tasks all [x].
cat > "$tmp/TASKS.md" <<'MD'
# Tasks
- [x] T-800 | spec:011 | phase:1 | est: 3m
  summary: done fail-spec task
- [x] T-801 | spec:011 | phase:1 | est: 3m
  summary: another done fail-spec task
- [x] T-810 | spec:022 | phase:1 | est: 3m
  summary: done pass-spec task
MD

run() { TRACE_SHIPPED="$tmp/SHIPPED.md" TRACE_TASKS="$tmp/TASKS.md" bash "$GEN" "$@"; }

out=$(run 2>&1); rc=$?
check "default advisory run exits 0" "$rc"

# Exactly one TRACE-MISMATCH, and it names spec 011 (FAIL but tasks done).
mm_count=$(printf '%s\n' "$out" | grep -c '^TRACE-MISMATCH:') || true
[ "${mm_count:-0}" -eq 1 ]; check "exactly one TRACE-MISMATCH line" $?

printf '%s\n' "$out" | grep -q 'TRACE-MISMATCH: spec 011'
check "TRACE-MISMATCH names the FAIL-but-done spec 011" $?

printf '%s\n' "$out" | grep -q 'verdict=FAIL'
check "mismatch line reports verdict=FAIL" $?

# The PASS spec 022 must NOT be a mismatch.
printf '%s\n' "$out" | grep -q 'TRACE-MISMATCH: spec 022' && r=1 || r=0
[ "$r" -eq 0 ]; check "no TRACE-MISMATCH for the PASS spec 022" $?

# --check must exit 1 when a mismatch exists.
run --check >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ]; check "--check exits 1 when a mismatch exists" $?

# --- Clean case: no mismatch (only a PASS spec with done tasks) → --check exit 0
cat > "$tmp/SHIPPED2.md" <<'MD'
<!-- BEGIN:shipped-registry (generated) -->

| Spec | Verdict | AC proven | Shipped (evidence) | Commit | PR / merge |
| ---- | ------- | --------- | ------------------ | ------ | ---------- |
| 022 | PASS | 18/18 | 2026-06-14 (verify/y) | 5ab984753 | #13 |

<!-- END:shipped-registry -->
MD
TRACE_SHIPPED="$tmp/SHIPPED2.md" TRACE_TASKS="$tmp/TASKS.md" bash "$GEN" --check >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ]; check "--check exits 0 when no mismatch" $?

echo "trace-mismatch: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
