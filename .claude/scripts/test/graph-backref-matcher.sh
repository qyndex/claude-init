#!/usr/bin/env bash
# M-20 — graph back_ref matcher. ADR refs are token-form (`ADR-0002`) but ids are
# slug-form (`0002-evidence-...`), so the old `.id == $t or endswith($t)` matcher
# NEVER matched → every ADR ref reported as an asymmetry (the live repo shows 9,
# all false). The fix normalizes ADR-NNNN ↔ NNNN-slug so back_refs populate and
# verify reports 0. Also: an entry must not self-reference (self-edge).
#
# O-7 correction: assert an EXACT count against a SYNTHETIC index that manufactures
# a known number of asymmetries — never the live-repo "9" magic number.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/.claude/memory/decisions" "$tmp/.claude/state/locks"
cp .claude/scripts/memory-index.sh  "$tmp/.claude/scripts/"
cp .claude/scripts/lib/with-lock.sh "$tmp/.claude/scripts/lib/"

# Two ADRs: 0001 references ADR-0002 (token form). After rebuild, 0002's back_refs
# must include 0001-alpha (id/slug form) — that is the id/token normalization.
cat > "$tmp/.claude/memory/decisions/0001-alpha.md" <<'EOF'
---
name: 0001-alpha
status: accepted
metadata: {type: decision}
---
# ADR-0001
Builds on ADR-0002.
EOF
cat > "$tmp/.claude/memory/decisions/0002-beta.md" <<'EOF'
---
name: 0002-beta
status: accepted
metadata: {type: decision}
---
# ADR-0002
Standalone.
EOF

( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )

# (1) 0002's back_refs now include 0001-alpha (the normalized match populated the edge).
back=$(cd "$tmp" && jq -r 'select(.id=="0002-beta") | .back_refs[]' .claude/memory/index.jsonl 2>/dev/null)
printf '%s' "$back" | grep -q '0001-alpha'
check "ADR-NNNN ref populates the target slug-id's back_refs (id normalization)" $?

# (2) verify reports ZERO asymmetries on this consistent fixture.
out=$(cd "$tmp" && bash .claude/scripts/memory-index.sh verify 2>&1)
echo "$out" | grep -qE 'verify: 0 asymmetries'
check "verify reports 0 asymmetries (was 9 false ones from the id/token mismatch)" $?

# (3) NEGATIVE / self-ref: an ADR that references ITSELF must not create a self-edge.
cat > "$tmp/.claude/memory/decisions/0003-selfie.md" <<'EOF'
---
name: 0003-selfie
status: accepted
metadata: {type: decision}
---
# ADR-0003
This is ADR-0003, referencing ADR-0003 itself.
EOF
( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )
selfback=$(cd "$tmp" && jq -r 'select(.id=="0003-selfie") | .back_refs[]?' .claude/memory/index.jsonl 2>/dev/null)
! printf '%s' "$selfback" | grep -q '0003-selfie'
check "self-referencing ADR does NOT get a self-edge back_ref" $?

# (4) Manufactured asymmetry: an ADR referencing a NON-EXISTENT target must still be
#     reported (exact count = 1), proving verify isn't just always-0 now.
cat > "$tmp/.claude/memory/decisions/0004-dangling.md" <<'EOF'
---
name: 0004-dangling
status: accepted
metadata: {type: decision}
---
# ADR-0004
References ADR-9999 which does not exist.
EOF
( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )
count=$(cd "$tmp" && bash .claude/scripts/memory-index.sh verify 2>&1 | grep -oE 'verify: [0-9]+' | grep -oE '[0-9]+')
[ "${count:-99}" -eq 1 ]
check "verify reports exactly 1 asymmetry for the one dangling ref (got ${count:-?})" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
