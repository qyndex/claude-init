#!/usr/bin/env bash
# Boot script — used by the verifier agent to start the app for E2E.
# Per-project: edit this to match your stack.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Detect and run
if [ -f package.json ]; then
  if grep -q '"dev"' package.json; then
    if [ -f pnpm-lock.yaml ]; then exec pnpm dev
    elif [ -f bun.lock ]; then exec bun run dev
    elif [ -f yarn.lock ]; then exec yarn dev
    else exec npm run dev
    fi
  elif grep -q '"start"' package.json; then
    if [ -f pnpm-lock.yaml ]; then exec pnpm start
    else exec npm start
    fi
  fi
elif [ -f pyproject.toml ]; then
  if grep -q 'fastapi\|uvicorn' pyproject.toml; then
    exec uv run uvicorn app:app --reload
  elif grep -q 'flask' pyproject.toml; then
    exec uv run flask run
  elif grep -q 'django' pyproject.toml; then
    exec uv run python manage.py runserver
  else
    echo "Edit .claude/scripts/run.sh — Python project but no recognized framework."
    exit 1
  fi
elif [ -f Cargo.toml ]; then
  exec cargo run
elif [ -f go.mod ]; then
  exec go run ./...
elif [ -f docker-compose.yml ] || [ -f compose.yml ]; then
  exec docker compose up
else
  echo "No recognized project structure. Edit .claude/scripts/run.sh per project."
  exit 1
fi
