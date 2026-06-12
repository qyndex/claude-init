#!/usr/bin/env bash
# Multi-stack unit-test dispatcher (e2e-audit stack-portability-2).
#
# Previously: if/elif waterfall that picked ONE stack and exec'd it — polyglot
# repos only ever tested the first match, and an unrecognized stack exited 0
# ("No unit test command configured.") — silent green. Now: lint.sh's pattern —
# loop over EVERY detected language stack, run its unit tests, aggregate, and
# exit 1 when a stack is detected but cannot be tested.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# JUSTIFIED: detection errors yield empty stacks — the empty guard below surfaces it rather than passing silently
stacks_json=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null || echo '{"stacks":[]}')
# JUSTIFIED: jq muted on malformed output — empty list is caught below
stacks=$(echo "$stacks_json" | jq -r '.stacks[]' 2>/dev/null | grep -E '^(typescript|python|rust|go|java|ruby|dotnet|php)$' || true)

if [ -z "$stacks" ]; then
  echo "test-unit: no language stacks detected — nothing to test (docs/shell-only repo)"
  exit 0
fi

# Python PM ladder (stack-portability-3)
py_run() {
  if [ -f uv.lock ]; then uv run "$@"
  elif [ -f poetry.lock ]; then poetry run "$@"
  elif [ -f Pipfile.lock ]; then pipenv run "$@"
  else "$@"
  fi
}

failures=0
ran=0

for stack in $stacks; do
  echo
  echo "→ unit tests [$stack]"
  case "$stack" in
    typescript)
      if [ -f package.json ] && grep -q '"test"' package.json; then
        ran=$((ran + 1))
        if [ -f pnpm-lock.yaml ]; then pnpm test --run || failures=$((failures + 1))
        elif [ -f bun.lock ] || [ -f bun.lockb ]; then bun test || failures=$((failures + 1))
        elif [ -f yarn.lock ]; then yarn test --run || failures=$((failures + 1))
        else npm test -- --run || failures=$((failures + 1))
        fi
      else
        echo "  ✗ node stack detected but package.json has no test script"
        failures=$((failures + 1))
      fi
      ;;
    python)
      if [ -d tests ] || [ -f conftest.py ]; then
        ran=$((ran + 1))
        py_run python3 -m pytest -q || failures=$((failures + 1))
      else
        echo "  ✗ python stack detected but no tests/ dir or conftest.py"
        failures=$((failures + 1))
      fi
      ;;
    rust)
      ran=$((ran + 1))
      cargo test --lib --bins || failures=$((failures + 1))
      ;;
    go)
      ran=$((ran + 1))
      go test -short ./... || failures=$((failures + 1))
      ;;
    java)
      ran=$((ran + 1))
      if [ -f pom.xml ]; then mvn -q test || failures=$((failures + 1))
      elif [ -x ./gradlew ]; then ./gradlew test || failures=$((failures + 1))
      else gradle test || failures=$((failures + 1))
      fi
      ;;
    ruby)
      ran=$((ran + 1))
      if [ -d spec ]; then bundle exec rspec || failures=$((failures + 1))
      else bundle exec rake test || failures=$((failures + 1))
      fi
      ;;
    dotnet)
      ran=$((ran + 1))
      dotnet test || failures=$((failures + 1))
      ;;
    php)
      if jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
        ran=$((ran + 1)); composer test || failures=$((failures + 1))
      elif [ -x vendor/bin/phpunit ]; then
        ran=$((ran + 1)); vendor/bin/phpunit || failures=$((failures + 1))
      else
        echo "  ✗ php stack detected but no composer test script / phpunit"
        failures=$((failures + 1))
      fi
      ;;
  esac
done

echo
if [ "$ran" -eq 0 ]; then
  echo "test-unit: stacks detected but ZERO test commands executed — refusing silent pass"
  exit 1
fi
if [ "$failures" -gt 0 ]; then
  echo "test-unit: $failures stack(s) failed"
  exit 1
fi
echo "test-unit: all $ran stack(s) green"
exit 0
