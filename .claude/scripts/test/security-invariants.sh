#!/usr/bin/env bash
# Security-invariants baseline for the harness (Spec 001 AC-3).
#
# Tagged: AC-03
#
# Asserts the constitution's §VII/§X security invariants hold in the committed
# config. This is the first 4-invariant scaffold; Phase 6 (T-047+) extends it to
# cover the full §VII verification chain and §X guardrail set.
#
# Each INVARIANT-NN is a single check against committed config/hooks — no network,
# no side effects. Exit 0 only when all pass; exit 1 lists the failures.
#
# Until T-007 (evidence-gate ruleset) and T-008 (sandbox in auto mode) land,
# INVARIANT-03 and INVARIANT-04 fail RED — that is the point: this suite is the
# failing test that demands those two tasks.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SETTINGS="$ROOT/.claude/settings.json"
RULESET="$ROOT/.github/rulesets/main-protection.json"

pass=0
fail=0
fails=()

check() {
  # check <label> <condition-exit-code>
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$label")
  fi
}

# ---- INVARIANT-01: constitution is write-protected (§X) ----
# The pre-edit-constitution-guard hook must be registered in the PreToolUse
# Write/Edit chain so agent writes to .claude/CLAUDE.md are denied.
jq -e '.hooks.PreToolUse[]?.hooks[]? | select(.command | test("pre-edit-constitution-guard"))' "$SETTINGS" >/dev/null 2>&1
check "INVARIANT-01 constitution-write-protect: pre-edit-constitution-guard registered in PreToolUse" $?

# ---- INVARIANT-02: bash-guard blocks the documented bypass classes (§X) ----
# The 15-class bypass regression must pass — proves rm-rf/curl-pipe-sh/etc are denied.
bash "$ROOT/.claude/scripts/test/pre-bash-guard-bypass.sh" >/dev/null 2>&1
check "INVARIANT-02 bash-guard-bypass-coverage: 15-class bypass regression passes" $?

# ---- INVARIANT-03: evidence-gate is a required status check (§VII.7) ----
# main-protection.json must list evidence-gate so merges blocked when any AC is UNPROVEN.
jq -e '[.rules[]? | select(.type=="required_status_checks") | (.parameters.required_status_checks[]?.context // .parameters.required_checks[]?.context)] | index("evidence-gate")' "$RULESET" >/dev/null 2>&1
check "INVARIANT-03 evidence-gate-ruleset: evidence-gate is a required check in main-protection.json" $?

# ---- INVARIANT-04: sandbox enabled in auto mode (§X) ----
# Background/auto sessions must run sandboxed: either sandbox.enabled:true or
# an enabledWhen guard referencing auto mode.
jq -e '.permissions.sandbox.enabled == true or (.permissions.sandbox.enabledWhen // "" | test("auto"))' "$SETTINGS" >/dev/null 2>&1
check "INVARIANT-04 sandbox-auto-mode: sandbox enabled (or auto-gated) in settings.json" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
