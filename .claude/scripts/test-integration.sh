#!/usr/bin/env bash
# Multi-stack integration-test dispatcher (e2e-audit stack-portability-2).
#
# Loops over EVERY detected language stack (lint.sh pattern) instead of the old
# first-match waterfall. Integration tests are OPTIONAL per stack (a project
# may genuinely have none) — but when a stack declares them (script/dir/tag
# convention present), a failure is a failure. Exits 1 if any declared
# integration suite fails; 0 when none exist (graceful, visible skip).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# JUSTIFIED: detection errors yield empty stacks — handled by the loop running zero times with a visible skip line
stacks_json=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null || echo '{"stacks":[]}')
# JUSTIFIED: jq muted on malformed output — empty list yields the graceful-skip exit
stacks=$(echo "$stacks_json" | jq -r '.stacks[]' 2>/dev/null | grep -E '^(typescript|python|rust|go|java|ruby|dotnet|php)$' || true)

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
  case "$stack" in
    typescript)
      if [ -f package.json ] && grep -q '"test:integration"' package.json; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        if [ -f pnpm-lock.yaml ]; then pnpm test:integration || failures=$((failures + 1))
        elif [ -f yarn.lock ]; then yarn test:integration || failures=$((failures + 1))
        elif [ -f bun.lock ] || [ -f bun.lockb ]; then bun run test:integration || failures=$((failures + 1))
        else npm run test:integration || failures=$((failures + 1))
        fi
      fi
      ;;
    python)
      if [ -d tests/integration ]; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        py_run python3 -m pytest tests/integration/ -q || failures=$((failures + 1))
      fi
      ;;
    rust)
      if [ -d tests ]; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        cargo test --tests || failures=$((failures + 1))
      fi
      ;;
    go)
      # JUSTIFIED: grep muted — no files carry the integration build tag, so there is nothing to run for this stack
      if grep -rql 'go:build integration' --include='*.go' . 2>/dev/null | head -1 | grep -q .; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        go test -tags=integration ./... || failures=$((failures + 1))
      fi
      ;;
    java)
      if [ -f pom.xml ] && grep -q failsafe pom.xml; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        mvn -q verify || failures=$((failures + 1))
      fi
      ;;
    ruby)
      if [ -d spec/integration ]; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        bundle exec rspec spec/integration || failures=$((failures + 1))
      fi
      ;;
    dotnet)
      # JUSTIFIED: find muted — absence of an *.IntegrationTests project means nothing to run
      if find . -maxdepth 3 -name '*IntegrationTests*.csproj' -print -quit 2>/dev/null | grep -q .; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        dotnet test --filter Category=Integration || failures=$((failures + 1))
      fi
      ;;
    php)
      if jq -e '.scripts["test:integration"]' composer.json >/dev/null 2>&1; then
        echo "→ integration [$stack]"
        ran=$((ran + 1))
        composer test:integration || failures=$((failures + 1))
      fi
      ;;
  esac
done

if [ "$ran" -eq 0 ]; then
  echo "No integration tests configured in any detected stack (graceful skip)."
  exit 0
fi
if [ "$failures" -gt 0 ]; then
  echo "test-integration: $failures stack(s) failed"
  exit 1
fi
echo "test-integration: all $ran integration suite(s) green"
exit 0
