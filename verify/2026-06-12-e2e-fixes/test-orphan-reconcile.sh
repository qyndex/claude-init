#!/usr/bin/env bash
# E2E: orphan-reconcile.sh + requeue-failed extensions (failure-recovery-3)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3 s=$4 o=$5
  if [ "$a" = "$e" ] && { [ -z "$s" ] || printf '%s' "$o" | grep -qF "$s"; }; then
    echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (rc=$a want=$e out=$(printf '%s' "$o" | head -3))"; fail=$((fail+1)); fi
}

g=$(mktemp -d); cd "$g"
git init -q .
mkdir -p tasks .claude/state .claude/scripts/lib .claude/memory/.cache .claude/sessions/abc .claude/hooks/.log
cp "$R/.claude/scripts/orphan-reconcile.sh" .claude/scripts/
cp "$R/.claude/scripts/task-status.sh" .claude/scripts/
cp "$R/.claude/scripts/requeue-failed.sh" .claude/scripts/
cp "$R/.claude/scripts/loop-iteration.sh" .claude/scripts/
cp "$R/.claude/scripts/next-task.sh" .claude/scripts/
cp "$R/.claude/scripts/spec-status-sync.sh" .claude/scripts/ 2>/dev/null
cp -r "$R/.claude/scripts/lib" .claude/scripts/
cat > tasks/TASKS.md <<'EOF'
## Active
- [~] T-960 | spec:HOTFIX | phase:1 | priority: normal | created: 2026-06-12 | last_touched: 2026-06-01 | est: 5m
  summary: stale in-progress from dead session
  accept: true
  owner: implementer
- [x] T-961 | spec:HOTFIX | phase:1 | priority: normal | created: 2026-06-12 | est: 5m
  summary: done dep
  accept: true
  owner: implementer
- [b] T-962 | spec:HOTFIX | phase:1 | priority: normal | created: 2026-06-12 | deps: T-961 | est: 5m
  summary: blocked but deps all done
  blocked_by: T-961
  accept: true
  owner: implementer
EOF

# ── fresh heartbeat → refuse to reconcile
printf '{"last_heartbeat_at":"%s"}\n' "$(date -Iseconds)" > .claude/memory/.cache/current-session.json
out=$(bash .claude/scripts/orphan-reconcile.sh 2>&1); rc=$?
chk "fresh heartbeat blocks reconcile" 0 $rc "nothing reconciled" "$out"
grep -q '^- \[~\] T-960' tasks/TASKS.md && { echo "PASS: T-960 untouched"; pass=$((pass+1)); } || { echo "FAIL: T-960 flipped despite live heartbeat"; fail=$((fail+1)); }

# ── stale heartbeat → flip [~] to [!]
printf '{"last_heartbeat_at":"2026-06-12T01:00:00+05:30"}\n' > .claude/memory/.cache/current-session.json
out=$(TASK_STATUS_NO_SYNC=1 bash .claude/scripts/orphan-reconcile.sh 2>&1); rc=$?
chk "stale heartbeat reconciles" 0 $rc "reconciled: T-960" "$out"
grep -q '^- \[!\] T-960' tasks/TASKS.md && { echo "PASS: T-960 now [!]"; pass=$((pass+1)); } || { echo "FAIL: T-960 not flipped"; fail=$((fail+1)); }
grep -q 'orphaned_at=' .claude/state/task-status-notes.log && { echo "PASS: orphaned_at note logged"; pass=$((pass+1)); } || { echo "FAIL: no orphaned_at note"; fail=$((fail+1)); }

# ── dry-run mode
sed -i '' 's/^- \[!\] T-960/- [~] T-960/' tasks/TASKS.md
out=$(bash .claude/scripts/orphan-reconcile.sh --dry-run 2>&1); rc=$?
chk "dry-run reports without flipping" 0 $rc "DRY: would flip T-960" "$out"
grep -q '^- \[~\] T-960' tasks/TASKS.md && { echo "PASS: dry-run left marker"; pass=$((pass+1)); } || { echo "FAIL: dry-run mutated"; fail=$((fail+1)); }

# ── requeue-failed extensions: stale [~] + unblockable [b]
out=$(bash .claude/scripts/requeue-failed.sh 2>&1)
printf '%s' "$out" | grep -q 'T-960' && printf '%s' "$out" | grep -q 'possible orphans' && { echo "PASS: stale [~] surfaced"; pass=$((pass+1)); } || { echo "FAIL: stale [~] not surfaced"; fail=$((fail+1)); }
printf '%s' "$out" | grep -q 'T-962' && printf '%s' "$out" | grep -q 'deps are ALL' && { echo "PASS: unblockable [b] surfaced"; pass=$((pass+1)); } || { echo "FAIL: unblockable [b] not surfaced"; fail=$((fail+1)); }

cd /; rm -rf "$g"
echo "----"; echo "orphan matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
