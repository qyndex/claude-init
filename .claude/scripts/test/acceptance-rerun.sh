#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q; git config user.email fixture@example.invalid; git config user.name fixture
mkdir tasks
printf '# Tasks\n' > tasks/TASKS.md
git add .; git commit -qm base
base=$(git rev-parse HEAD)
runner="$ROOT/.claude/scripts/rerun-acceptance.py"
pass=0
check() { local expected="$1"; shift; if "$@" > output 2>&1; then actual=0; else actual=1; fi; [ "$actual" = "$expected" ] || { cat output; exit 1; }; pass=$((pass+1)); }
write_task() { printf '%s\n' '- [x] T-900 | spec:007' "  accept: $1" > tasks/TASKS.md; }
write_task 'printf proof > proof.txt'
git add tasks; git commit -qm candidate; git checkout -q --detach
check 0 python3 "$runner" --root "$tmp" --base "$base"
[ "$(cat proof.txt)" = proof ]
write_task false
# Exercise verify's wiring while HEAD is detached, not just the helper.
mkdir -p .claude/scripts
cp "${VERIFY_UNDER_TEST:-$ROOT/.claude/scripts/verify.sh}" .claude/scripts/verify.sh
[ ! -f "$runner" ] || cp "$runner" .claude/scripts/
printf '#!/bin/bash\necho '\''{"stacks":[],"workspace":"none"}'\''\n' > .claude/scripts/detect-stacks.sh
check 1 env VERIFY_BASE="$base" bash .claude/scripts/verify.sh
check 1 python3 "$runner" --root "$tmp" --base "$base"
write_task 'sleep 3'
check 1 python3 "$runner" --root "$tmp" --base "$base" --timeout 0.1
printf '%s\n' '- [x] T-900 | spec:007' > tasks/TASKS.md
check 1 python3 "$runner" --root "$tmp" --base "$base"
write_task true
cat tasks/TASKS.md >> duplicate; cat duplicate >> tasks/TASKS.md
check 1 python3 "$runner" --root "$tmp" --base "$base"
check 1 python3 "$runner" --root "$tmp" --base invalid-ref
check 1 python3 "$runner" --root "$tmp"
printf 'passed: %s; failed: 0\n' "$pass"
