#!/usr/bin/env bash
# M-16 — `--grep <term>` content/trailer recall in memory-recall.sh.
#
# The existing recall path only matches on paths_touched vs the working set. A
# content search complements it: surface a memory entry whose FILE BODY contains
# a distinctive term, even when no code-path intersects the working set. Must
# stay read-only and compose with --paths (union) or stand alone.
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

# A pattern whose BODY carries a distinctive term but references NO working-set path.
cat > "$tmp/.claude/memory/patterns/quokka-note.md" <<'EOF'
---
name: quokka-note
description: "a pattern with a distinctive body term"
status: established
---
# quokka-note
The zephyrantics protocol governs how we retry idempotent writes.
It touches `.claude/scripts/deploy.sh` only.
EOF

( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )

# (1) --grep for a distinctive body term surfaces the entry (no --paths given).
hit=$(cd "$tmp" && bash .claude/scripts/memory-recall.sh --grep zephyrantics 2>/dev/null)
printf '%s' "$hit" | grep -q 'quokka-note'
check "--grep surfaces an entry whose body contains the term" $?

# (2) NEGATIVE: a term in NO file returns ZERO lines (guards against false-green).
miss=$(cd "$tmp" && bash .claude/scripts/memory-recall.sh --grep xyzzy_nowhere_term 2>/dev/null)
line_count=$(printf '%s' "$miss" | grep -c '.' || true)
[ "${line_count:-0}" -eq 0 ]
check "--grep for an absent term returns ZERO lines (got ${line_count:-0})" $?

# (3) COMPOSES with --paths without crashing: union of path-hits and content-hits.
both=$(cd "$tmp" && bash .claude/scripts/memory-recall.sh --paths "totally/unrelated/x.rb" --grep zephyrantics 2>/dev/null)
rc=$?
check "--grep composes with --paths (exits 0)" "$rc"
printf '%s' "$both" | grep -q 'quokka-note'
check "--grep + --paths still surfaces the content-hit entry" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
