#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts" "$tmp/.claude/state" "$tmp/bin"
cp "$ROOT/.claude/scripts/verify.sh" "$tmp/.claude/scripts/"
pass=0
check() { local expected="$1"; shift; if "$@" > "$tmp/output" 2>&1; then actual=0; else actual=1; fi; [ "$actual" = "$expected" ] || { cat "$tmp/output"; exit 1; }; pass=$((pass+1)); }
detect() { printf '#!/bin/bash\necho '\''%s'\''\n' "$1" > "$tmp/.claude/scripts/detect-stacks.sh"; }
detect '{"stacks":[],"workspace":"none"}'
check 0 bash "$tmp/.claude/scripts/verify.sh"
touch "$tmp/.claude/state/allow-skip-gates"
check 1 env SKIP_COVERAGE=1 bash "$tmp/.claude/scripts/verify.sh"
check 1 env VERIFY_CI=1 GITHUB_ACTIONS=true SKIP_E2E_JOURNEY=1 bash "$tmp/.claude/scripts/verify.sh"
printf '#!/bin/bash\nexit 42\n' > "$tmp/.claude/scripts/detect-stacks.sh"
check 1 bash "$tmp/.claude/scripts/verify.sh"
detect '{"stacks":null}'
check 1 bash "$tmp/.claude/scripts/verify.sh"
detect '{"stacks":["new-language"]}'
check 1 bash "$tmp/.claude/scripts/verify.sh"
# Successful Ruby must not conceal Python with no test entrypoint.
detect '{"stacks":["python","ruby"],"workspace":"none"}'
touch "$tmp/requirements.txt" "$tmp/Gemfile"
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/bundle"; chmod +x "$tmp/bin/bundle"
check 1 env PATH="$tmp/bin:$PATH" bash "$tmp/.claude/scripts/verify.sh"
printf 'passed: %s; failed: 0\n' "$pass"
