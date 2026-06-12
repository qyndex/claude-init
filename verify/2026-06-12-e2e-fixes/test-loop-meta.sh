#!/usr/bin/env bash
# E2E: run metadata + external-edit stop (e2e-audit autopilot-2/5)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3 s=$4 o=$5
  if [ "$a" = "$e" ] && { [ -z "$s" ] || printf '%s' "$o" | grep -qF "$s"; }; then
    echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (rc=$a want=$e out=$o)"; fail=$((fail+1)); fi
}

# ── Lib-level: loop_state_start / iterate / run_exceeded
tmpd=$(mktemp -d)
export STATE_FILE="$tmpd/state.json"
. "$R/.claude/scripts/lib/loop-state.sh"

loop_state_start "" 2
chk "start writes run metadata" 0 $? "" ""
out=$(jq -r '.run.max_iter' "$STATE_FILE")
chk "max_iter persisted" "2" "$out" "" "$out"

loop_state_run_exceeded >/dev/null; chk "fresh run not exceeded" 1 $? "" ""
loop_state_iterate; loop_state_iterate
out=$(loop_state_run_exceeded); chk "max-iter cap trips at 2/2" 0 $? "max-iter reached" "$out"

loop_state_start "2020-01-01T00:00:00+00:00" 0
out=$(loop_state_run_exceeded); chk "past deadline trips" 0 $? "deadline passed" "$out"

loop_state_start "2099-01-01T00:00:00+00:00" 0
loop_state_run_exceeded >/dev/null; chk "future deadline does not trip" 1 $? "" ""

# state without .run (legacy) — exceeded must not trip, iterate must no-op
loop_state_init
loop_state_run_exceeded >/dev/null; chk "no run metadata = unlimited" 1 $? "" ""
loop_state_iterate; chk "iterate no-ops without run metadata" 0 $? "" ""

# schema required keys still present after run metadata added
loop_state_start "" 5
for key in $(jq -r '.required[]' "$R/.claude/templates/consecutive-aborts.schema.json"); do
  jq -e "has(\"$key\")" "$STATE_FILE" >/dev/null || { echo "FAIL: schema key $key lost"; fail=$((fail+1)); }
done
echo "PASS: schema required keys preserved"; pass=$((pass+1))
unset STATE_FILE

# ── Script-level: loop-iteration.sh in a sandbox git repo
g=$(mktemp -d); cd "$g"
git init -q .; git checkout -q -b feat-test
mkdir -p tasks .claude/state .claude/scripts/lib .claude/hooks/.log .claude/templates
cp "$R/.claude/scripts/loop-iteration.sh" .claude/scripts/
cp "$R/.claude/scripts/next-task.sh" .claude/scripts/
cp -r "$R/.claude/scripts/lib" .claude/scripts/
# stub verify.sh so pre-flight passes
printf '#!/usr/bin/env bash\nexit 0\n' > .claude/scripts/verify.sh
cat > tasks/TASKS.md <<'EOF'
## Active
- [ ] T-901 | spec:HOTFIX | phase:1 | priority: normal | created: 2026-06-12 | est: 5m
  summary: sandbox task
  accept: true
  owner: implementer
EOF

out=$(bash .claude/scripts/loop-iteration.sh start --max-iter 1 2>&1); rc=$?
chk "start subcommand" 0 $rc "loop run started" "$out"

out=$(bash .claude/scripts/loop-iteration.sh 2>&1); rc=$?
chk "iteration 1 nominates T-901" 0 $rc "T-901" "$out"

out=$(bash .claude/scripts/loop-iteration.sh 2>&1); rc=$?
chk "iteration 2 refused — max-iter 1" 2 $rc "run budget spent" "$out"

# reset budget; test external-edit stop
bash .claude/scripts/loop-iteration.sh start --max-iter 10 >/dev/null
echo "# human touched this" >> tasks/TASKS.md
out=$(bash .claude/scripts/loop-iteration.sh 2>&1); rc=$?
chk "external TASKS.md edit stops the loop" 2 $rc "edited outside the loop" "$out"
# snapshot refreshed by the stop — next call proceeds
out=$(bash .claude/scripts/loop-iteration.sh 2>&1); rc=$?
chk "after snapshot refresh loop resumes" 0 $rc "T-901" "$out"

# record refreshes snapshot → no false external-edit stop
sed -i '' 's/^- \[ \] T-901/- [x] T-901/' tasks/TASKS.md
bash .claude/scripts/loop-iteration.sh record T-901 progress >/dev/null
out=$(bash .claude/scripts/loop-iteration.sh 2>&1); rc=$?
chk "record-refreshed snapshot: no false stop (backlog now empty rc=1)" 1 $rc "IDEATE" "$out"

cd /; rm -rf "$tmpd" "$g"
echo "----"
echo "loop-meta matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
