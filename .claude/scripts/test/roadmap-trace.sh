#!/usr/bin/env bash
# T-P5 (spec-005 AC-5a, gap G5a) — validate.sh must flag a roadmap row whose
# `spec:NNN` reference resolves to no specs/{active,archive}/NNN-*.md. OQ-3 chose
# WIRE (not de-scope). Consistent with [spec-plan-trace], a dangling ref is an
# advisory WARN (not a hard fail) so the real tree stays rc=0. This test drives
# validate.sh against a hermetic roadmap fixture via the ROADMAP_FILE env hook.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# (1) The [roadmap-trace] block exists in validate.sh.
grep -qE '\[roadmap-trace\]' .claude/scripts/validate.sh
check "AC-5a: validate.sh has a [roadmap-trace] block" $?

# (2) It is a WARN, not a hard fail (advisory, consistent with [spec-plan-trace]).
#     Extract ONLY the [roadmap-trace] block: from its banner to the NEXT banner.
block=$(awk '/─── \[roadmap-trace\]/{s=1; next} s && /^# ───/{exit} s{print}' .claude/scripts/validate.sh)
printf '%s' "$block" | grep -qE 'warn '
check "AC-5a: dangling roadmap spec ref is a warning (warn)" $?
! printf '%s' "$block" | grep -qE '\bfail \b'
check "AC-5a: dangling roadmap spec ref is NOT a hard fail" $?

# (3) Behavioral: hermetic roadmap fixture with one resolvable spec ref (004, which
#     exists in the real tree) and one dangling ref (777). Assert exactly one dangling
#     warning naming 777, and none for the resolvable 004. Uses ROADMAP_FILE env hook.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/ROADMAP.md" <<'EOF'
# Roadmap
- [ ] Real thing | spec:004 | quarter:2026-Q3 | status: active
- [ ] Ghost thing | spec:777 | quarter:2026-Q4 | status: planned
EOF

out=$(ROADMAP_FILE="$tmp/ROADMAP.md" bash .claude/scripts/validate.sh 2>&1)

dangling=$(printf '%s' "$out" | grep -iE 'roadmap-trace' | grep -E '777' || true)
printf '%s' "$dangling" | grep -q '777'
check "AC-5a: warns on dangling roadmap spec ref 777" $?

resolvable=$(printf '%s' "$out" | grep -iE 'roadmap-trace.*dangl|roadmap-trace.*resolve' | grep -E '\b004\b' || true)
[ -z "$resolvable" ]
check "AC-5a: does NOT warn on resolvable roadmap spec ref 004" $?

# Exactly one dangling warning emitted for this fixture.
count=$(printf '%s\n' "$out" | grep -cE 'roadmap-trace.*dangling' || true)
[ "$count" -eq 1 ]
check "AC-5a: exactly one dangling warning for the fixture" $?

# (4) The roadmap schema is documented (README) and a canonical roadmap file is seeded.
[ -f roadmap/README.md ]
check "AC-5a: roadmap/README.md documents the row schema" $?
grep -qE 'spec:[0-9]' roadmap/ROADMAP.md
check "AC-5a: roadmap/ROADMAP.md seeded with a spec-referencing row" $?

echo "passed: $pass"; echo "failed: $fail"
[ "$fail" -eq 0 ]
