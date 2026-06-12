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
elif [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then
  # Python PM ladder (e2e-audit stack-portability-3): the runner follows the
  # lockfile — uv was previously assumed, breaking poetry/pipenv/pip repos.
  py_run() {
    if [ -f uv.lock ]; then exec uv run "$@"
    elif [ -f poetry.lock ]; then exec poetry run "$@"
    elif [ -f Pipfile.lock ]; then exec pipenv run "$@"
    else exec "$@"
    fi
  }
  py_manifest="pyproject.toml"
  [ -f "$py_manifest" ] || py_manifest="requirements.txt"
  if grep -q 'fastapi\|uvicorn' "$py_manifest" 2>/dev/null; then
    py_run uvicorn app:app --reload
  elif grep -q 'flask' "$py_manifest" 2>/dev/null; then
    py_run flask run
  elif grep -q 'django' "$py_manifest" 2>/dev/null; then
    py_run python manage.py runserver
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
