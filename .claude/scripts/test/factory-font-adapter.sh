#!/usr/bin/env bash
# Run the complete Python adapter suite through the existing M00 shell inventory.
set -euo pipefail
cd "$(dirname "$0")/../../.."
exec python3 .claude/scripts/test/factory-font-adapter.py
