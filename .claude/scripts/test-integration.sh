#!/usr/bin/env bash
# Run the project's integration test command. Auto-detects.
# Returns 0 if no integration tests found (graceful skip).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ -f package.json ] && grep -q '"test:integration"' package.json; then
  if [ -f pnpm-lock.yaml ]; then pnpm test:integration; exit $?
  else npm run test:integration; exit $?
  fi
elif [ -f pyproject.toml ] && [ -d tests/integration ]; then
  uv run pytest tests/integration/ -q
  exit $?
elif [ -f Cargo.toml ] && [ -d tests ]; then
  cargo test --tests
  exit $?
elif [ -f go.mod ]; then
  go test -tags=integration ./...
  exit $?
fi

echo "No integration tests configured (graceful skip)."
exit 0
