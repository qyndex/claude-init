#!/usr/bin/env bash
# M-13-14 (together) — (a) kill the recall noise floor: an UNRELATED path query must
# return ZERO lines, not bonus-only entries; (b) index sh/css/html/toml so a memory
# referencing a `.sh` path can actually carry it.
#
# O-7 correction: assert the output IS EMPTY against a SYNTHETIC index (not the live
# repo's "20 noise lines" magic number, which drifts with repo content).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/.claude/memory/patterns" "$tmp/.claude/state/locks"
cp .claude/scripts/memory-index.sh  "$tmp/.claude/scripts/"
cp .claude/scripts/memory-recall.sh "$tmp/.claude/scripts/"
cp .claude/scripts/lib/with-lock.sh "$tmp/.claude/scripts/lib/"

# A pattern that references a .sh path and a .css path (M-14 extensions) plus an
# established status (so it carries a recency/status BONUS — the noise source).
cat > "$tmp/.claude/memory/patterns/shell-helper.md" <<'EOF'
---
name: shell-helper
description: "a pattern about a shell helper"
status: established
metadata:
  type: pattern
  status: established
---
# shell-helper
Touches `.claude/scripts/deploy.sh` and `src/web/app.css` and `pyproject.toml`.
EOF

( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )

# (M-14) The .sh / .css / .toml paths must be captured in paths_touched.
pt=$(cd "$tmp" && jq -r 'select(.id=="shell-helper") | .paths_touched[]' .claude/memory/index.jsonl 2>/dev/null)
printf '%s' "$pt" | grep -q 'deploy\.sh'
check "index captures a .sh path in paths_touched (was excluded)" $?
printf '%s' "$pt" | grep -q 'app\.css'
check "index captures a .css path in paths_touched" $?
printf '%s' "$pt" | grep -q 'pyproject\.toml'
check "index captures a .toml path in paths_touched" $?

# (M-13) Noise floor: a query for an UNRELATED path must return ZERO lines. The
# established pattern would otherwise surface on its status/recency bonus alone.
out=$(cd "$tmp" && bash .claude/scripts/memory-recall.sh --paths "totally/unrelated/nowhere.rb" 2>/dev/null)
line_count=$(printf '%s' "$out" | grep -c '.' || true)
[ "${line_count:-0}" -eq 0 ]
check "unrelated-path recall returns ZERO lines (noise floor killed, got ${line_count:-0})" $?

# (M-13 positive) A query for the ACTUAL .sh path the pattern touches must return it
# (proves the floor didn't over-correct to silence real matches).
hit=$(cd "$tmp" && bash .claude/scripts/memory-recall.sh --paths ".claude/scripts/deploy.sh" 2>/dev/null)
printf '%s' "$hit" | grep -q 'shell-helper'
check "matching .sh path recall DOES return the entry (floor didn't oversilence)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
