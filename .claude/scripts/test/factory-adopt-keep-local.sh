#!/usr/bin/env bash
# Real isolated Git/filesystem fixtures; no actual adopter or live authority.
set -euo pipefail
cd "$(dirname "$0")/../../.."
exec python3 .claude/scripts/test/factory-adopt-keep-local.py
