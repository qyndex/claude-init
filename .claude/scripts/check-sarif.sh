#!/usr/bin/env bash
# Spec 006 AC-5: fail closed on scanner output errors and high/critical findings.
set -euo pipefail
file="${1:?Usage: check-sarif.sh <file>}"
[ -s "$file" ] || { echo "SARIF missing or empty: $file" >&2; exit 1; }
jq -e '
  .version == "2.1.0" and
  (.runs | type == "array" and length > 0) and
  all(.runs[]; (.results | type == "array") and all(.results[]; type == "object"))
' "$file" >/dev/null || { echo "Invalid SARIF scan output" >&2; exit 1; }
count=$(jq '[
  .runs[] as $run | $run.results[] |
  . as $result |
  ($result.properties."security-severity" //
    ([$run.tool.driver.rules[]? | select(.id == $result.ruleId) |
       .properties."security-severity" | select(. != null)][0]) // 0 | tonumber) as $severity |
  select(.level == "error" or $severity >= 7)
] | length' "$file")
if [ "$count" -gt 0 ]; then
  echo "$count high/critical findings" >&2; exit 1
fi
echo "SARIF clean of high/critical findings"
