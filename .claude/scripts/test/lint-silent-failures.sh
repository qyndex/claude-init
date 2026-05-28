#!/usr/bin/env bash
# Test for lint-silent-failures.sh (Spec 001 AC-8).
#
# lint-silent-failures: ignore-file
#   This file seeds DELIBERATELY-unjustified silent-error patterns into a temp
#   fixture tree to exercise the linter. Those fixture strings are not real
#   silent failures, so the real-tree audit skips this file wholesale.
#
# Tagged: AC-08
#
# Seeds fixture scripts containing silent-error patterns — some annotated with a
# nearby `# JUSTIFIED:` comment, some not — and asserts the linter correctly
# classifies justified vs unjustified and exits non-zero iff unjustified > 0.
#
# The linter is invoked against a fixture tree via SCAN_DIRS + AUDIT_FILE overrides
# so it never depends on the real .claude/scripts content.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINT="$ROOT/.claude/scripts/lint-silent-failures.sh"

pass=0
fail=0
fails=()

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SCAN_DIRS="$TMP/scripts"
export AUDIT_FILE="$TMP/audit.json"
mkdir -p "$SCAN_DIRS"

# Fixture A — UNJUSTIFIED silent failures (no nearby # JUSTIFIED:).
cat >"$SCAN_DIRS/unjustified.sh" <<'EOF'
#!/usr/bin/env bash
rm /tmp/whatever || true
count=$(grep -c foo bar 2>/dev/null)
risky_command || echo 0
EOF

# Fixture B — JUSTIFIED silent failures (annotated within 3 lines).
cat >"$SCAN_DIRS/justified.sh" <<'EOF'
#!/usr/bin/env bash
# JUSTIFIED: best-effort cleanup; the file may legitimately not exist yet.
rm /tmp/scratch || true
# JUSTIFIED: jq absence is handled by the caller; empty output is the contract.
value=$(jq -r .x file.json 2>/dev/null)
EOF

# Fixture C — set -uo pipefail without -e (the spec's named anti-pattern).
cat >"$SCAN_DIRS/noerrexit.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
do_thing
EOF

expect() { # expect <label> <condition-rc>
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi
}

# Run the linter (expected to exit non-zero because of fixture A + C).
bash "$LINT" >/dev/null 2>&1
lint_rc=$?

test -f "$AUDIT_FILE"
expect "audit JSON is written" $?

jq -e . "$AUDIT_FILE" >/dev/null 2>&1
expect "audit JSON is valid" $?

# Unjustified count must be > 0 (fixture A's 3 + fixture C's set-line are unjustified).
jq -e '.unjustified > 0' "$AUDIT_FILE" >/dev/null 2>&1
expect "unjustified count is surfaced (> 0)" $?

# The justified fixture's patterns must be classified justified, not unjustified.
# Anchor on "/justified.sh" so the substring does not also match "unjustified.sh".
jq -e '[.findings[] | select(.path | test("/justified.sh$")) | .justified] | all' "$AUDIT_FILE" >/dev/null 2>&1
expect "annotated patterns are classified justified" $?

# The unjustified fixture's patterns must NOT be classified justified.
jq -e '[.findings[] | select(.path | test("/unjustified.sh$")) | .justified] | any | not' "$AUDIT_FILE" >/dev/null 2>&1
expect "unannotated patterns are classified unjustified" $?

# Linter exits non-zero when unjustified > 0.
[ "$lint_rc" -ne 0 ]
expect "linter exits non-zero on unjustified findings" $?

# Now annotate everything and confirm a clean run exits 0.
cat >"$SCAN_DIRS/unjustified.sh" <<'EOF'
#!/usr/bin/env bash
# JUSTIFIED: now annotated.
rm /tmp/whatever || true
# JUSTIFIED: now annotated.
count=$(grep -c foo bar 2>/dev/null)
# JUSTIFIED: now annotated.
risky_command || echo 0
EOF
cat >"$SCAN_DIRS/noerrexit.sh" <<'EOF'
#!/usr/bin/env bash
# JUSTIFIED: scripts here intentionally continue past errors and handle them inline.
set -uo pipefail
do_thing
EOF
rm -f "$AUDIT_FILE"
bash "$LINT" >/dev/null 2>&1
clean_rc=$?
jq -e '.unjustified == 0' "$AUDIT_FILE" >/dev/null 2>&1
expect "fully annotated tree reports unjustified == 0" $?
[ "$clean_rc" -eq 0 ]
expect "linter exits 0 when all findings justified" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
