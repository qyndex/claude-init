#!/usr/bin/env bash
# Multi-stack typecheck dispatcher — Round 8 E.
# Loops over every detected stack; refuses silent pass.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

stacks_json=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null || echo '{"stacks":[]}')
stacks=$(echo "$stacks_json" | jq -r '.stacks[]' 2>/dev/null)

if [ -z "$stacks" ]; then
  echo "typecheck: no stacks detected"
  exit 1
fi

failures=0
ran=0

for stack in $stacks; do
  echo
  echo "→ typecheck [$stack]"
  ran=$((ran + 1))

  case "$stack" in
    typescript|npm)
      if [ -f tsconfig.json ]; then
        npx tsc --noEmit --strict || failures=$((failures + 1))
      fi
      ;;
    python|pypi)
      if command -v mypy >/dev/null; then
        mypy --strict . || failures=$((failures + 1))
      else
        echo "  ⚠ mypy not installed"
        failures=$((failures + 1))
      fi
      ;;
    rust|crates)
      cargo check --all-targets || failures=$((failures + 1))
      ;;
    go)
      go build ./... || failures=$((failures + 1))
      ;;
    java)
      if command -v gradle >/dev/null && [ -f build.gradle ]; then
        gradle compileJava || failures=$((failures + 1))
      elif command -v mvn >/dev/null && [ -f pom.xml ]; then
        mvn compile || failures=$((failures + 1))
      fi
      ;;
  esac
done

echo
echo "─────────────────────────────────────"
echo "typecheck: ran=$ran stacks failures=$failures"
[ "$failures" -eq 0 ]
