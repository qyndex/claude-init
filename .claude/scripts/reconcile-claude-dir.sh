#!/usr/bin/env bash
# Versioned ownership and private transactional recovery; no target setup execution.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/factory-adopt.py" "$@"
