#!/usr/bin/env bash
# Run the project's unit test command. Auto-detects.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ -f package.json ] && grep -q '"test"' package.json; then
  if [ -f pnpm-lock.yaml ]; then exec pnpm test --run
  elif [ -f bun.lock ]; then exec bun test
  elif [ -f yarn.lock ]; then exec yarn test --run
  else exec npm test -- --run
  fi
elif [ -f pyproject.toml ]; then
  if [ -d tests ] || [ -f conftest.py ]; then
    exec uv run pytest tests/ -q
  fi
elif [ -f Cargo.toml ]; then
  exec cargo test --lib --bins
elif [ -f go.mod ]; then
  exec go test -short ./...
else
  echo "No unit test command configured."
  exit 0
fi
