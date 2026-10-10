#!/usr/bin/env bash
# Trusted receipts determine delivery; local ship markers cannot close feedback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${1:-}" ] || [ -z "${FACTORY_RUNTIME_DB:-}" ] || [ -z "${FACTORY_REPOSITORY:-}" ]; then
  echo "Feedback remains open: provide spec ID and trusted FACTORY_RUNTIME_DB/FACTORY_REPOSITORY." >&2
  exit 1
fi
exec python3 "$ROOT/.claude/scripts/factory-feedback.py" --db "$FACTORY_RUNTIME_DB" \
  --repository "$FACTORY_REPOSITORY" --reconcile-spec "${1%%-*}"
