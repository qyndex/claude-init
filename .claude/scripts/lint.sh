#!/usr/bin/env bash
# Multi-stack lint dispatcher — Round 8 E.
#
# Previously: if/elif waterfall that picked ONE stack and exec'd it. Polyglot
# repos with both npm + python only ever ran npm lint. Silently passed CI
# when no stack was detected.
#
# Now: loops over EVERY detected stack, runs the right linter, aggregates
# failures. Exit non-zero if ANY stack fails. No silent pass.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

stacks_json=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null || echo '{"stacks":[]}')
stacks=$(echo "$stacks_json" | jq -r '.stacks[]' 2>/dev/null)

if [ -z "$stacks" ]; then
  echo "lint: no stacks detected — refusing silent pass (Round 8 E)"
  exit 1
fi

failures=0
ran=0

run_stack_lint() {
  local stack="$1"
  echo
  echo "→ lint [$stack]"
  ran=$((ran + 1))

  case "$stack" in
    typescript|npm)
      if [ -f package.json ] && grep -q '"lint"' package.json; then
        if [ -f pnpm-lock.yaml ]; then pnpm lint || failures=$((failures + 1))
        elif [ -f bun.lock ]; then bun run lint || failures=$((failures + 1))
        elif [ -f yarn.lock ]; then yarn lint || failures=$((failures + 1))
        else npm run lint || failures=$((failures + 1))
        fi
      elif command -v eslint >/dev/null; then
        eslint --max-warnings 0 . || failures=$((failures + 1))
      else
        echo "  ⚠ no eslint configured; install + add lint script to package.json"
        failures=$((failures + 1))
      fi
      ;;
    python|pypi)
      if command -v ruff >/dev/null; then
        ruff check . || failures=$((failures + 1))
      else
        echo "  ⚠ ruff not installed"
        failures=$((failures + 1))
      fi
      ;;
    rust|crates)
      cargo clippy --all-targets --all-features -- -D warnings || failures=$((failures + 1))
      ;;
    go)
      if command -v golangci-lint >/dev/null; then
        golangci-lint run || failures=$((failures + 1))
      else
        # Fallback to less-strict go vet
        echo "  ⚠ golangci-lint not installed; falling back to go vet (weaker)"
        go vet ./... || failures=$((failures + 1))
      fi
      ;;
    java)
      if command -v gradle >/dev/null && [ -f build.gradle ]; then
        gradle check --warning-mode all || failures=$((failures + 1))
      elif command -v mvn >/dev/null && [ -f pom.xml ]; then
        mvn checkstyle:check spotbugs:check || failures=$((failures + 1))
      fi
      ;;
    terraform)
      if command -v tflint >/dev/null; then
        tflint --recursive || failures=$((failures + 1))
      fi
      if command -v terraform >/dev/null; then
        terraform fmt -check -recursive || failures=$((failures + 1))
      fi
      ;;
    docker)
      if command -v hadolint >/dev/null; then
        find . -name 'Dockerfile*' -not -path '*/node_modules/*' -print0 | xargs -0 hadolint || failures=$((failures + 1))
      fi
      ;;
    shell)
      if command -v shellcheck >/dev/null; then
        find . -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.git/*' -print0 \
          | xargs -0 shellcheck -S warning || failures=$((failures + 1))
      fi
      ;;
    sql)
      if command -v sqlfluff >/dev/null; then
        sqlfluff lint --dialect=ansi . || failures=$((failures + 1))
      fi
      ;;
    *)
      echo "  ℹ no lint configured for stack: $stack"
      ;;
  esac
}

for s in $stacks; do
  run_stack_lint "$s"
done

echo
echo "─────────────────────────────────────"
echo "lint: ran=$ran stacks failures=$failures"
[ "$failures" -eq 0 ]
