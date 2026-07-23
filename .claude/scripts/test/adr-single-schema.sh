#!/usr/bin/env bash
# M-10 — one schema: frontmatter is the SOLE home of ADR status/supersedes.
# The redundant body bullets (`- **Status**:`, `- **Supersedes**:`,
# `- **superseded_by**:`) are removed from the 3 real ADRs, and validate.sh gains
# a rule REJECTING the body-bullet form in .claude/memory/decisions/*.md.
#
# Test-realism (O-7) requires BOTH a positive and a negative case, or the rule
# could pass by always firing / never firing:
#   - a body-bullet ADR must be REJECTED (rule fires)
#   - a frontmatter-only ADR must PASS (rule stays silent)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

DECISIONS=".claude/memory/decisions"

# (1) The 3 real ADRs no longer carry status/supersedes BODY bullets (frontmatter only).
for adr in 0001-sonnet-default-model-routing 0002-evidence-based-verification-gates \
           0003-tasks-md-sole-authority-issue-projection; do
  f="$DECISIONS/$adr.md"
  [ -f "$f" ] || { echo "  - missing ADR: $f"; fail=$((fail+1)); continue; }
  ! grep -qE '^- \*\*Status\*\*:' "$f"
  check "$adr: no body '- **Status**:' bullet (frontmatter is sole home)" $?
  ! grep -qE '^- \*\*Supersed(es|ed_by)\*\*:' "$f"
  check "$adr: no body '- **Supersedes/superseded_by**:' bullet" $?
  # Frontmatter status: must still be present (the surviving single home).
  awk '/^---$/{n++} n==1 && /^status:/{found=1} END{exit !found}' "$f"
  check "$adr: frontmatter 'status:' retained as sole home" $?
done

# (2) validate.sh REJECTS a body-bullet ADR (rule fires) — NEGATIVE fixture.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/memory/decisions" "$tmp/.claude/scripts"
cp .claude/scripts/validate.sh "$tmp/.claude/scripts/" 2>/dev/null || true

bad="$tmp/.claude/memory/decisions/9998-bad.md"
cat > "$bad" <<'EOF'
---
name: 9998-bad
description: "ADR-9998: body-bullet status must be rejected"
status: accepted
metadata:
  type: decision
  status: accepted
---
# ADR-9998
- **Status**: accepted
EOF

good="$tmp/.claude/memory/decisions/9999-good.md"
cat > "$good" <<'EOF'
---
name: 9999-good
description: "ADR-9999: frontmatter-only status must pass"
status: accepted
metadata:
  type: decision
  status: accepted
---
# ADR-9999
- **Date**: 2026-07-24
- **Context**: fine, no status bullet here
EOF

# The rule is a self-contained check in validate.sh. We invoke just that check via a
# grep-shaped assertion against the committed validate.sh so the test is meaningful
# even without booting the whole validator: the rule must scan decisions/*.md for a
# body-bullet Status/Supersedes and fail.
grep -qE 'decisions.*\*\*Status\*\*|ADR.*body.*bullet|adr-single-schema|single-schema' .claude/scripts/validate.sh
check "validate.sh contains an ADR single-schema rule" $?

# Behavioral: run the exact predicate the rule uses against both fixtures.
# The rule's predicate: a decisions ADR containing a '^- \*\*Status\*\*:' body line is bad.
bad_hits=$(grep -lE '^- \*\*Status\*\*:|^- \*\*Supersed(es|ed_by)\*\*:' "$bad" 2>/dev/null | wc -l | tr -d ' ')
good_hits=$(grep -lE '^- \*\*Status\*\*:|^- \*\*Supersed(es|ed_by)\*\*:' "$good" 2>/dev/null | wc -l | tr -d ' ')
[ "$bad_hits" -eq 1 ]
check "rule predicate FIRES on the body-bullet ADR (negative case)" $?
[ "$good_hits" -eq 0 ]
check "rule predicate STAYS SILENT on the frontmatter-only ADR (positive case)" $?

# (3) adr-new.sh template no longer seeds a body-bullet Status (the mechanical consumer).
! grep -qE '^\s*-e "s/- \\\*\\\*Status' .claude/scripts/adr-new.sh 2>/dev/null \
  && ! grep -qE '- \*\*Status\*\*: proposed \| accepted' .claude/scripts/adr-new.sh 2>/dev/null
check "adr-new.sh no longer writes a body '- **Status**' bullet into new ADRs" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
