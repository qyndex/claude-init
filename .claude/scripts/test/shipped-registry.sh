#!/usr/bin/env bash
# M-08 — the SHIPPED registry generator produces a spec-indexed, latest-wins,
# delimiter-marked registry from evidence bundles. Hermetic: runs the generator
# against a fixture verify/ tree in a temp repo, asserting the shape.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GEN="$ROOT/.claude/scripts/shipped-registry.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

test -f "$GEN" || { echo "generator missing: $GEN"; exit 1; }

# Hermetic fixture repo: two evidence bundles for the SAME spec with different
# generated_at — the newer verdict must win.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts" "$tmp/specs" \
         "$tmp/verify/2026-01-01-004/" "$tmp/verify/2026-06-14-004/"
cp "$GEN" "$tmp/.claude/scripts/shipped-registry.sh"
git -C "$tmp" init -q 2>/dev/null || true

# Older bundle: FAIL verdict.
cat > "$tmp/verify/2026-01-01-004/evidence.json" <<'J'
{"spec":"004","commit":"aaaaaaaaaaaa","generated_at":"2026-01-01T00:00:00+00:00","ac_total":10,"ac_proven":0,"verdict":"FAIL"}
J
# Newer bundle: PASS verdict — must win.
cat > "$tmp/verify/2026-06-14-004/evidence.json" <<'J'
{"spec":"004","commit":"bbbbbbbbbbbb","generated_at":"2026-06-14T00:00:00+00:00","ac_total":10,"ac_proven":10,"verdict":"PASS"}
J

( cd "$tmp" && bash .claude/scripts/shipped-registry.sh >/dev/null 2>&1 )
OUT="$tmp/specs/SHIPPED.md"

test -f "$OUT"; check "generator writes specs/SHIPPED.md" $?

grep -q '<!-- BEGIN:shipped-registry (generated) -->' "$OUT" 2>/dev/null \
  && grep -q '<!-- END:shipped-registry -->' "$OUT" 2>/dev/null
check "registry has BEGIN/END delimiter markers" $?

# Latest-wins: the PASS (newer) row present, the FAIL (older) row absent.
grep -qE '\|\s*004\s*\|\s*PASS\s*\|' "$OUT" 2>/dev/null
check "newest verdict (PASS) wins for spec 004" $?

! grep -qE '\|\s*004\s*\|\s*FAIL\s*\|' "$OUT" 2>/dev/null
check "older verdict (FAIL) is superseded, not listed" $?

# Only ONE row per spec.
n=$(grep -cE '^\|\s*004\s*\|' "$OUT" 2>/dev/null)
[ "$n" -eq 1 ]; check "exactly one row for spec 004 (deduped) — got $n" $?

# --check mode: clean after generate, stale after mutation.
( cd "$tmp" && bash .claude/scripts/shipped-registry.sh --check >/dev/null 2>&1 )
check "--check passes when SHIPPED.md is current" $?

echo "stale" >> "$OUT"
( cd "$tmp" && bash .claude/scripts/shipped-registry.sh --check >/dev/null 2>&1 )
[ "$?" -ne 0 ]; check "--check fails when SHIPPED.md is stale" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
