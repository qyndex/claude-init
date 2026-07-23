#!/usr/bin/env bash
# M-06 — network-boundary sync must be wired into BOTH the /ship and /verify
# skills, so STATE.md is refreshed at every boundary (not only session-end).
# Ship must also COMMIT the STATE pre-merge (so it rides the PR branch), and the
# call must be grep-gated (a no-op when initiative-state.sh is absent).
#
# /ship + /verify SKILL.md are GUARDED skills → the fix ships as staged patches
# (M-06-*.patch). This test applies them onto temp copies of the real skills so
# it is green whether or not the operator has installed them yet.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PATCHDIR="$ROOT/.claude/memory.proposed/patches"
V_PATCH="$PATCHDIR/M-06-verify-skill-sync.patch"
S_PATCH="$PATCHDIR/M-06-ship-skill-sync.patch"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/skills/verify" "$tmp/.claude/skills/ship"
cp "$ROOT/.claude/skills/verify/SKILL.md" "$tmp/.claude/skills/verify/"
cp "$ROOT/.claude/skills/ship/SKILL.md"   "$tmp/.claude/skills/ship/"

for p in "$V_PATCH" "$S_PATCH"; do
  [ -f "$p" ] || { echo "  - missing patch: $p"; fail=$((fail+1)); }
done
( cd "$tmp" && git apply "$V_PATCH" "$S_PATCH" ) 2>/dev/null
applied=$?
check "M-06 patches apply onto the guarded skills" "$applied"
[ "$applied" -ne 0 ] && { echo "passed: $pass"; echo "failed: $fail"; exit 1; }

V="$tmp/.claude/skills/verify/SKILL.md"
S="$tmp/.claude/skills/ship/SKILL.md"

# (1) Both skills call the sync.
grep -q 'initiative-state.sh sync' "$V"
check "/verify calls initiative-state.sh sync" $?
grep -q 'initiative-state.sh sync' "$S"
check "/ship calls initiative-state.sh sync" $?

# (2) The call is grep-gated in both (no-op when the script is absent).
grep -q "grep -ql 'initiative-state.sh sync'" "$V"
check "/verify sync is grep-gated (no-op when script absent)" $?
grep -q "grep -ql 'initiative-state.sh sync'" "$S"
check "/ship sync is grep-gated (no-op when script absent)" $?

# (3) Ship commits STATE pre-merge — the sync+commit must precede the push step.
sync_line=$(grep -n 'initiative-state.sh sync' "$S" | head -1 | cut -d: -f1)
push_line=$(grep -n 'git push -u origin' "$S" | head -1 | cut -d: -f1)
{ [ -n "$sync_line" ] && [ -n "$push_line" ] && [ "$sync_line" -lt "$push_line" ]; }
check "/ship syncs BEFORE the push (STATE rides the PR branch)" $?
grep -q 'git commit -m "chore(state): sync living STATE.md pre-merge' "$S"
check "/ship commits the synced STATE pre-merge" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
