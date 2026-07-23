#!/usr/bin/env bash
# M-07-state — initiative-state.sh sync must: (1) sync ALL active specs, not just
# newest-by-mtime; (2) count [s] shipped tasks; (3) derive phase from ground-truth
# task states, not the stale swarm workflow-state.json; (4) filter "Next unblocked"
# to THIS spec (no cross-spec bleed). Hermetic temp repo.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/.claude/scripts/initiative-state.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts" "$tmp/.claude/state" "$tmp/specs/active" \
         "$tmp/plans/active" "$tmp/initiatives/active" "$tmp/tasks" \
         "$tmp/.swarms/coordinator"
cp "$SCRIPT" "$tmp/.claude/scripts/initiative-state.sh"
git -C "$tmp" init -q 2>/dev/null || true

# Two active specs. Make 007 NEWER so the old "newest only" behavior would skip 003.
: > "$tmp/specs/active/003-alpha.md"
sleep 0.1 2>/dev/null || true
: > "$tmp/specs/active/007-beta.md"

# A stale swarm phase that ground-truth must OVERRIDE.
echo '{"phase":"specifying"}' > "$tmp/.swarms/coordinator/workflow-state.json"

# TASKS: spec 003 fully shipped ([x]+[s]); spec 007 mid-implementation.
cat > "$tmp/tasks/TASKS.md" <<'T'
# TASKS

## Active
- [x] T-300  | spec:003  | phase:1
- [s] T-301  | spec:003  | phase:1
- [s] T-302  | spec:003  | phase:1
- [ ] T-700  | spec:007  | phase:1
- [~] T-701  | spec:007  | phase:1
- [b] T-702  | spec:007  | phase:1
T

( cd "$tmp" && bash .claude/scripts/initiative-state.sh sync >/dev/null 2>&1 )

s003="$tmp/initiatives/active/spec-003-alpha.STATE.md"
s007="$tmp/initiatives/active/spec-007-beta.STATE.md"

# (1) BOTH specs synced (not just newest).
{ [ -f "$s003" ] && [ -f "$s007" ]; }
check "syncs ALL active specs (both 003 and 007 STATE.md exist)" $?

# (2)+(3) spec 003 = all terminal → phase 'shipped', [s] counted in total.
grep -q '\*\*phase\*\*: shipped' "$s003" 2>/dev/null
check "spec-003 phase is ground-truth 'shipped' (overrides stale 'specifying')" $?
grep -qE '\*\*tasks\*\*: 3/3 done' "$s003" 2>/dev/null
check "spec-003 counts [s] shipped tasks (3/3, not 1/3)" $?

# (3) spec 007 has an in-progress task → phase 'implementing'.
grep -q '\*\*phase\*\*: implementing' "$s007" 2>/dev/null
check "spec-007 phase is ground-truth 'implementing'" $?

# (4) spec 007's "Next unblocked" must NOT list spec-003 tasks.
next007=$(sed -n '/## Next unblocked/,/## Last 5/p' "$s007")
! printf '%s' "$next007" | grep -q 'T-300\|T-301\|T-302'
check "spec-007 Next-unblocked excludes spec-003 tasks (no cross-spec bleed)" $?
# And it should list its own pending T-700.
printf '%s' "$next007" | grep -q 'T-700'
check "spec-007 Next-unblocked lists its own pending T-700" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
