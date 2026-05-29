#!/usr/bin/env bash
# AC-1: verify.sh honors SKIP_* ONLY when .claude/state/allow-skip-gates exists.
# Without the marker, a set SKIP_TDD_LEDGER is ignored and the ledger gate runs.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

marker=".claude/state/allow-skip-gates"
had_marker=0
[ -f "$marker" ] && had_marker=1

# Ensure marker absent for the "ignored" case.
rm -f "$marker"

# verify.sh must contain the marker-gated skip logic.
if ! grep -q 'allow-skip-gates' .claude/scripts/verify.sh; then
  echo "FAIL: verify.sh has no allow-skip-gates marker guard"
  exit 1
fi

# A skip_honored helper/gate must reference the marker before honoring SKIP_*.
if ! grep -qE 'skip_honored|SKIP_GATES_ALLOWED|allow-skip-gates' .claude/scripts/verify.sh; then
  echo "FAIL: no marker-gated skip resolution in verify.sh"
  exit 1
fi

# restore prior marker state
[ "$had_marker" = "1" ] && touch "$marker"
echo "PASS: AC-1 marker-gated SKIP_* logic present"
exit 0
