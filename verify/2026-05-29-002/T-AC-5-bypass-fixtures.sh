#!/usr/bin/env bash
# AC-5 (BUG-5) — pre-bash-guard.sh must deny shell-redirect / tee / find-exec /
# xargs evasions that target constitution-class files. Eight bypass attempts;
# every one must exit 2 (deny). The destructive strings live in this file (not
# the test runner's argv) so the live guard does not block the runner itself.
#
# Tagged: AC-5
set -uo pipefail
cd "$(dirname "$0")/../.."

GUARD=.claude/hooks/pre-bash-guard.sh
fails=0

# Each fixture: a command string that an injected agent might use to mutate a
# protected file. assert_denied feeds it as a tool_input.command payload and
# requires exit 2.
assert_denied() {
  local label="$1" cmd="$2"
  local payload
  payload=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)")
  printf '%s' "$payload" | bash "$GUARD" >/dev/null 2>&1
  local ec=$?
  if [ "$ec" -eq 2 ]; then
    echo "  PASS [BYPASS-$label] denied (exit 2): $cmd"
  else
    echo "  FAIL [BYPASS-$label] NOT denied (exit $ec): $cmd"
    fails=$((fails + 1))
  fi
}

echo "AC-5 bypass-attempt fixtures (8 cases — all must be denied):"
assert_denied 1 'tee .claude/hooks/evil.sh <<< "x"'
assert_denied 2 'tee -a .claude/CLAUDE.md < /tmp/payload'
assert_denied 3 'find . -name "*.sh" -exec sh -c "echo pwned" {} \;'
assert_denied 4 'cat /tmp/x | xargs bash'
assert_denied 5 'echo pwned > .claude/hooks/pre-bash-guard.sh'
assert_denied 6 'echo pwned >> .claude/CLAUDE.md'
assert_denied 7 'printf x > .claude/settings.json'
assert_denied 8 'echo ci > .github/workflows/evil.yml'

if [ "$fails" -ne 0 ]; then
  echo "AC-5 FAILED: $fails of 8 bypass attempts were NOT denied."
  exit 1
fi
echo "AC-5 PASSED: all 8 bypass attempts denied."
exit 0
