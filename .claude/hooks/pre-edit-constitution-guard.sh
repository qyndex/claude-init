#!/usr/bin/env bash
# PreToolUse hook for Write|Edit|NotebookEdit — blocks agent writes to constitution-class files.
#
# Spec 001 AC-1: enforces what CLAUDE.md §VII/§X claim. Without this hook, the constitution
# itself, the hooks that enforce all guards, the settings that define permissions, and the
# CI workflows are all writable by Claude with zero protection — see incident
# .claude/memory/incidents/2026-05-28-sec-constitution-unprotected.md.
#
# Contract (matches .claude/scripts/test/pre-edit-constitution-guard.sh):
#   - deny-listed path           → exit 2 AND stdout JSON {"permissionDecision":"deny", ...}
#   - FORCE_CONSTITUTION_EDIT=1  → exit 0 (escape hatch for legitimate operator edits)
#   - normal path                → exit 0 (no decision, continue hook chain)
#
# Escape hatch usage: a human operator runs `FORCE_CONSTITUTION_EDIT=1 claude` to amend
# the constitution intentionally. The harness must NEVER set this variable from inside
# any script/agent/workflow — only the operator's shell rc.
#
# Latency budget: <50ms p95. Path check only; no content scan.

set -uo pipefail

# Escape hatch — operator-driven amendment.
if [ "${FORCE_CONSTITUTION_EDIT:-0}" = "1" ]; then
  exit 0
fi

# Read PreToolUse JSON payload from stdin.
payload=$(cat 2>/dev/null || true)
if [ -z "$payload" ]; then
  exit 0
fi

# Extract file_path (jq if available; fall back to grep on the JSON).
file_path=""
if command -v jq >/dev/null 2>&1; then
  file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
fi
if [ -z "$file_path" ]; then
  file_path=$(printf '%s' "$payload" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
fi
if [ -z "$file_path" ]; then
  # No path → nothing to guard.
  exit 0
fi

# Normalize to repo-relative — strip the absolute prefix if present.
ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd || echo "")"
rel="$file_path"
if [ -n "$ROOT" ]; then
  case "$file_path" in
    "$ROOT"/*) rel="${file_path#$ROOT/}" ;;
  esac
fi

# Deny-list — constitution-class globs.
deny=0
case "$rel" in
  .claude/CLAUDE.md)                       deny=1 ;;
  .claude/settings.json)                   deny=1 ;;
  .claude/hooks/*)                         deny=1 ;;
  .claude/rules/*)                         deny=1 ;;
  .claude/agents/*)                        deny=1 ;;
  .mcp.json)                               deny=1 ;;
  .github/workflows/*)                     deny=1 ;;
  .github/rulesets/*)                      deny=1 ;;
  .github/CODEOWNERS)                      deny=1 ;;
esac

if [ "$deny" = "1" ]; then
  # Audit-log the attempt before denying.
  mkdir -p .claude/hooks/.log 2>/dev/null
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "constitution-write-attempt" "$rel" \
    >> .claude/hooks/.log/constitution-write-attempts.log 2>/dev/null || true

  # Emit deny JSON per Claude Code hook contract.
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Constitution-class file '${rel}' is protected from agent writes. Set FORCE_CONSTITUTION_EDIT=1 in your shell to override (operator-only). See .claude/memory/incidents/2026-05-28-sec-constitution-unprotected.md."}}
EOF
  exit 2
fi

# Path not in deny-list — continue the hook chain.
exit 0
