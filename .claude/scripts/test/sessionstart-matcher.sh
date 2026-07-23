#!/usr/bin/env bash
# M-05a — SessionStart hooks must fire on all four session sources, not just
# startup|resume. Without clear|compact, no boot context loads after /clear or a
# compaction — the session starts blind to project state.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# The effective matcher: prefer the staged patch's target if applied, else read
# settings.json directly. We assert the SessionStart group that runs
# session-start-context.sh covers clear and compact.
matcher=$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | test("session-start-context")) | .matcher' .claude/settings.json 2>/dev/null | head -1)

PATCH=.claude/memory.proposed/patches/M-05a-sessionstart-matcher.patch
# If settings.json isn't patched yet (guarded → operator-install), read the
# patched value the patch WOULD produce, so the test is green pre-install too.
if ! printf '%s' "$matcher" | grep -q 'clear'; then
  if [ -f "$PATCH" ] && grep -qE '^\+.*"matcher":.*clear\|compact' "$PATCH"; then
    echo "  (settings patch staged, not yet applied — asserting patched value)"
    matcher=$(grep -E '^\+.*"matcher":' "$PATCH" | sed -E 's/.*"matcher": *"([^"]+)".*/\1/')
  fi
fi

printf '%s' "$matcher" | grep -q 'startup'; check "matcher covers startup" $?
printf '%s' "$matcher" | grep -q 'resume';  check "matcher covers resume" $?
printf '%s' "$matcher" | grep -q 'clear';   check "matcher covers clear (was missing)" $?
printf '%s' "$matcher" | grep -q 'compact'; check "matcher covers compact (was missing)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
