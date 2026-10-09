#!/usr/bin/env bash
# Spec 006 AC-2/AC-4: tool errors and unknown consumed contracts cannot pass.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts" "$tmp/.swarms/streams/fixture" "$tmp/bin"
cp "$ROOT/.claude/scripts/local-pr-check.sh" "$tmp/.claude/scripts/"
export PATH="$tmp/bin:$PATH"
pass=0; fail=0
for tool in semgrep gitleaks commitlint codeql licensee cyclonedx-bom lighthouse perf-budget; do
  printf '#!/bin/bash\nexit 42\n' > "$tmp/bin/$tool"; chmod +x "$tmp/bin/$tool"
done
for check in semgrep gitleaks commitlint codeql license sbom lighthouse perf-budget; do
  if bash "$tmp/.claude/scripts/local-pr-check.sh" "--only=$check" >"$tmp/log" 2>&1; then echo "FAIL: $check passed failing/missing invocation"; fail=$((fail+1)); else pass=$((pass+1)); fi
done
printf '## Contracts consumed\n- unsupported:required-proof\n' > "$tmp/.swarms/streams/fixture/analysis.md"
if (cd "$tmp" && bash "$ROOT/.claude/scripts/contract-tests.sh" fixture) >"$tmp/log" 2>&1; then echo 'FAIL: unknown contract passed'; fail=$((fail+1)); else pass=$((pass+1)); fi
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/semgrep"
if bash "$tmp/.claude/scripts/local-pr-check.sh" --only=semgrep >"$tmp/log" 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); fi
for selection in semgrepp ""; do
  if bash "$tmp/.claude/scripts/local-pr-check.sh" "--only=$selection" >"$tmp/log" 2>&1; then echo "FAIL: invalid selection passed"; fail=$((fail+1)); else pass=$((pass+1)); fi
done
echo "passed: $pass; failed: $fail"; [ "$fail" -eq 0 ]
