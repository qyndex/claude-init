#!/usr/bin/env bash
# Test for audit-doc-claims.sh (Spec 001 AC-23). The script-under-test is built
# in T-053; this is the failing test that demands it.
#
# Tagged: AC-23
#
# audit-doc-claims.sh scans docs for enforcement claims ("enforced by X" /
# "blocked by X" / "gated by X" / "required by X") and verifies each named gate
# X resolves to a REAL .claude/scripts/*.sh (executable), .github/workflows/*.yml,
# or .claude/hooks/*.sh. An orphan claim (gate X does not exist) → non-zero exit.
#
# SANDBOX CONVENTION (T-053 MUST honor this): the audit script accepts the doc
# root to scan via the env var AUDIT_DOC_ROOT. When set, the script scans markdown
# under that directory instead of the real repo doc set. Gate resolution always
# resolves against the real repo ($ROOT/.claude/scripts, /.github/workflows,
# /.claude/hooks) so a doc in the sandbox can legitimately reference validate.sh.
#
# Portable for BSD + GNU (macOS default shell). No nested process substitution.
#
# lint-silent-failures: ignore-file
# This is a TEST: it mutes the audit script's stderr because the assertion's exit
# code (captured via `check`) is the signal, not the script's diagnostic noise.
# The silent-failure gate targets production scripts where a swallowed error hides
# a real fault; here a swallowed error simply fails the assertion below.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
AUDIT="$ROOT/.claude/scripts/audit-doc-claims.sh"

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

# Sandbox doc root — never scan the real repo doc set.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- case 1: doc references a clearly non-existent gate → orphan → non-zero ---
ORPHAN_DIR="$TMP/orphan"
mkdir -p "$ORPHAN_DIR"
cat >"$ORPHAN_DIR/claim.md" <<'EOF'
# Orphan claim fixture

This rule is enforced by nonexistent-gate-xyz.sh, which does not exist anywhere
in the harness, so the audit must flag it.
EOF
AUDIT_DOC_ROOT="$ORPHAN_DIR" bash "$AUDIT" >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ]
check "orphan-claim-fails: claim naming a non-existent gate exits non-zero" $?

# --- case 2: doc references a REAL gate (validate.sh exists) → exit 0 ---
REAL_DIR="$TMP/real"
mkdir -p "$REAL_DIR"
cat >"$REAL_DIR/claim.md" <<'EOF'
# Real claim fixture

Harness structure is enforced by validate.sh on every .claude/ edit, and the
15-class bypass set is blocked by pre-bash-guard.sh.
EOF
AUDIT_DOC_ROOT="$REAL_DIR" bash "$AUDIT" >/dev/null 2>&1
check "real-gate-passes: claim naming an existing gate exits 0" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
