#!/usr/bin/env bash
# Spec 006 AC-6: empty applicability is explicit; malformed scan data blocks.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/stale-deps" "$tmp/artifacts" "$tmp/bin"
cp "$ROOT/.claude/scripts/stale-deps/rollup.sh" "$tmp/.claude/scripts/stale-deps/"
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/gh"; chmod +x "$tmp/bin/gh"; export PATH="$tmp/bin:$PATH"
pass=0; fail=0
if bash "$tmp/.claude/scripts/stale-deps/rollup.sh" "$tmp/artifacts" >"$tmp/log" 2>&1 && grep -q 'No applicable stack artifacts' "$tmp/.claude/memory/audits/stale-deps-$(date +%Y-%m-%d).md"; then pass=$((pass+1)); else echo 'FAIL: no-artifact outcome missing'; fail=$((fail+1)); fi
mkdir -p "$tmp/artifacts/node" "$tmp/artifacts/python"
printf '{"stack":"node","shipped":2,"mediated":0,"escalated":1}' > "$tmp/artifacts/node/summary.json"
printf '{"stack":"python","shipped":3,"mediated":1,"escalated":0}' > "$tmp/artifacts/python/summary.json"
if bash "$tmp/.claude/scripts/stale-deps/rollup.sh" "$tmp/artifacts" >"$tmp/log" 2>&1 && grep -q 'shipped=5 mediated=1 escalated=1' "$tmp/log"; then pass=$((pass+1)); else echo 'FAIL: multistack aggregation'; fail=$((fail+1)); fi
printf '{"stack":"node","shipped":"broken"}' > "$tmp/artifacts/node/summary.json"
if bash "$tmp/.claude/scripts/stale-deps/rollup.sh" "$tmp/artifacts" >"$tmp/log" 2>&1; then echo 'FAIL: malformed scan result passed'; fail=$((fail+1)); else pass=$((pass+1)); fi
echo "passed: $pass; failed: $fail"; [ "$fail" -eq 0 ]
