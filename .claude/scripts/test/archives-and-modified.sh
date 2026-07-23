#!/usr/bin/env bash
# M-17 — (a) reachable archives via `--include-archived`; (b) `modified:` stamp.
#
# (a) Archived memories live under .claude/memory/.archive/. A normal rebuild
#     excludes them (default). `rebuild --include-archived` walks them too and
#     marks each with archived:true so recall can distinguish them.
# (b) build_entry records fs mtime, which `touch` mutates. Add a `modified:`
#     field derived from frontmatter modified:/last_verified: when present, else
#     fall back to the numeric mtime — so recency reflects real content edits.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/.claude/memory/patterns" \
         "$tmp/.claude/memory/.archive/patterns" "$tmp/.claude/state/locks"
cp .claude/scripts/memory-index.sh "$tmp/.claude/scripts/"
cp .claude/scripts/lib/with-lock.sh "$tmp/.claude/scripts/lib/"

# A live pattern with an explicit frontmatter modified: date.
cat > "$tmp/.claude/memory/patterns/dated.md" <<'EOF'
---
name: dated
description: "a pattern with a modified stamp"
status: established
modified: 2026-07-20
---
# dated
Body.
EOF

# A live pattern with NO modified/last_verified — must fall back to mtime.
cat > "$tmp/.claude/memory/patterns/undated.md" <<'EOF'
---
name: undated
description: "a pattern without a modified stamp"
status: established
---
# undated
Body.
EOF

# An ARCHIVED pattern — must be absent from a normal rebuild, present with
# archived:true after --include-archived.
cat > "$tmp/.claude/memory/.archive/patterns/oldghost.md" <<'EOF'
---
name: oldghost
description: "an archived pattern"
status: established
---
# oldghost
Body.
EOF

# (a) Normal rebuild: archive excluded.
( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )
ghost=$(cd "$tmp" && jq -r 'select(.id=="oldghost") | .id' .claude/memory/index.jsonl 2>/dev/null)
[ -z "$ghost" ]
check "normal rebuild EXCLUDES archived entries (got '${ghost}')" $?

# (b) modified: stamp from frontmatter.
mod=$(cd "$tmp" && jq -r 'select(.id=="dated") | .modified' .claude/memory/index.jsonl 2>/dev/null)
[ "$mod" = "2026-07-20" ]
check "entry with frontmatter modified: carries that value (got '${mod}')" $?

# (b) fallback: undated entry's modified is a numeric mtime.
umod=$(cd "$tmp" && jq -r 'select(.id=="undated") | .modified' .claude/memory/index.jsonl 2>/dev/null)
printf '%s' "$umod" | grep -qE '^[0-9]+$'
check "entry without frontmatter modified: falls back to numeric mtime (got '${umod}')" $?

# (a) --include-archived: archive now present and marked.
( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild --include-archived >/dev/null 2>&1 )
ghost2=$(cd "$tmp" && jq -r 'select(.id=="oldghost") | .id' .claude/memory/index.jsonl 2>/dev/null)
[ "$ghost2" = "oldghost" ]
check "rebuild --include-archived INCLUDES the archived entry" $?
arch=$(cd "$tmp" && jq -r 'select(.id=="oldghost") | .archived' .claude/memory/index.jsonl 2>/dev/null)
[ "$arch" = "true" ]
check "archived entry is marked archived:true (got '${arch}')" $?
# Live entries stay archived:false under --include-archived (not blanket-marked).
liva=$(cd "$tmp" && jq -r 'select(.id=="dated") | .archived' .claude/memory/index.jsonl 2>/dev/null)
[ "$liva" = "false" ]
check "live entry stays archived:false under --include-archived (got '${liva}')" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
