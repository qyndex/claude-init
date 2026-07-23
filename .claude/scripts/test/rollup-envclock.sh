#!/usr/bin/env bash
# M-18 — deterministic rollup trigger. `memory-rollup.sh weekly <YYYY-Www>` (or the
# ROLLUP_NOW epoch env) must actually target that week — the arg was silently
# ignored (cmd_weekly hardcoded `date +%G-W%V`). Plus a `backfill <start> <end>`
# that emits every week in the range. Env-clock, so it's rig-testable without
# waiting real weeks (O-7: the "backfill W25-W30" claim needs a threaded clock).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/.claude/memory/rollups" "$tmp/tasks" \
         "$tmp/initiatives/active" "$tmp/.claude/state/locks"
cp .claude/scripts/memory-rollup.sh "$tmp/.claude/scripts/"
cp .claude/scripts/lib/with-lock.sh "$tmp/.claude/scripts/lib/"
: > "$tmp/tasks/TASKS.md"
git -C "$tmp" init -q 2>/dev/null || true

# (1) A target-week ARG is honored: `weekly 2026-W25` writes 2026-W25.md, not the
#     current wall-clock week.
( cd "$tmp" && bash .claude/scripts/memory-rollup.sh weekly 2026-W25 >/dev/null 2>&1 )
[ -f "$tmp/.claude/memory/rollups/2026-W25.md" ]
check "weekly <arg> writes the ARG week's file (2026-W25.md)" $?
# And the file's own heading names that week (not today's).
grep -q '2026-W25' "$tmp/.claude/memory/rollups/2026-W25.md" 2>/dev/null
check "the rollup body names the target week 2026-W25" $?

# (2) Wall-clock week must NOT have been written when an arg was given.
thisweek=$(date +%G-W%V)
if [ "$thisweek" != "2026-W25" ]; then
  [ ! -f "$tmp/.claude/memory/rollups/${thisweek}.md" ]
  check "no wall-clock-week file written when an explicit week arg is given" $?
else
  check "no wall-clock-week file written when an explicit week arg is given (skipped — this IS W25)" 0
fi

# (3) backfill <start> <end> emits every week in the inclusive range.
( cd "$tmp" && bash .claude/scripts/memory-rollup.sh backfill 2026-W27 2026-W30 >/dev/null 2>&1 )
missing=0
for w in 2026-W27 2026-W28 2026-W29 2026-W30; do
  [ -f "$tmp/.claude/memory/rollups/${w}.md" ] || { echo "    missing $w"; missing=$((missing+1)); }
done
[ "$missing" -eq 0 ]
check "backfill 2026-W27..2026-W30 emits all 4 week files" $?

# (4) Idempotence: re-running the same weekly is byte-stable modulo the generated-at
#     line (which uses wall-clock). Assert the WEEK heading is stable.
h1=$(grep -m1 '^# Rollup' "$tmp/.claude/memory/rollups/2026-W25.md")
( cd "$tmp" && bash .claude/scripts/memory-rollup.sh weekly 2026-W25 >/dev/null 2>&1 )
h2=$(grep -m1 '^# Rollup' "$tmp/.claude/memory/rollups/2026-W25.md")
[ "$h1" = "$h2" ]
check "re-running weekly <same-arg> keeps the week heading stable" $?

# (5) No orphan lock.
[ ! -d "$tmp/.claude/state/locks/memory-plane.lock" ]
check "memory-plane lock released after rollup" $?

# (6) The CI workflow half (staged patch, guarded .github/workflows/*) must open a
#     PR, NOT push to main directly (O-7: cross-machine race can't use the local
#     mkdir-lock; git merge is the serialization point).
WF_PATCH="$ROOT/.claude/memory.proposed/patches/M-18-weekly-rollup-workflow.patch"
if [ -f "$WF_PATCH" ]; then
  grep -qE '^\+.*(git checkout -b|gh pr create)' "$WF_PATCH"
  check "M-18 CI workflow patch uses the PR-branch pattern" $?
  ! grep -qE '^\+.*git push.*origin main' "$WF_PATCH"
  check "M-18 CI workflow patch does NOT push to main directly (cross-machine safe)" $?
else
  check "M-18 CI workflow patch present" 1
fi

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
