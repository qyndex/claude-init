#!/usr/bin/env bash
# T-P1 (spec-005 AC-1, gap G1) — validate.sh must flag an approved/shipped spec that
# has no plan referencing it. OQ-1: warn-first (not a hard fail), so the current tree
# (spec-004 is planless) stays rc=0. This test drives validate.sh against a hermetic
# specs/plans fixture via the env hooks the [spec-plan-trace] block exposes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# (1) The [spec-plan-trace] block exists in validate.sh.
grep -qE '\[spec-plan-trace\]|spec.*plan.*trace|planless' .claude/scripts/validate.sh
check "validate.sh has a spec→plan trace block" $?

# (2) It is a WARN, not a hard fail (OQ-1). Assert the block calls warn(), not fail(),
#     on a missing plan — grep the block region.
# Extract ONLY the [spec-plan-trace] block: from its banner to the NEXT banner.
block=$(awk '/─── \[spec-plan-trace\]/{s=1; next} s && /^# ───/{exit} s{print}' .claude/scripts/validate.sh)
printf '%s' "$block" | grep -qE 'warn '
check "planless spec is a warning (warn), per OQ-1 warn-first" $?
! printf '%s' "$block" | grep -qE '\bfail \b'
check "planless spec is NOT a hard fail" $?

# (3) Behavioral: hermetic fixture. An approved spec with a matching plan → no warning;
#     an approved spec with NO plan → a warning naming it. Uses env hooks
#     SPT_SPECS_DIR / SPT_PLANS_DIR (mirrors validate's other overridable checks).
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/specs/active" "$tmp/plans/active"
# spec 900: approved, HAS a plan
cat > "$tmp/specs/active/900-has-plan.md" <<'EOF'
---
id: 900
status: approved
---
# Spec 900
EOF
cat > "$tmp/plans/active/900-has-plan.md" <<'EOF'
---
id: 900
spec: specs/active/900-has-plan.md
status: approved
---
# Plan 900
EOF
# spec 901: approved, NO plan
cat > "$tmp/specs/active/901-no-plan.md" <<'EOF'
---
id: 901
status: shipped
---
# Spec 901
EOF
# spec 902: draft, no plan — should NOT warn (only approved/shipped are checked)
cat > "$tmp/specs/active/902-draft.md" <<'EOF'
---
id: 902
status: draft
---
# Spec 902
EOF

out=$(SPT_SPECS_DIR="$tmp/specs" SPT_PLANS_DIR="$tmp/plans" \
      bash .claude/scripts/validate.sh 2>&1 | grep -iE 'spec.*901|planless|no plan' )
printf '%s' "$out" | grep -q '901'
check "warns on approved/shipped spec 901 with no plan" $?

nowarn=$(SPT_SPECS_DIR="$tmp/specs" SPT_PLANS_DIR="$tmp/plans" \
      bash .claude/scripts/validate.sh 2>&1 | grep -iE 'planless|no plan' | grep -E '900|902' || true)
[ -z "$nowarn" ]
check "does NOT warn on spec 900 (has plan) or 902 (draft)" $?

echo "passed: $pass"; echo "failed: $fail"
[ "$fail" -eq 0 ]
