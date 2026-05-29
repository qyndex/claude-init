#!/usr/bin/env bash
# AC-2: verify.sh prints the active SKIP_* set and appends it to an audit log.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

rm -f .claude/state/allow-skip-gates
out=$(SKIP_COVERAGE=1 SKIP_STORY_MAP=1 SKIP_INTEG_COV=1 SKIP_TDD_LEDGER=1 \
      bash .claude/scripts/verify.sh 2>&1 || true)

# Output must name the requested SKIP vars.
echo "$out" | grep -q 'SKIP_COVERAGE' || { echo "FAIL: SKIP set not printed"; exit 1; }
echo "$out" | grep -qiE 'IGNORED|HONORED' || { echo "FAIL: honored/ignored status not printed"; exit 1; }

# Audit log must have been appended.
test -f verify/.skip-log || { echo "FAIL: verify/.skip-log not written"; exit 1; }
grep -q 'verify-skip-request' verify/.skip-log || { echo "FAIL: skip-log missing entry"; exit 1; }

echo "PASS: AC-2 SKIP_* set printed + logged"
exit 0
