#!/usr/bin/env bash
# AC-12: check-model-consistency.sh flags literal opus-4-7 / Opus 4.7 in
# .github/workflows/** and docs/** so a future bump can't strand them.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# The script must contain a stale-version scan over workflows + docs.
grep -q 'opus-4-7' .claude/scripts/check-model-consistency.sh || { echo "FAIL: no stale-version scan in check-model-consistency.sh"; exit 1; }

# Synthetic: a temp workflow pinning opus-4-7 must be flagged.
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.github/workflows"
cp -r .claude "$tmpdir/" 2>/dev/null
printf 'name: t\njobs:\n  x:\n    steps:\n      - with:\n          model: claude-opus-4-7\n' > "$tmpdir/.github/workflows/synthetic.yml"
mkdir -p "$tmpdir/docs"
# Run the stale scan against the synthetic tree.
out=$(cd "$tmpdir" && STALE_SCAN_ONLY=1 bash .claude/scripts/check-model-consistency.sh 2>&1 || true)
rm -rf "$tmpdir"
echo "$out" | grep -qiE 'opus-4-7|stale' || { echo "FAIL: synthetic opus-4-7 workflow not flagged ($out)"; exit 1; }

echo "PASS: AC-12 stale-model scan over workflows/docs present"
exit 0
