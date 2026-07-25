#!/usr/bin/env bash
# T-P3 (spec-005 AC-3, gap G3) — harvest-decisions.sh turns a merged commit's
# Constraint:/Rejected:/Directive: trailers into a DRAFT ADR (status: proposed,
# OQ-2), deduped so re-running the same commit does not create a second ADR.
# Draft-only: never sets accepted. Tests use a throwaway git repo fixture so no
# real commit/ADR is touched.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SCRIPT="$ROOT/.claude/scripts/harvest-decisions.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
dec="$tmp/decisions"
mkdir -p "$dec"
# minimal ADR template the harvester/adr-new path needs
cp .claude/memory/decisions/0000-template.md "$dec/0000-template.md" 2>/dev/null || {
  printf -- '---\nname: 0000-decision-template\ndescription: ADR template — copy to a new file and fill in.\nstatus: template\ncreated: YYYY-MM-DD\nmetadata:\n  type: decision\n  status: template\n---\n# ADR-0000: <Decision Title>\n## Context\n## Decision\n' > "$dec/0000-template.md"
}

# A commit-ish is fed via a fixture body file (HARVEST_BODY_FILE) so we don't need a
# real git object. The script reads the body, extracts trailers.
cat > "$tmp/body.txt" <<'EOF'
feat(x): do the thing

Some body.

Constraint:    must not add latency to the hot path
Rejected:      inline cache | too fragile under concurrency
Directive:     operator wants autonomous shipping
Confidence:    high
Scope-risk:    localized
EOF

run() { HARVEST_DECISIONS_DIR="$dec" HARVEST_BODY_FILE="$tmp/body.txt" bash "$SCRIPT" "$@"; }

# (1) Harvest creates a draft ADR carrying the trailers.
out=$(run FAKESHA1 2>&1); rc=$?
[ "$rc" -eq 0 ]; check "harvest exits 0 on a trailer-bearing commit" $?
adr=$(ls "$dec"/[0-9]*.md 2>/dev/null | grep -v 0000-template | head -1)
[ -n "$adr" ] && [ -f "$adr" ]; check "creates a new ADR file" $?

# (2) status is proposed (draft-only, OQ-2), NEVER accepted.
grep -qE '^status: proposed' "$adr"; check "ADR status is proposed (draft-only)" $?
! grep -qE '^status: accepted' "$adr"; check "ADR is NOT auto-accepted" $?

# (3) The harvested trailers are present in the ADR body.
grep -q 'must not add latency to the hot path' "$adr"; check "ADR carries the Constraint trailer" $?
grep -q 'operator wants autonomous shipping' "$adr"; check "ADR carries the Directive trailer" $?

# (4) A harvest_hash is stamped (dedupe key).
grep -qE 'harvest_hash:' "$adr"; check "ADR records a harvest_hash for dedupe" $?

# (5) Idempotent — re-running the SAME commit does not create a second ADR.
before=$(ls "$dec"/[0-9]*.md | grep -vc 0000-template)
run FAKESHA1 >/dev/null 2>&1
after=$(ls "$dec"/[0-9]*.md | grep -vc 0000-template)
[ "$before" -eq "$after" ]; check "re-harvesting the same commit does not duplicate (dedupe by hash)" $?

# (6) A commit with NO decision trailers harvests nothing (no noise ADR).
cat > "$tmp/nobody.txt" <<'EOF'
chore: bump dep

Confidence:    high
Scope-risk:    none
EOF
n_before=$(ls "$dec"/[0-9]*.md | grep -vc 0000-template)
HARVEST_DECISIONS_DIR="$dec" HARVEST_BODY_FILE="$tmp/nobody.txt" bash "$SCRIPT" FAKESHA2 >/dev/null 2>&1
n_after=$(ls "$dec"/[0-9]*.md | grep -vc 0000-template)
[ "$n_before" -eq "$n_after" ]; check "commit with no Constraint/Rejected/Directive → no ADR (no noise)" $?

echo "passed: $pass"; echo "failed: $fail"
[ "$fail" -eq 0 ]
