#!/usr/bin/env bash
# AC-2 accept: pre-bash-guard.sh must exit 2 (not 0) on a deny path.
# The destructive command lives in this file (not the caller's argv) so the
# live pre-bash-guard does not block the runner that exercises it.
set -uo pipefail
cd "$(dirname "$0")/../.."
payload=$(printf '{"tool_input":{"command":"%s"}}' "rm -rf /tmp/x")
printf '%s' "$payload" | bash .claude/hooks/pre-bash-guard.sh >/dev/null 2>&1
ec=$?
[ "$ec" -eq 2 ]
