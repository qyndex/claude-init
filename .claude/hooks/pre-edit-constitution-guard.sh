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

# Escape hatch — operator-driven amendment. Log LOUDLY every time it fires so a
# leaked/persisted FORCE_CONSTITUTION_EDIT (e.g. exported into a long-lived shell)
# is visible in the audit trail instead of silently disabling the whole guard.
if [ "${FORCE_CONSTITUTION_EDIT:-0}" = "1" ]; then
  mkdir -p .claude/hooks/.log 2>/dev/null
  printf '%s\t%s\tFORCE_CONSTITUTION_EDIT=1 active — guard bypassed\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "constitution-guard-bypass" \
    >> .claude/hooks/.log/constitution-write-attempts.log 2>/dev/null || true
  exit 0
fi

# Fail-closed jq preamble (e2e-audit hooks-engineering-4): without jq the grep
# fallback below still works for simple payloads, but escaped/nested paths can
# evade it — this guard protects the constitution itself, so it fails CLOSED.
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked by .claude/hooks/pre-edit-constitution-guard.sh: jq is not installed; the constitution guard fails CLOSED. Install jq (brew install jq)." >&2
  exit 2
fi

# Read PreToolUse JSON payload from stdin.
# JUSTIFIED: cat stderr suppressed and || true — an empty/closed stdin yields an empty payload, handled by the -z guard below; the hook must fail open, not crash the tool chain
payload=$(cat 2>/dev/null || true)
if [ -z "$payload" ]; then
  exit 0
fi

# Extract file_path (jq if available; fall back to grep on the JSON).
file_path=""
if command -v jq >/dev/null 2>&1; then
  # JUSTIFIED: jq stderr suppressed — malformed JSON yields an empty file_path and falls back to the grep extractor below; the guard must not abort on bad input
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
# JUSTIFIED: cd error output discarded — if the dir is unreachable ROOT becomes empty and rel stays the raw path, which is still matched against the deny-list
ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd || echo "")"
rel="$file_path"
if [ -n "$ROOT" ]; then
  case "$file_path" in
    "$ROOT"/*) rel="${file_path#"$ROOT"/}" ;;
  esac
fi

# Canonicalize before matching — a literal case-glob is bypassed by a leading
# "./" or an embedded "/./" or "/../" segment that still resolves to a protected
# file (e.g. "./.claude/./CLAUDE.md"). Collapse them so the deny-list always sees
# the real path. Pure-bash (no realpath dependency, and the file may not exist yet).
while [ "$rel" != "${rel#./}" ]; do rel="${rel#./}"; done   # strip leading ./
rel="${rel//\/.\///}"                                       # collapse /./ → /
# collapse a/b/../c → a/c, iteratively (left-to-right, bounded by path depth)
while case "$rel" in */../*|*/..) true ;; *) false ;; esac; do
  # JUSTIFIED: sed is the simplest reliable collapse of one ../ segment; loop bounds it
  next=$(printf '%s' "$rel" | sed -E 's#(^|/)[^/]+/\.\.(/|$)#\1#')
  [ "$next" = "$rel" ] && break
  rel="$next"
done
rel="${rel#/}"                                              # drop any leading slash

# Deny-list — constitution-class globs.
deny=0
case "$rel" in
  .claude/CLAUDE.md)                       deny=1 ;;
  .claude/settings.json)                   deny=1 ;;
  .claude/hooks/*)                         deny=1 ;;
  .claude/rules/*)                         deny=1 ;;
  .claude/agents/*)                        deny=1 ;;
  # Gap-audit G2: skill frontmatter is a §IX cache-prefix surface, same as agents/*.
  # Proposals still flow freely via .claude/memory.proposed/skills/ (not matched here).
  .claude/skills/*)                        deny=1 ;;
  .mcp.json)                               deny=1 ;;
  .github/workflows/*)                     deny=1 ;;
  .github/rulesets/*)                      deny=1 ;;
  .github/CODEOWNERS)                      deny=1 ;;
  tasks/TASKS.md)                          deny=1 ;;
  specs/active/*)                          deny=1 ;;
esac

# Spec-write carve-out (e2e-audit failure-recovery-1): /specify must be able to
# CREATE specs/active/<id>-<slug>.md. Creation of a not-yet-existing spec file is
# allowed; mutation of an existing spec stays denied (approved specs are immutable
# to agents — amendments go through the operator). Path shape is enforced so the
# carve-out cannot be used to plant arbitrary files under specs/active/.
if [ "$deny" = "1" ]; then
  case "$rel" in
    specs/active/[0-9][0-9][0-9]-*.md)
      if [ ! -e "$rel" ] && [ ! -e "${ROOT:+$ROOT/}$rel" ]; then
        deny=0
      fi
      ;;
  esac
fi

if [ "$deny" = "1" ]; then
  # Audit-log the attempt before denying.
  # JUSTIFIED: mkdir error output discarded — the log dir usually exists; a creation failure must not stop the deny path that follows
  mkdir -p .claude/hooks/.log 2>/dev/null
  # JUSTIFIED: append error output discarded and tolerated — best-effort audit line; an unwritable log must never prevent the security deny below
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "constitution-write-attempt" "$rel" \
    >> .claude/hooks/.log/constitution-write-attempts.log 2>/dev/null || true

  # Emit deny JSON per Claude Code hook contract.
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Constitution-class file '${rel}' is protected from agent writes. Set FORCE_CONSTITUTION_EDIT=1 in your shell to override (operator-only). See .claude/memory/incidents/2026-05-28-sec-constitution-unprotected.md."}}
EOF
  # On exit 2 the harness surfaces STDERR; keep the stdout JSON for the test
  # contract but mirror the reason here so it is never silently dropped.
  echo "Constitution-class file '${rel}' is protected from agent writes. Set FORCE_CONSTITUTION_EDIT=1 in your shell to override (operator-only). See .claude/memory/incidents/2026-05-28-sec-constitution-unprotected.md." >&2
  exit 2
fi

# Path not in deny-list — continue the hook chain.
exit 0
