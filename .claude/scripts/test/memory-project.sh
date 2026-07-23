#!/usr/bin/env bash
# M-12 — MEMORY.md Decisions/Patterns rows are PROJECTED between delimiter markers
# from the index, single-writer. The hand-written content OUTSIDE the markers must
# be byte-identical after projection (O-7 FALSE-GREEN guard: a naive "decisions now
# appear" test would pass even if the generator clobbered the hand-written header).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/.claude/memory/decisions" \
         "$tmp/.claude/memory/patterns" "$tmp/.claude/state/locks"
cp .claude/scripts/memory-index.sh "$tmp/.claude/scripts/"
cp .claude/scripts/memory-project.sh "$tmp/.claude/scripts/" 2>/dev/null || true
cp .claude/scripts/lib/with-lock.sh "$tmp/.claude/scripts/lib/"

# Two decision ADRs + one pattern in the index.
cat > "$tmp/.claude/memory/decisions/0001-alpha.md" <<'EOF'
---
name: 0001-alpha
description: "ADR-0001: alpha decision"
status: accepted
metadata: {type: decision, status: accepted}
---
# ADR-0001
EOF
cat > "$tmp/.claude/memory/decisions/0002-beta.md" <<'EOF'
---
name: 0002-beta
description: "ADR-0002: beta decision"
status: superseded
superseded_by: ADR-0001
metadata: {type: decision, status: superseded}
---
# ADR-0002
EOF
cat > "$tmp/.claude/memory/patterns/gamma.md" <<'EOF'
---
name: gamma
description: "the gamma pattern"
status: established
metadata: {type: pattern, status: established}
---
# gamma
EOF

# MEMORY.md fixture with distinctive hand-written prose OUTSIDE the markers.
cat > "$tmp/.claude/memory/MEMORY.md" <<'EOF'
# Memory index

HAND-WRITTEN-HEADER-SENTINEL — this taxonomy prose must never be clobbered.

## Decisions

<!-- BEGIN:auto-decisions -->
_(none yet)_
<!-- END:auto-decisions -->

## Patterns

<!-- BEGIN:auto-patterns -->
_(none yet)_
<!-- END:auto-patterns -->

## Footer

HAND-WRITTEN-FOOTER-SENTINEL — also must survive.
EOF

# Snapshot the exact bytes OUTSIDE the marker blocks BEFORE projection.
outside_before() {
  awk '/<!-- BEGIN:auto-/{skip=1} !skip{print} /<!-- END:auto-/{skip=0}' "$1"
}
before="$tmp/outside.before"; outside_before "$tmp/.claude/memory/MEMORY.md" > "$before"

( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )
( cd "$tmp" && bash .claude/scripts/memory-project.sh >/dev/null 2>&1 )
rc=$?
check "memory-project.sh exits 0" "$rc"

M="$tmp/.claude/memory/MEMORY.md"

# (1) Decisions projected between the markers.
dblock=$(awk '/<!-- BEGIN:auto-decisions/{f=1;next} /<!-- END:auto-decisions/{f=0} f' "$M")
printf '%s' "$dblock" | grep -q '0001-alpha'
check "decisions block lists ADR 0001-alpha" $?

# (2) Superseded decision excluded (recall-parity: superseded ADRs don't clutter).
! printf '%s' "$dblock" | grep -q '0002-beta'
check "superseded ADR 0002-beta excluded from projection" $?

# (3) Patterns projected between their markers.
pblock=$(awk '/<!-- BEGIN:auto-patterns/{f=1;next} /<!-- END:auto-patterns/{f=0} f' "$M")
printf '%s' "$pblock" | grep -q 'gamma'
check "patterns block lists the gamma pattern" $?

# (4) FALSE-GREEN GUARD: bytes OUTSIDE the markers are byte-identical.
after="$tmp/outside.after"; outside_before "$M" > "$after"
diff -q "$before" "$after" >/dev/null 2>&1
check "content OUTSIDE the markers is byte-identical (no clobber)" $?
grep -q 'HAND-WRITTEN-HEADER-SENTINEL' "$M" && grep -q 'HAND-WRITTEN-FOOTER-SENTINEL' "$M"
check "hand-written header + footer sentinels survive" $?

# (5) Idempotence: a second projection produces the identical file.
cp "$M" "$tmp/M.first"
( cd "$tmp" && bash .claude/scripts/memory-project.sh >/dev/null 2>&1 )
diff -q "$tmp/M.first" "$M" >/dev/null 2>&1
check "projection is idempotent (second run byte-identical)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
