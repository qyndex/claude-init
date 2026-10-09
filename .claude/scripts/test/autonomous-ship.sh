#!/usr/bin/env bash
# Request-only local boundary; no fake local evidence may grant merge authority.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'FAKE'
#!/bin/bash
if [ "$1 $2" = 'repo view' ]; then echo qyndex/claude-init; exit 0; fi
printf '%s\n' "$*" >> "$CALLS"
[ "$1 $2" = 'workflow run' ] && [ "${API_FAIL:-0}" = 0 ]
FAKE
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" CALLS="$tmp/calls"
pass=0
bash "$ROOT/.claude/scripts/autonomous-ship.sh" 42 >/dev/null
[ "$(cat "$CALLS")" = 'workflow run factory-merge.yml --repo qyndex/claude-init -f pr=42 -f mode=merge' ]; pass=$((pass+1))
: > "$CALLS"
bash "$ROOT/.claude/scripts/autonomous-ship.sh" 42 --dry-run >/dev/null
[ ! -s "$CALLS" ]; pass=$((pass+1))
for arg in invalid 0; do
 if bash "$ROOT/.claude/scripts/autonomous-ship.sh" "$arg" >/dev/null 2>&1; then exit 1; fi; pass=$((pass+1))
done
if API_FAIL=1 bash "$ROOT/.claude/scripts/autonomous-ship.sh" 42 >/dev/null 2>&1; then exit 1; fi; pass=$((pass+1))
! grep -qE 'gh pr merge|SKIP_RULESET' "$ROOT/.claude/scripts/autonomous-ship.sh"; pass=$((pass+1))
for workflow in auto-merge.yml auto-merge-dependabot.yml release-please.yml; do
 ! grep -qE 'gh pr merge' "$ROOT/.github/workflows/$workflow"; pass=$((pass+1))
done
! grep -qE 'git revert|git push origin main' "$ROOT/.claude/scripts/verified-merge.sh"; pass=$((pass+1))
printf 'passed: %s; failed: 0\n' "$pass"
