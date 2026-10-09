#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts" "$tmp/bin" "$tmp/coverage"
cp "${VERIFY_UNDER_TEST:-$ROOT/.claude/scripts/verify.sh}" "$tmp/.claude/scripts/"
printf '#!/bin/bash\necho '\''{"stacks":["typescript"],"workspace":"none"}'\''\n' > "$tmp/.claude/scripts/detect-stacks.sh"
printf '{"scripts":{"test":"true","coverage":"true"}}\n' > "$tmp/package.json"
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/npm"; chmod +x "$tmp/bin/npm"
pass=0
for value in null '"bad"' -1 101 89.9; do
 printf '{"total":{"lines":{"pct":%s},"branches":{"pct":100}}}\n' "$value" > "$tmp/coverage/coverage-summary.json"
 if PATH="$tmp/bin:$PATH" bash "$tmp/.claude/scripts/verify.sh" > "$tmp/output" 2>&1; then cat "$tmp/output"; echo 'FAIL: invalid/insufficient coverage passed'; exit 1; fi
 pass=$((pass+1))
done
printf '{"total":{"lines":{"pct":99.5},"branches":{"pct":99.5}}}\n' > "$tmp/coverage/coverage-summary.json"
PATH="$tmp/bin:$PATH" bash "$tmp/.claude/scripts/verify.sh" > "$tmp/output" 2>&1 || { cat "$tmp/output"; exit 1; }
printf 'passed: %s; failed: 0\n' "$((pass+1))"
