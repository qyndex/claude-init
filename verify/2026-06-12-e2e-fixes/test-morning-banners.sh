#!/usr/bin/env bash
# E2E: morning-operator banners in staged session-start-context.sh (autopilot-4)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
has() { if printf '%s' "$2" | grep -qF "$1"; then echo "PASS: banner '$1'"; pass=$((pass+1)); else echo "FAIL: missing banner '$1'"; fail=$((fail+1)); fi; }

g=$(mktemp -d); cd "$g"
git init -q .
mkdir -p tasks .claude/state .claude/scripts/lib .claude/memory/.cache .claude/hooks
cp "$R/verify/2026-06-12-e2e-fixes/staged/.claude/hooks/session-start-context.sh" .claude/hooks/
cp "$R/.claude/scripts/orphan-reconcile.sh" .claude/scripts/ 2>/dev/null
cp "$R/.claude/scripts/requeue-failed.sh" .claude/scripts/ 2>/dev/null
cp -r "$R/.claude/scripts/lib" .claude/scripts/ 2>/dev/null

cat > tasks/TASKS.md <<'EOF'
## Active
- [!] T-970 | spec:HOTFIX | phase:1 | priority: normal | created: 2026-06-12 | est: 2m
  summary: failed overnight
  accept: true
  owner: implementer
EOF
printf '# Overnight\nESCALATION: stop-verify gate blocked 3x\nESCALATION: subagent handoff invalid\n' > OVERNIGHT_REPORT.md
date -Iseconds > .claude/state/ideation-pending
printf '{"count":3,"same_task_streak":0,"last_task":"T-970","last_error_hash":null,"last_pivot_attempt":0,"updated":"x"}\n' > .claude/state/consecutive-aborts.json

out=$(bash .claude/hooks/session-start-context.sh < /dev/null 2>/dev/null)
has "OVERNIGHT_REPORT.md is 0h old with 2 ESCALATION(s)" "$out"
has "[!] failed tasks: 1" "$out"
has "IDEATION-PENDING" "$out"
has "ABORT-CAP REACHED (count=3)" "$out"
printf '%s' "$out" | jq -e . >/dev/null 2>&1 && { echo "PASS: output is valid JSON"; pass=$((pass+1)); } || { echo "FAIL: invalid JSON output"; fail=$((fail+1)); }

# quiet path: no triggers → none of the four banners
rm OVERNIGHT_REPORT.md .claude/state/ideation-pending
printf '{"count":0,"same_task_streak":0,"last_task":null,"last_error_hash":null,"last_pivot_attempt":0,"updated":"x"}\n' > .claude/state/consecutive-aborts.json
cat > tasks/TASKS.md <<'EOF'
## Active
EOF
out=$(bash .claude/hooks/session-start-context.sh < /dev/null 2>/dev/null)
for s in "OVERNIGHT_REPORT" "failed tasks" "IDEATION" "ABORT-CAP"; do
  if printf '%s' "$out" | grep -qF "$s"; then echo "FAIL: quiet path emitted '$s'"; fail=$((fail+1)); else echo "PASS: quiet path silent on '$s'"; pass=$((pass+1)); fi
done

cd /; rm -rf "$g"
echo "----"; echo "banner matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
