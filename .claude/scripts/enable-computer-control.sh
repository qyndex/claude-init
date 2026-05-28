#!/usr/bin/env bash
# Opt-in script to enable the community Computer Use MCP server.
# REQUIRES disposable sandbox (Docker / VM) — do NOT run on your primary laptop.
#
# Background: Anthropic Computer Use is a powerful API but has no first-party
# Claude Code MCP. The community Shiyao-Huang/claude-code-computer-use-mcp is
# the closest canonical implementation. It can drive your desktop (mouse,
# keyboard, screenshots) so it's appropriate ONLY in disposable sandboxes.
#
# Refuses to run unless CLAUDE_SANDBOX_OK=1 is set.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ "${CLAUDE_SANDBOX_OK:-0}" != "1" ]; then
  cat <<EOF
✗ enable-computer-control.sh refused.

This script enables community Computer Use MCP which can control your desktop
(mouse, keyboard, screenshots). It is appropriate ONLY in disposable sandboxes:

  - Docker container that's destroyed after the run
  - Throwaway VM (Vagrant, Multipass, Lima)
  - Ephemeral CI runner

To proceed:
  CLAUDE_SANDBOX_OK=1 bash .claude/scripts/enable-computer-control.sh

For most browser work, prefer:
  - Claude in Chrome (if you need your authenticated session)
  - playwright-mcp / webapp-testing plugin (for deterministic UI automation)

These are the recommended paths in CLAUDE.md §X.
EOF
  exit 1
fi

step() { printf '\n→ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }

step "Enabling computer-control in .mcp.json"
# Idempotent: move from _disabled_examples to top-level mcpServers
if jq -e '.mcpServers."computer-use"' .mcp.json >/dev/null 2>&1; then
  ok "already enabled"
else
  jq '
    .mcpServers."computer-use" = ._disabled_examples."computer-use"
    | del(._disabled_examples."computer-use")
  ' .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
  ok "computer-use moved to active mcpServers"
fi

step "Verifying"
jq -r '.mcpServers."computer-use" | "  command: " + .command + " " + (.args | join(" "))' .mcp.json

step "Done"
cat <<EOF

WARNING: this MCP can control your desktop. To disable:
  jq '.mcpServers."computer-use" as \$cu | del(.mcpServers."computer-use") | ._disabled_examples."computer-use" = \$cu' .mcp.json > /tmp/m && mv /tmp/m .mcp.json

Restart Claude Code for the MCP change to take effect.
EOF
