#!/usr/bin/env bash
# Spec 006 AC-1: a healthy coordinator must not hide a failing candidate.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/coordinator/.claude/scripts" "$tmp/candidate/.claude/scripts" "$tmp/bin"
cp "$ROOT/.claude/scripts/verify.sh" "$ROOT/.claude/scripts/local-pr-check.sh" "$tmp/coordinator/.claude/scripts/"
for dir in coordinator candidate; do
  printf '#!/bin/bash\nprintf '\''{"stacks":[],"workspace":"none"}\\n'\''\n' > "$tmp/$dir/.claude/scripts/detect-stacks.sh"
done
printf '{"scripts":{"test":"false"}}\n' > "$tmp/candidate/package.json"
printf '#!/bin/bash\nexit 42\n' > "$tmp/bin/npm"; chmod +x "$tmp/bin/npm"
export PATH="$tmp/bin:$PATH"
pass=0; fail=0
expect_fail() { if "$@" >"$tmp/output" 2>&1; then echo "FAIL: $* unexpectedly passed"; fail=$((fail+1)); else pass=$((pass+1)); fi; }
expect_fail bash "$tmp/coordinator/.claude/scripts/verify.sh" --root "$tmp/candidate"
expect_fail bash "$tmp/coordinator/.claude/scripts/verify.sh" --root "$tmp/missing"
if bash "$tmp/coordinator/.claude/scripts/verify.sh" --root "$tmp/coordinator" >"$tmp/output" 2>&1; then pass=$((pass+1)); else cat "$tmp/output"; fail=$((fail+1)); fi
printf '#!/bin/bash\n[ -f package.json ] && exit 42\nexit 0\n' > "$tmp/bin/semgrep"; chmod +x "$tmp/bin/semgrep"
expect_fail bash "$tmp/coordinator/.claude/scripts/local-pr-check.sh" --only=semgrep --root "$tmp/candidate"
# Exercise the actual coordinator merge gate, with every external command stubbed.
merge_root="$tmp/merge"
mkdir -p "$merge_root/.claude/scripts" "$merge_root/.claude/worktrees/fixture" "$merge_root/.swarms/coordinator"
cp "$ROOT/.claude/scripts/verified-merge.sh" "$merge_root/.claude/scripts/"
printf '{"fleet":{"fixture":{"branch":"fixture","status":"ready"}}}' > "$merge_root/.swarms/coordinator/fleet.json"
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/git"
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/claude"
printf '#!/bin/bash\necho unexpected-gh >> "$FACTORY_FIXTURE/gh-calls"\nexit 42\n' > "$tmp/bin/gh"
chmod +x "$tmp/bin/git" "$tmp/bin/claude" "$tmp/bin/gh"
export FACTORY_FIXTURE="$merge_root"
# Verify must receive the candidate path as an argument, not rely on CWD.
cat > "$merge_root/.claude/scripts/verify.sh" <<'STUB'
#!/bin/bash
[ "$1" = "--root" ] && [ "$2" = "$FACTORY_FIXTURE/.claude/worktrees/fixture" ]
STUB
printf '#!/bin/bash\nexit 42\n' > "$merge_root/.claude/scripts/local-pr-check.sh"
printf '#!/bin/bash\nexit 0\n' > "$merge_root/.claude/scripts/contract-tests.sh"
expect_fail bash "$merge_root/.claude/scripts/verified-merge.sh" fixture --dry-run
# Mediation may repair heavy checks, but a remaining contract failure still blocks.
cat > "$merge_root/.claude/scripts/local-pr-check.sh" <<'STUB'
#!/bin/bash
if [ ! -f "$FACTORY_FIXTURE/heavy-ran" ]; then touch "$FACTORY_FIXTURE/heavy-ran"; exit 42; fi
exit 0
STUB
printf '#!/bin/bash\necho ran >> "$FACTORY_FIXTURE/contracts-ran"\nexit 42\n' > "$merge_root/.claude/scripts/contract-tests.sh"
expect_fail bash "$merge_root/.claude/scripts/verified-merge.sh" fixture
if [ -f "$merge_root/contracts-ran" ] && [ ! -f "$merge_root/gh-calls" ]; then pass=$((pass+1)); else echo 'FAIL: mediation omitted contracts or reached merge'; fail=$((fail+1)); fi
echo "passed: $pass; failed: $fail"; [ "$fail" -eq 0 ]
