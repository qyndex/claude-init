#!/usr/bin/env bash
# Cross-stream contract tests — Round 6 E.
#
# Each stream declares the contracts it *consumes* from sibling streams in
# .swarms/streams/<id>/analysis.md under `## Contracts consumed`. This script
# parses that section and asserts each consumed contract IS present on the
# integrated branch (this stream rebased onto main + other already-merged
# siblings).
#
# Contract types we check (heuristic — extend per project):
#   - exported_symbol:<lang>:<file>:<symbol>   → `grep -E 'export.*<symbol>' <file>` succeeds
#   - http_route:<method>:<path>               → `grep -E '<method>.*<path>' src/ -r` succeeds
#   - db_column:<table>:<column>               → migrations include the column add
#   - flag:<flag_name>                         → flag registry contains it
#
# Usage: bash .claude/scripts/contract-tests.sh <stream-id>
# Exit 0 if all contracts present; non-zero with list of missing.

set -uo pipefail

STREAM="${1:-}"
[ -z "$STREAM" ] && { echo "Usage: $0 <stream-id>" >&2; exit 1; }

ANALYSIS=".swarms/streams/${STREAM}/analysis.md"
[ -f "$ANALYSIS" ] || { echo "contract-tests: $ANALYSIS not found (no analysis = no contracts; passing)"; exit 0; }

# Extract `## Contracts consumed` section
contracts=$(awk '
  /^## Contracts consumed/ { in_section=1; next }
  /^## / && in_section { in_section=0 }
  in_section && /^- / { sub(/^- /,""); print }
' "$ANALYSIS")

if [ -z "$contracts" ]; then
  echo "contract-tests: no contracts declared in $ANALYSIS — passing"
  exit 0
fi

missing=0
echo "contract-tests: checking $(echo "$contracts" | wc -l | tr -d ' ') declared contracts"
while IFS= read -r contract; do
  [ -z "$contract" ] && continue
  type=$(echo "$contract" | cut -d: -f1)
  case "$type" in
    exported_symbol)
      lang=$(echo "$contract" | cut -d: -f2)
      file=$(echo "$contract" | cut -d: -f3)
      symbol=$(echo "$contract" | cut -d: -f4)
      if [ -f "$file" ]; then
        if grep -qE "(export.*${symbol}|^${symbol}|def ${symbol}|fn ${symbol})" "$file" 2>/dev/null; then
          echo "  ✓ exported_symbol $symbol in $file"
        else
          echo "  ✗ exported_symbol $symbol MISSING from $file"
          missing=$((missing + 1))
        fi
      else
        echo "  ✗ exported_symbol $symbol — file $file does not exist"
        missing=$((missing + 1))
      fi
      ;;
    http_route)
      method=$(echo "$contract" | cut -d: -f2)
      route=$(echo "$contract" | cut -d: -f3-)
      if grep -rqE "(${method}.*['\"]${route}['\"]|@(${method}|route)\\(['\"]${route})" src/ 2>/dev/null; then
        echo "  ✓ http_route $method $route"
      else
        echo "  ✗ http_route $method $route MISSING"
        missing=$((missing + 1))
      fi
      ;;
    db_column)
      table=$(echo "$contract" | cut -d: -f2)
      column=$(echo "$contract" | cut -d: -f3)
      if grep -rqE "(ALTER TABLE ${table}.*${column}|CREATE TABLE.*${table}.*${column}|${column}.*${table})" migrations/ db/ 2>/dev/null; then
        echo "  ✓ db_column ${table}.${column}"
      else
        echo "  ✗ db_column ${table}.${column} MISSING from migrations"
        missing=$((missing + 1))
      fi
      ;;
    flag)
      flag_name=$(echo "$contract" | cut -d: -f2)
      if grep -rqE "['\"]${flag_name}['\"]" .claude/memory/flags/ src/ 2>/dev/null; then
        echo "  ✓ flag $flag_name"
      else
        echo "  ✗ flag $flag_name MISSING from registry"
        missing=$((missing + 1))
      fi
      ;;
    *)
      echo "  ? unknown contract type: $type ($contract)"
      ;;
  esac
done <<< "$contracts"

if [ "$missing" -gt 0 ]; then
  echo
  echo "contract-tests: $missing contracts missing — semantic conflict likely"
  exit 1
fi
echo "contract-tests: all contracts satisfied"
exit 0
