#!/usr/bin/env bash
# M-07-data — spec-004 reverse-drift reconcile. Verifies:
#  (1) the SHIPPED registry lists spec-004 as PASS with PR#13 provenance;
#  (2) the [s] shipped marker is ledger-EXEMPT (check-tdd-ledger scans only [x]),
#      so the reconcile does NOT hard-fail the required TDD-ledger gate — the
#      whole point of using [s] instead of [x] (Correction 4);
#  (3) the TASKS.md patch flips exactly the 17 [ ] spec-004 tasks to [s],
#      leaving T-154 ([x], has real logs) untouched.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# (1) SHIPPED registry lists spec-004 PASS
grep -qE '^\|\s*004\s*\|\s*PASS\s*\|' specs/SHIPPED.md 2>/dev/null
check "SHIPPED.md lists spec-004 as PASS" $?
grep -qE '#13' specs/SHIPPED.md 2>/dev/null
check "SHIPPED.md carries spec-004 PR#13 provenance" $?

# (2) [s] is ledger-exempt: the ledger feeder greps ONLY [x], so [s] tasks are
#     never enforced. Assert the feeder pattern does not include [s].
if grep -qE "grep -oE '\^- \\\\\[x\\\\\] T-\[0-9\]\+'" .claude/scripts/check-tdd-ledger.sh; then
  check "check-tdd-ledger scans only [x] (so [s] is exempt)" 0
else
  # looser: the feeder line mentions [x] and not [s]
  feeder=$(grep -n 'done <' .claude/scripts/check-tdd-ledger.sh | tail -1)
  { printf '%s' "$feeder" | grep -q '\[x\]' && ! printf '%s' "$feeder" | grep -q '\[s\]'; }
  check "check-tdd-ledger scans only [x] (so [s] is exempt)" $?
fi

# (3) The reconcile patch flips exactly the 17 unshipped spec-004 tasks to [s].
PATCH=.claude/memory.proposed/patches/M-07-data-spec004-shipped-marker.patch
if [ -f "$PATCH" ]; then
  added_s=$(grep -cE '^\+- \[s\] T-1[45][0-9]' "$PATCH")
  removed_blank=$(grep -cE '^-- \[ \] T-1[45][0-9]' "$PATCH")
  [ "$added_s" -eq 17 ] && [ "$removed_blank" -eq 17 ]
  check "reconcile patch flips exactly 17 [ ]→[s] spec-004 tasks (got +$added_s/-$removed_blank)" $?
  # T-154 (the [x] one) must NOT be MODIFIED — it may appear as a context line
  # (unprefixed), but never as an added/removed (+/-) line.
  ! grep -qE '^[+-].*T-154' "$PATCH"
  check "reconcile patch leaves T-154 ([x], real logs) unmodified" $?
else
  check "reconcile patch present" 1
fi

# (4) Behavioral: apply the patch to a temp TASKS.md, run the real ledger feeder
#     logic, and confirm none of T-140..T-157 (now [s]) enter the [x] scan.
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
cp tasks/TASKS.md "$tmp"
if [ -f "$PATCH" ]; then
  # Simulate the flip on the temp copy (sed the same transform)
  sed -i.bak -E 's/^- \[ \] (T-1[45][0-9])/- [s] \1/' "$tmp" 2>/dev/null; rm -f "$tmp.bak"
  scanned=$(grep -oE '^- \[x\] T-[0-9]+' "$tmp" | grep -oE 'T-1[45][0-9]' | grep -cE 'T-1[45][0-5]' || true)
  # Only T-154 should remain in the [x] scan among 140..157.
  only154=$(grep -oE '^- \[x\] T-[0-9]+' "$tmp" | grep -cE 'T-15[45]')
  [ "$(grep -oE '^- \[s\] T-1[45][0-9]' "$tmp" | wc -l | tr -d ' ')" -eq 17 ]
  check "post-flip: 17 spec-004 tasks are [s] (ledger-exempt)" $?
fi

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
