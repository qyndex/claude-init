#!/usr/bin/env bash
# Test for the forthcoming `validate.sh --json` flag (Spec 001 AC-21, Phase 4).
#
# Tagged: AC-21
#
# Drives T-046. Encodes the --json contract that the implementer must satisfy:
#   bash .claude/scripts/validate.sh --json
# emits a single JSON document:
#   { schema_version: 1,
#     generated_at: <string>,
#     categories: [ {name,status,checked,failures,warnings}, ... ],
#     summary: { passed, warned, failed, overall } }
# where summary.overall matches ^(pass|warn|fail)$.
#
# It also asserts the DEFAULT (no-flag) text mode stays back-compatible: it must
# print the human banner ("→ Validating .claude/ harness" + "[core]" header) and
# must NOT be parseable as JSON.
#
# Until T-046 lands, the --json branch produces non-JSON text, so the --json
# assertions FAIL RED here — that is the intended red signal demanding T-046.
#
# lint-silent-failures: ignore-file
# This is a TEST: it captures validate.sh output to temp files and mutes stderr
# on purpose because each assertion's exit code (via `check`) is the signal. The
# silent-failure gate targets production scripts; a swallowed error in a test
# just fails the assertion below.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VALIDATE="$ROOT/.claude/scripts/validate.sh"

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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Capture both modes once (avoid nested process substitution) ----
JSON_OUT="$TMP/json.out"
TEXT_OUT="$TMP/text.out"
bash "$VALIDATE" --json >"$JSON_OUT" 2>/dev/null
bash "$VALIDATE" >"$TEXT_OUT" 2>/dev/null

# ---- AC-21.1: --json emits a single valid JSON document ----
jq -e . "$JSON_OUT" >/dev/null 2>&1
check "json-mode-valid: \`validate.sh --json\` stdout parses as JSON" $?

# ---- AC-21.2: schema_version is the literal 1 ----
jq -e '.schema_version == 1' "$JSON_OUT" >/dev/null 2>&1
check "json-schema-version: .schema_version == 1" $?

# ---- AC-21.3: categories is an array ----
jq -e '.categories | type == "array"' "$JSON_OUT" >/dev/null 2>&1
check "json-categories-array: .categories is a JSON array" $?

# ---- AC-21.4: each category carries name/status/checked/failures/warnings ----
jq -e 'all(.categories[]?; has("name") and has("status") and has("checked") and has("failures") and has("warnings"))' "$JSON_OUT" >/dev/null 2>&1
check "json-category-shape: every category has name/status/checked/failures/warnings" $?

# ---- AC-21.5: summary object has passed/warned/failed/overall ----
jq -e '.summary | has("passed") and has("warned") and has("failed") and has("overall")' "$JSON_OUT" >/dev/null 2>&1
check "json-summary-shape: .summary has passed/warned/failed/overall" $?

# ---- AC-21.6: summary.overall matches ^(pass|warn|fail)$ ----
jq -e '.summary.overall | test("^(pass|warn|fail)$")' "$JSON_OUT" >/dev/null 2>&1
check "json-summary-overall-enum: .summary.overall in {pass,warn,fail}" $?

# ---- AC-21.7: default text mode prints the human banner (back-compat) ----
grep -q 'Validating .claude/ harness' "$TEXT_OUT"
check "text-mode-banner: default mode prints the human banner" $?

grep -q '\[core\]' "$TEXT_OUT"
check "text-mode-category-header: default mode prints the [core] category header" $?

# ---- AC-21.8: default text mode is NOT JSON ----
if jq -e . "$TEXT_OUT" >/dev/null 2>&1; then
  check "text-mode-not-json: default mode does NOT emit JSON" 1
else
  check "text-mode-not-json: default mode does NOT emit JSON" 0
fi

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
