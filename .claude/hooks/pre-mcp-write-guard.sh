#!/usr/bin/env bash
# PreToolUse hook for MCP write tools (e2e-audit security-automode-1/-5).
#
# The filesystem MCP server is alwaysLoad and its write_file/edit_file/move_file
# bypass the Write|Edit matcher entirely — an auto-mode agent could rewrite
# settings.json, hooks, CI, or the constitution itself through MCP with zero
# guard coverage. Same for github-MCP content writes (create_or_update_file,
# push_files). This hook closes that hole by synthesizing a Write-equivalent
# payload per target path and delegating to the two existing guards, so the
# deny-list, path canonicalization, and secret rules live in ONE place:
#   1. pre-edit-constitution-guard.sh  (constitution-class deny-list)
#   2. pre-write-secret-scan.sh        (secret patterns in path + content)
#
# Registered matcher (settings.json PreToolUse):
#   mcp__filesystem__write_file|mcp__filesystem__edit_file|mcp__filesystem__move_file|mcp__github__create_or_update_file|mcp__github__push_files
#
# MCP read tools stay ungated (read deny-listing is handled by permissions).
# Exit contract matches the delegated guards: deny → exit 2 + stdout JSON.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Fail-closed jq preamble (e2e-audit hooks-engineering-4): this guard cannot do
# its job without JSON parsing — refuse the tool call rather than fail open.
if ! command -v jq >/dev/null 2>&1; then
  echo "pre-mcp-write-guard: jq is required for MCP write guarding — install jq (brew install jq). Denying MCP write until then." >&2
  exit 2
fi

# JUSTIFIED: cat stderr suppressed and || true — an empty/closed stdin yields an empty payload, handled below; matcher misfires must not crash the chain
payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)

# Collect every path this call writes to, plus the content when available.
paths=""
content=""
case "$tool_name" in
  mcp__filesystem__write_file)
    paths=$(printf '%s' "$payload" | jq -r '.tool_input.path // empty')
    content=$(printf '%s' "$payload" | jq -r '.tool_input.content // empty')
    ;;
  mcp__filesystem__edit_file)
    paths=$(printf '%s' "$payload" | jq -r '.tool_input.path // empty')
    content=$(printf '%s' "$payload" | jq -r '[.tool_input.edits[]?.newText // empty] | join("\n")')
    ;;
  mcp__filesystem__move_file)
    paths=$(printf '%s\n%s' \
      "$(printf '%s' "$payload" | jq -r '.tool_input.source // empty')" \
      "$(printf '%s' "$payload" | jq -r '.tool_input.destination // empty')")
    ;;
  mcp__github__create_or_update_file)
    paths=$(printf '%s' "$payload" | jq -r '.tool_input.path // empty')
    content=$(printf '%s' "$payload" | jq -r '.tool_input.content // empty')
    ;;
  mcp__github__push_files)
    paths=$(printf '%s' "$payload" | jq -r '.tool_input.files[]?.path // empty')
    content=$(printf '%s' "$payload" | jq -r '[.tool_input.files[]?.content // empty] | join("\n")')
    ;;
  *)
    # Unknown tool routed here — nothing to extract; let the classifier decide.
    exit 0
    ;;
esac

[ -z "$paths" ] && exit 0

while IFS= read -r p; do
  [ -z "$p" ] && continue
  synth=$(jq -cn --arg fp "$p" --arg c "$content" \
    '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')

  # Secret-path rules: settings.json's Read/Write deny list (.env*, *.pem, *.key,
  # *credentials*) does NOT apply to MCP tools — enforce the same globs here.
  base="${p##*/}"
  case "$base" in
    .env|.env.*|*.pem|*.key|*credentials*)
      echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Secret-class path '${p}' is deny-listed for writes (settings.json parity for MCP tools).\"}}"
      echo "pre-mcp-write-guard: ${tool_name} write to secret-class path '${p}' denied." >&2
      exit 2
      ;;
  esac

  # Delegate 1: constitution-class deny-list (path canonicalization included).
  out=$(printf '%s' "$synth" | bash "$HOOK_DIR/pre-edit-constitution-guard.sh" 2>&1)
  rc=$?
  if [ "$rc" -eq 2 ]; then
    printf '%s\n' "$out"
    echo "pre-mcp-write-guard: ${tool_name} write to '${p}' denied by constitution guard." >&2
    exit 2
  fi

  # Delegate 2: secret scan (path rules + content patterns). Its deny contract
  # is exit 0 + stdout JSON, so detect the decision, not the exit code.
  out=$(printf '%s' "$synth" | bash "$HOOK_DIR/pre-write-secret-scan.sh" 2>&1)
  rc=$?
  if [ "$rc" -eq 2 ] || printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    printf '%s\n' "$out"
    echo "pre-mcp-write-guard: ${tool_name} write to '${p}' denied by secret scan." >&2
    exit 2
  fi
done <<EOF_PATHS
$paths
EOF_PATHS

exit 0
