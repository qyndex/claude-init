#!/usr/bin/env bash
# E2E: workflow-state.sh idle phase + session-scoped streak (autopilot-1)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want=$e got=$a)"; fail=$((fail+1)); fi; }

g=$(mktemp -d); cd "$g"
git init -q .
mkdir -p .claude/hooks .claude/scripts/lib .claude/state specs/active plans/active tasks .swarms/coordinator
cp "$R/verify/2026-06-12-e2e-fixes/staged/.claude/hooks/workflow-state.sh" .claude/hooks/
cp "$R/.claude/scripts/lib/atomic-write.sh" .claude/scripts/lib/
cp "$R/.claude/scripts/next-task.sh" .claude/scripts/
printf '# c\n' > .claude/CLAUDE.md
cat > tasks/TASKS.md <<'EOF'
## Active
EOF

run_hook() { CLAUDE_SESSION_ID="$1" bash .claude/hooks/workflow-state.sh < /dev/null; }

# ── shipped spec → idle, streak 0, no warn even after many turns
cat > specs/active/050-done-feature.md <<'EOF'
---
id: 050
status: shipped
---
# Done feature
EOF
for i in 1 2 3 4 5; do out=$(run_hook sess-A); done
phase=$(jq -r '.phase' .swarms/coordinator/workflow-state.json)
streak=$(jq -r '.streak' .swarms/coordinator/workflow-state.json)
chk "shipped spec → phase idle" "idle" "$phase"
chk "idle forces streak 0 (no ratchet after 5 turns)" "0" "$streak"
case "$out" in *"LOOP DETECTED"*|*"still stuck"*) echo "FAIL: idle emitted a stuck warning"; fail=$((fail+1));; *) echo "PASS: idle emits no stuck warning"; pass=$((pass+1));; esac

# ── draft spec → streak ratchets within ONE session, G4 warn preserved
cat > specs/active/051-wip.md <<'EOF'
---
id: 051
status: draft
---
# WIP
EOF
sleep 1; touch specs/active/051-wip.md
out=""
for i in 1 2 3; do out=$(run_hook sess-B); done
streak=$(jq -r '.streak' .swarms/coordinator/workflow-state.json)
chk "same-session streak ratchets to 3" "3" "$streak"
case "$out" in *"LOOP DETECTED"*) echo "PASS: G4 full warn string preserved at streak 3"; pass=$((pass+1));; *) echo "FAIL: no LOOP DETECTED at streak 3: $out"; fail=$((fail+1));; esac
out=$(run_hook sess-B)
case "$out" in *"still stuck in this phase"*) echo "PASS: G4 short reminder string preserved"; pass=$((pass+1));; *) echo "FAIL: short reminder missing"; fail=$((fail+1));; esac

# ── new session resets the streak
out=$(run_hook sess-C)
streak=$(jq -r '.streak' .swarms/coordinator/workflow-state.json)
sid=$(jq -r '.session_id' .swarms/coordinator/workflow-state.json)
chk "new session resets streak to 1" "1" "$streak"
chk "session_id persisted" "sess-C" "$sid"
case "$out" in *"LOOP DETECTED"*|*"still stuck"*) echo "FAIL: new session inherited stuck warning"; fail=$((fail+1));; *) echo "PASS: new session starts quiet"; pass=$((pass+1));; esac

# ── hook output is valid JSON every time
run_hook sess-C | jq -e . >/dev/null && { echo "PASS: hook emits valid JSON"; pass=$((pass+1)); } || { echo "FAIL: invalid hook JSON"; fail=$((fail+1)); }

cd /; rm -rf "$g"
echo "----"
echo "workflow-state matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
