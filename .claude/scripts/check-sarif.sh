#!/usr/bin/env bash
# Spec 006 AC-5: fail closed on scanner output errors and high/critical findings.
set -euo pipefail
file="${1:?Usage: check-sarif.sh <file>}"
shift
policy=""; expected=""; source_root=""; policy_args=0
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || { echo "Incomplete audit policy options" >&2; exit 1; }
  case "$1" in
    --audit-policy) [ -z "$policy" ] || { echo "Duplicate audit policy option" >&2; exit 1; }; policy="$2" ;;
    --expected-registry-sha256) [ -z "$expected" ] || { echo "Duplicate audit policy option" >&2; exit 1; }; expected="$2" ;;
    --source-root) [ -z "$source_root" ] || { echo "Duplicate audit policy option" >&2; exit 1; }; source_root="$2" ;;
    *) echo "Unknown SARIF gate option" >&2; exit 1 ;;
  esac
  policy_args=$((policy_args+1)); shift 2
done
if [ "$policy_args" -ne 0 ] && { [ "$policy_args" -ne 3 ] || [ -z "$policy" ] || [ -z "$expected" ] || [ -z "$source_root" ]; }; then
  echo "Audit policy blocked: explicit policy, protected expected hash and source root required" >&2; exit 1
fi
[ -s "$file" ] || { echo "SARIF missing or empty: $file" >&2; exit 1; }
# SARIF 2.1.0 sections 3.27.9/.10 and 3.50.3: kind defaults to fail;
# explicit result level wins, otherwise inherit the rule configuration level.
# This scanner gate resolves inline driver rules; unsupported external metadata
# or invocation overrides must block instead of silently using a weaker level.
audit_mode=false
[ "$policy_args" -eq 0 ] || audit_mode=true
if ! findings=$(jq -s --argjson audit_mode "$audit_mode" '
  def require($valid): if $valid then . else error("invalid severity metadata") end;
  def level: require(. == "error" or . == "warning" or . == "note" or . == "none");
  def nonempty_string: type == "string" and length > 0;
  def optional_array($key):
    if has($key) then .[$key] | require(type == "array") else [] end;
  def driver_rules:
    (if has("tool") then .tool | require(type == "object") else {} end) |
    require((optional_array("extensions") | length == 0)) |
    (if has("driver") then .driver | require(type == "object") else {} end) |
    optional_array("rules");
  def property_severity:
    if has("properties") then
      .properties | require(type == "object") |
      if has("security-severity") then
        .["security-severity"] | require(type == "number" or type == "string") |
        tonumber | require(isfinite and (isnan | not))
      else null end
    else null end;
  def id_agrees($id; $rule):
    $id == null or $id == $rule.id or
    ($id | startswith($rule.id + "/") and
      (ltrimstr($rule.id + "/") | length > 0 and (contains("/") | not)));
  # SARIF array index -1 means unknown/absent, not an invalid rule reference.
  def rule_index:
    require(type == "number" and . >= -1 and floor == .) |
    if . == -1 then null else . end;
  def descriptor($run; $result):
    ($result | if has("rule") then .rule | require(type == "object") else {} end) as $ref |
    $ref | require(($result | has("rule") | not) or has("id") or has("index")) |
    require((has("toolComponent") | not) and (has("guid") | not)) |
    $result | require((has("ruleId") | not) or (.ruleId | nonempty_string)) |
    $ref | require((has("id") | not) or (.id | nonempty_string)) |
    require(($result | has("ruleId") | not) or (has("id") | not) or .id == $result.ruleId) |
    # Explicit fields must agree before -1 becomes an absent lookup index
    # (SARIF 2.1.0 sections 3.27.6 and 3.52.5).
    require(($result | has("ruleIndex") | not) or (has("index") | not) or .index == $result.ruleIndex) |
    ($result | if has("ruleIndex") then .ruleIndex | rule_index else null end) as $result_index |
    ($ref | if has("index") then .index | rule_index else null end) as $reference_index |
    require($result_index == null or $reference_index == null or $result_index == $reference_index) |
    ($result.ruleId // $ref.id // null) as $id |
    ($result_index // $reference_index) as $index |
    ($run | driver_rules) as $rules |
    $rules | require(all(.[]; type == "object" and (.id | nonempty_string))) |
    if $index != null then
      $index | require(type == "number" and . >= 0 and floor == . and . < ($rules | length)) |
      $rules[$index] | require(id_agrees($id; .))
    elif $id != null then
      [$rules[] | select(id_agrees($id; .))] |
      require(length <= 1) | (.[0] // null) |
      require(. != null or ($result | has("rule") | not))
    else null end;
  def effective_level($result; $rule):
    ($result | if has("kind") then .kind else "fail" end) as $kind |
    $kind | require(. == "fail" or . == "pass" or . == "open" or
      . == "informational" or . == "notApplicable" or . == "review") |
    (if $rule != null and ($rule | has("defaultConfiguration")) then
      $rule.defaultConfiguration | require(type == "object") |
      if has("level") then .level | level else "warning" end
    else "warning" end) as $default |
    if $result | has("level") then
      $result.level | level | require($kind == "fail" or . == "none")
    elif $kind == "fail" then $default else "none" end;
  require(length == 1) | .[0] |
  require(type == "object" and .version == "2.1.0" and
    (.runs | type == "array" and length > 0)) |
  require((optional_array("inlineExternalProperties") | length == 0)) |
  [.runs[] as $run |
    $run | require(type == "object" and (.results | type == "array")) |
    # The narrow audit profile interprets only checkout-relative inline URIs.
    # It cannot authenticate remapped bases; default unwaived behavior is unchanged.
    require(($audit_mode | not) or (has("originalUriBaseIds") | not)) |
    require((has("externalPropertyFileReferences") | not) or
      (.externalPropertyFileReferences | type == "object" and length == 0)) |
    (driver_rules) as $validated_rules |
    optional_array("invocations") |
    require(all(.[]; type == "object" and
      (optional_array("ruleConfigurationOverrides") | length == 0) and
      (($audit_mode | not) or (has("workingDirectory") | not)))) |
    $run.results[] | require(type == "object") | . as $result |
    descriptor($run; $result) as $rule |
    effective_level($result; $rule) as $level |
    ($result | property_severity) as $result_severity |
    ($rule // {} | property_severity) as $rule_severity |
    ($result_severity // $rule_severity // 0) as $severity |
    select(($result.kind // "fail") == "fail" and ($level == "error" or $severity >= 7)) |
    {rule: ($result.ruleId // $result.rule.id // $rule.id // null),
     locations: ($result.locations // null), numeric_high: ($severity >= 7), level: $level}
  ]
' "$file"); then
  echo "Invalid SARIF scan output or unsupported severity metadata" >&2
  exit 1
fi
if [ "$policy_args" -ne 0 ]; then
  printf '%s\n' "$findings" | python3 -I "$(dirname "$0")/check-sarif-audit-policy.py" \
    --policy "$policy" --expected-sha256 "$expected" --source-root "$source_root"
  exit "$?"
fi
count=$(printf '%s\n' "$findings" | jq 'length')
if [ "$count" -gt 0 ]; then
  echo "$count high/critical findings" >&2; exit 1
fi
echo "SARIF clean of high/critical findings"
