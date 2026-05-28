#!/usr/bin/env bash
# Test scaffolding for .claude/hooks/pre-edit-constitution-guard.sh (Spec 001 AC-1).
#
# Tagged: AC-01
#
# Exercises 15+ deny-list paths, the FORCE_CONSTITUTION_EDIT escape hatch,
# and one allow-pass control. Each case feeds a synthesised PreToolUse JSON
# payload into the hook on stdin and asserts on the {exit-code, stdout-JSON}
# pair the spec/plan promise:
#
#   - deny-listed path           → exit 2 AND stdout contains permissionDecision:"deny"
#   - FORCE_CONSTITUTION_EDIT=1  → exit 0 even on a deny-listed path
#   - normal path                → exit 0 (continue chain), no permissionDecision deny
#
# Until T-002 lands the hook, every assertion must fail red — that is the
# point of the scaffold and the TDD ledger's red.log captures it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$ROOT/.claude/hooks/pre-edit-constitution-guard.sh"

pass=0
fail=0
fails=()

run_case() {
  # run_case <label> <expect: deny|allow> <env-prefix> <file_path>
  local label="$1" expect="$2" env_prefix="$3" file_path="$4"
  local payload exit_code out

  payload=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","new_string":"x"},"session_id":"test-session"}' "$file_path")

  # Clear an inherited FORCE_CONSTITUTION_EDIT so the deny cases test the guard's
  # real behavior even when an operator has the escape hatch set in their shell.
  # The escape-hatch case re-sets it explicitly via env_prefix.
  if [ -n "$env_prefix" ]; then
    out=$(printf '%s' "$payload" | env -u FORCE_CONSTITUTION_EDIT $env_prefix bash "$HOOK" 2>&1)
  else
    out=$(printf '%s' "$payload" | env -u FORCE_CONSTITUTION_EDIT bash "$HOOK" 2>&1)
  fi
  exit_code=$?

  case "$expect" in
    deny)
      # Spec: exit 2 AND stdout JSON has permissionDecision: "deny".
      if [ "$exit_code" = "2" ] && printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
        pass=$((pass+1))
      else
        fail=$((fail+1))
        fails+=("$label: expected deny (exit 2 + permissionDecision deny) but got exit=$exit_code out=$out")
      fi
      ;;
    allow)
      # Spec: exit 0 and no deny JSON.
      if [ "$exit_code" = "0" ] && ! printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
        pass=$((pass+1))
      else
        fail=$((fail+1))
        fails+=("$label: expected allow (exit 0, no deny) but got exit=$exit_code out=$out")
      fi
      ;;
  esac
}

# ---- Deny-list cases (15) — every constitution-class path the hook must reject.
run_case "DENY-01 constitution"             deny ""  ".claude/CLAUDE.md"
run_case "DENY-02 settings.json"            deny ""  ".claude/settings.json"
run_case "DENY-03 mcp.json"                 deny ""  ".mcp.json"
run_case "DENY-04 hook script"              deny ""  ".claude/hooks/pre-bash-guard.sh"
run_case "DENY-05 hook nested"              deny ""  ".claude/hooks/sub/dir/anything.sh"
run_case "DENY-06 workflow"                 deny ""  ".github/workflows/harness-validate.yml"
run_case "DENY-07 workflow nested"          deny ""  ".github/workflows/nested/ci.yml"
run_case "DENY-08 ruleset"                  deny ""  ".github/rulesets/main-protection.json"
run_case "DENY-09 CODEOWNERS"               deny ""  ".github/CODEOWNERS"
run_case "DENY-10 absolute constitution"    deny ""  "$ROOT/.claude/CLAUDE.md"
run_case "DENY-11 absolute settings"        deny ""  "$ROOT/.claude/settings.json"
run_case "DENY-12 absolute hook"            deny ""  "$ROOT/.claude/hooks/pre-write-secret-scan.sh"
run_case "DENY-13 absolute workflow"        deny ""  "$ROOT/.github/workflows/claude-review.yml"
run_case "DENY-14 absolute ruleset"         deny ""  "$ROOT/.github/rulesets/main-protection.json"
run_case "DENY-15 absolute CODEOWNERS"      deny ""  "$ROOT/.github/CODEOWNERS"

# ---- Escape-hatch case — FORCE_CONSTITUTION_EDIT=1 must let a deny-listed path through.
run_case "FORCE escape hatch on CLAUDE.md"  allow "FORCE_CONSTITUTION_EDIT=1" ".claude/CLAUDE.md"

# ---- Allow-pass case — a normal repo path must NOT be denied.
run_case "ALLOW normal path"                allow "" "src/app.ts"

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
