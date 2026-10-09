#!/usr/bin/env bash
# Spec 006 AC-3: invalid emission and a failed runner cannot publish PASS.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/specs/active" "$tmp/bin"
cp "$ROOT/.claude/scripts/collect-evidence.sh" "$ROOT/.claude/scripts/spec-match.sh" "$tmp/.claude/scripts/"
cp "$ROOT/.claude/scripts/lib/atomic-write.sh" "$tmp/.claude/scripts/lib/"
printf '#!/bin/bash\nexit 0\n' > "$tmp/.claude/scripts/verify.sh"
printf '#!/bin/bash\nexit 42\n' > "$tmp/bin/npx"; chmod +x "$tmp/bin/npx"; export PATH="$tmp/bin:$PATH"
pass=0; fail=0
bundle="$tmp/verify/$(date +%Y-%m-%d)-900-fixture"
mkdir -p "$bundle"
printf '# Fixture\n## Acceptance criteria\nNo IDs.\n## Notes\n' > "$tmp/specs/active/900-fixture.md"
if bash "$tmp/.claude/scripts/collect-evidence.sh" 900 --check-only >"$tmp/log" 2>&1; then echo 'FAIL: zero-AC evidence passed'; fail=$((fail+1)); else pass=$((pass+1)); fi
printf '# Fixture\n## Acceptance criteria\n- AC-1: fixture behavior\n## Notes\n' > "$tmp/specs/active/900-fixture.md"
printf '{"testResults":[{"assertionResults":[{"title":"AC-1 behavior","status":"passed"}]}]}\n' > "$bundle/results.json"
if bash "$tmp/.claude/scripts/collect-evidence.sh" 900 --check-only >"$tmp/log" 2>&1 && jq -e '.verdict=="PASS" and .ac_total==1' "$bundle/evidence.json" >/dev/null; then pass=$((pass+1)); else cat "$tmp/log"; fail=$((fail+1)); fi
printf '{"devDependencies":{"jest":"fixture"}}\n' > "$tmp/package.json"
if bash "$tmp/.claude/scripts/collect-evidence.sh" 900 >"$tmp/log" 2>&1; then echo 'FAIL: failed runner reused old results'; fail=$((fail+1)); else pass=$((pass+1)); fi
# A valid JSON prefix followed by garbage must not leak passing tags.
printf '{"testResults":[{"assertionResults":[{"title":"AC-1 behavior","status":"passed"}]}]} trailing-garbage' > "$bundle/results.json"
if bash "$tmp/.claude/scripts/collect-evidence.sh" 900 --check-only >"$tmp/log" 2>&1; then echo 'FAIL: malformed trailing data passed'; fail=$((fail+1)); else pass=$((pass+1)); fi
# Invalid prepared results must also fail in check-only mode.
printf 'not JSON\n' > "$bundle/results.json"
if bash "$tmp/.claude/scripts/collect-evidence.sh" 900 --check-only >"$tmp/log" 2>&1; then echo 'FAIL: invalid prepared evidence passed'; fail=$((fail+1)); else pass=$((pass+1)); fi
echo "passed: $pass; failed: $fail"; [ "$fail" -eq 0 ]
