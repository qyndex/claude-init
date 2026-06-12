#!/usr/bin/env bash
# E2E: verify.sh accept re-run gate (tdd-loop-5)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1 (want=$2 got=$3)"; fail=$((fail+1)); fi; }

g=$(mktemp -d); cd "$g"
git init -q .; git config user.email t@t; git config user.name t
mkdir -p tasks .claude/scripts .claude/state
# minimal verify.sh harness: extract just the accept re-run block dependencies
cat > tasks/TASKS.md <<'EOF'
## Active
- [ ] T-950 | spec:HOTFIX | phase:1 | priority: normal | created: 2026-06-12 | est: 2m
  summary: will pass
  accept: test -f marker-a
  owner: implementer
- [ ] T-951 | spec:HOTFIX | phase:1 | priority: normal | created: 2026-06-12 | est: 2m
  summary: will fail
  accept: test -f marker-that-never-exists
  owner: implementer
EOF
git add -A; git commit -qm base
git branch -m main
git checkout -qb feat-x
touch marker-a
sed -i '' 's/^- \[ \] T-950/- [x] T-950/; s/^- \[ \] T-951/- [x] T-951/' tasks/TASKS.md
git add -A; git commit -qm flip

# run ONLY the accept re-run block via the real verify.sh with everything else skipped
cp "$R/.claude/scripts/verify.sh" .claude/scripts/
cp "$R/.claude/scripts/check-tdd-ledger.sh" .claude/scripts/ 2>/dev/null
cp -r "$R/.claude/scripts/lib" .claude/scripts/ 2>/dev/null
cp "$R/.claude/scripts/detect-stacks.sh" .claude/scripts/ 2>/dev/null
out=$(SKIP_COVERAGE=1 SKIP_TDD_LEDGER=1 SKIP_STORY_MAP=1 SKIP_INTEG_COV=1 SKIP_E2E_JOURNEY=1 SKIP_CHAR_GATE=1 bash .claude/scripts/verify.sh 2>&1); rc=$?
chk "verify fails when a newly-[x] accept is red" 1 $rc
printf '%s' "$out" | grep -q "T-950 accept still green" && { echo "PASS: green accept re-ran clean"; pass=$((pass+1)); } || { echo "FAIL: T-950 not re-run"; fail=$((fail+1)); }
printf '%s' "$out" | grep -q "T-951.*accept: now fails" && { echo "PASS: red accept flagged"; pass=$((pass+1)); } || { echo "FAIL: T-951 not flagged"; fail=$((fail+1)); }

# fix the failing accept → verify passes
touch marker-that-never-exists
out=$(SKIP_COVERAGE=1 SKIP_TDD_LEDGER=1 SKIP_STORY_MAP=1 SKIP_INTEG_COV=1 SKIP_E2E_JOURNEY=1 SKIP_CHAR_GATE=1 bash .claude/scripts/verify.sh 2>&1); rc=$?
chk "verify passes once accepts are green" 0 $rc

cd /; rm -rf "$g"
echo "----"; echo "accept-rerun matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
