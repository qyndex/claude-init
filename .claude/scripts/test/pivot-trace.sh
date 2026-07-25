#!/usr/bin/env bash
# T-P6 (spec-005 AC-5b, gap G5b) — validate.sh must flag a pivot manifest whose
# frontmatter `target:` resolves to no spec or initiative. OQ-3 chose WIRE. Advisory
# WARN (not a hard fail), consistent with [spec-plan-trace]/[roadmap-trace], so the
# real tree stays rc=0. Also asserts the /pivot skill is delivered as a clean-applying
# staged patch (guarded dir → operator applies). Uses the PIVOT_DIR env hook.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# (1) The [pivot-trace] block exists in validate.sh.
grep -qE '\[pivot-trace\]' .claude/scripts/validate.sh
check "AC-5b: validate.sh has a [pivot-trace] block" $?

# (2) It is a WARN, not a hard fail. Extract ONLY the [pivot-trace] block.
block=$(awk '/─── \[pivot-trace\]/{s=1; next} s && /^# ───/{exit} s{print}' .claude/scripts/validate.sh)
printf '%s' "$block" | grep -qE 'warn '
check "AC-5b: dangling pivot target is a warning (warn)" $?
! printf '%s' "$block" | grep -qE '\bfail \b'
check "AC-5b: dangling pivot target is NOT a hard fail" $?

# (3) The pivots/active/ directory exists (with a .gitkeep).
[ -d pivots/active ]
check "AC-5b: pivots/active/ directory exists" $?

# (4) The /pivot skill is delivered as a clean-applying staged patch (guarded dir).
patch=.claude/memory.proposed/patches/SPEC005-02-pivot-skill.patch
[ -f "$patch" ]
check "AC-5b: SPEC005-02 pivot-skill patch exists" $?
git apply --check "$patch" 2>/dev/null
check "AC-5b: SPEC005-02 patch applies clean (git apply --check)" $?
grep -qE '\+\+\+ b/\.claude/skills/pivot/SKILL\.md' "$patch"
check "AC-5b: patch targets .claude/skills/pivot/SKILL.md" $?

# (5) Behavioral: hermetic pivots dir with one resolvable target (spec 004, which
#     exists in the real tree) and one dangling target (spec 888). Assert exactly one
#     dangling warning naming 888, and none for the resolvable 004. Uses PIVOT_DIR.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/active"
cat > "$tmp/active/resolvable.md" <<'EOF'
---
id: PIV-900
verb: supersede
target: 004
target_kind: specs
---
# Pivot PIV-900
EOF
cat > "$tmp/active/dangling.md" <<'EOF'
---
id: PIV-901
verb: drop
target: 888
target_kind: specs
---
# Pivot PIV-901
EOF

out=$(PIVOT_DIR="$tmp" bash .claude/scripts/validate.sh 2>&1)

dangling=$(printf '%s' "$out" | grep -iE 'pivot-trace' | grep -E '888' || true)
printf '%s' "$dangling" | grep -q '888'
check "AC-5b: warns on dangling pivot target 888" $?

resolvable=$(printf '%s' "$out" | grep -iE 'pivot-trace.*dangl' | grep -E '\b004\b' || true)
[ -z "$resolvable" ]
check "AC-5b: does NOT warn on resolvable pivot target 004" $?

count=$(printf '%s\n' "$out" | grep -cE 'pivot-trace.*dangling' || true)
[ "$count" -eq 1 ]
check "AC-5b: exactly one dangling warning for the fixture" $?

echo "passed: $pass"; echo "failed: $fail"
[ "$fail" -eq 0 ]
