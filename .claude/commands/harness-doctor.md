---
description: Diagnose the harness itself. Reports version drift vs upstream, plugin staleness, MCP version pins, hook log size, memory growth, settings.json size. Run monthly or when behavior feels off.
argument-hint: "[--fix]"
allowed-tools: Read, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# /harness-doctor — Self-diagnostic

```bash
ROOT="$(cd .claude/.. && pwd)"

echo "# Harness Doctor — $(date -Iseconds)"
echo

# 1. Version check
echo "## Version"
if [ -f .claude/VERSION ]; then
  cat .claude/VERSION
else
  echo "⚠ .claude/VERSION missing — cannot determine harness version"
fi

# 2. Compare to upstream (if origin set)
if [ -f .claude/VERSION ]; then
  upstream=$(grep 'source=' .claude/VERSION | cut -d= -f2)
  if [ -n "$upstream" ]; then
    echo
    echo "## Upstream drift"
    echo "Source: $upstream"
    latest=$(claude -p "WebFetch $upstream/raw/main/.claude/VERSION and return the harness_version field" --bare 2>/dev/null)
    echo "Latest: $latest"
  fi
fi

# 3. Plugin staleness
echo
echo "## Plugin staleness"
if command -v claude >/dev/null; then
  claude -p "/plugin list with last-update dates" --bare 2>/dev/null | head -30
fi

# 4. MCP version pins
echo
echo "## MCP server pins"
echo "Pinned to @latest (supply-chain risk):"
grep -h '@latest' .mcp.json 2>/dev/null | head -10
echo
echo "Pinned to specific versions (good):"
grep -h '@[0-9]' .mcp.json 2>/dev/null | head -10

# 5. Hook log size
echo
echo "## Hook log size"
if [ -d .claude/hooks/.log ]; then
  du -sh .claude/hooks/.log/* 2>/dev/null | sort -rh | head -10
fi

# 6. Memory file size
echo
echo "## Memory file sizes"
for f in .claude/memory/MEMORY.md .claude/memory/decisions/*.md .claude/memory/incidents/*.md; do
  [ -f "$f" ] && wc -l "$f" 2>/dev/null
done | sort -rn | head -20

# 7. Settings.json size
echo
echo "## Settings.json metrics"
echo "Lines: $(wc -l < .claude/settings.json)"
echo "Allow patterns: $(jq -r '.permissions.allow | length' .claude/settings.json)"
echo "Ask patterns: $(jq -r '.permissions.ask | length' .claude/settings.json)"
echo "Deny patterns: $(jq -r '.permissions.deny | length' .claude/settings.json)"

# 8. Validate
echo
echo "## Validate"
bash .claude/scripts/validate.sh 2>&1 | tail -3

# 9. Recommend
echo
echo "## Recommendations"
echo "- If MCP @latest pins → run /audit-plugins to pin"
echo "- If MEMORY.md > 200 lines → run /dream"
echo "- If settings.json > 500 lines → /audit-settings to prune unused entries"
echo "- If upstream drift → git remote update && consider pulling harness updates"
```

## Recurring scan

Add to `dream-cron` so this runs daily and surfaces issues at session-start via additionalContext.

$ARGUMENTS
