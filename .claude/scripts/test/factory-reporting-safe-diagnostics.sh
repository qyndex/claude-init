#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 .claude/scripts/test/factory-reporting-safe-diagnostics.py
