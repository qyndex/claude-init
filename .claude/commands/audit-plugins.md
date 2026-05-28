---
description: Check installed plugins + .mcp.json entries for staleness, security advisories, version pin drift. Runs monthly or before any major harness change.
argument-hint: "[--auto-pin]"
allowed-tools: Read, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# /audit-plugins — Plugin + MCP staleness check

```bash
echo "# Plugin + MCP audit — $(date -Iseconds)"

# 1. Plugins
echo
echo "## Installed plugins"
if command -v claude >/dev/null; then
  claude -p "/plugin list --json" --bare 2>/dev/null | jq -r '.[] | "\(.name) @ \(.version // "unpinned") — last update: \(.last_updated // "unknown")"' | head -30
fi

# 2. For each marketplace plugin, check last GitHub push
echo
echo "## Marketplace freshness check"
jq -r '.recommended_plugins[]? | .marketplace + "/" + .name' .claude/plugins/marketplace.json 2>/dev/null | while read entry; do
  marketplace=$(echo "$entry" | cut -d/ -f1)
  plugin=$(echo "$entry" | cut -d/ -f2)
  repo=$(jq -r --arg m "$marketplace" '.marketplaces[] | select(.name == $m) | .owner + "/" + .repo' .claude/plugins/marketplace.json 2>/dev/null)
  if [ -n "$repo" ]; then
    last_push=$(gh api "repos/$repo" --jq '.pushed_at' 2>/dev/null)
    age_days=$(( ($(date +%s) - $(date -d "$last_push" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_push" +%s 2>/dev/null)) / 86400 ))
    if [ "$age_days" -gt 365 ]; then
      echo "⚠ STALE: $entry — repo $repo last push ${age_days} days ago"
    fi
  fi
done

# 3. MCP servers — find @latest pins
echo
echo "## MCP servers pinned to @latest (supply-chain risk)"
grep -n '@latest' .mcp.json | grep -v '_doc\|_disabled' || echo "(none — good)"

# 4. Recommended pins
echo
echo "## Suggested pinned versions (from npm registry)"
grep -h '@latest' .mcp.json 2>/dev/null | grep -oE '@[a-zA-Z0-9/_-]+/?[a-zA-Z0-9-]+@latest' | sort -u | while read pkg_at_latest; do
  pkg=$(echo "$pkg_at_latest" | sed 's/@latest$//')
  latest=$(npm view "$pkg" version 2>/dev/null)
  if [ -n "$latest" ]; then
    echo "  $pkg@latest → $pkg@$latest"
  fi
done

# 5. Security advisories
echo
echo "## Security advisories on plugins"
echo "Stub: GitHub Security Advisories API integration"
# gh api repos/owner/repo/security-advisories — requires per-repo loop

# 6. Recommend
echo
echo "## Recommendations"
echo "- Pin any MCP @latest above to specific versions and let Dependabot upgrade"
echo "- Audit stale plugins: consider removing or replacing"
echo "- Run /harness-doctor for the broader harness health view"

if [ "${1:-}" = "--auto-pin" ]; then
  echo
  echo "## Auto-pinning @latest in .mcp.json"
  # In-place replace @latest with the actual latest version
  cp .mcp.json .mcp.json.before-pin
  echo "Backup at .mcp.json.before-pin"
  # The agent runs this as a follow-up edit
fi
```

$ARGUMENTS
