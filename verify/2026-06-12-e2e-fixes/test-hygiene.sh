#!/usr/bin/env bash
# E2E: P5.3 failure-recovery-5,6 — gc-logs jsonl + offset reset; requeue lock rc + flip re-grep
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

# ── gc-logs: jsonl rotation + instinct offset reset ──
T=$(mktemp -d); cd "$T"
mkdir -p .claude/scripts/lib .claude/hooks/.log .claude/memory/.cache/instincts .swarms/streams/feat-1
cp "$R/.claude/scripts/gc-logs.sh" .claude/scripts/
seq 1 200 | sed 's/.*/{"obs":&}/' > .claude/memory/.cache/instincts/observations.jsonl
printf '150\n' > .claude/memory/.cache/.instinct-extract.state
printf '{"e":1}\n' > .swarms/streams/feat-1/lane-events.jsonl
printf 'small\n' > .claude/hooks/.log/tiny.log

out=$(GC_LOG_MAX_BYTES=100 bash .claude/scripts/gc-logs.sh)
chk "gc: oversized observations.jsonl rotated"  0 "$([ -f .claude/memory/.cache/instincts/observations.jsonl.1 ] && [ ! -s .claude/memory/.cache/instincts/observations.jsonl ]; echo $?)"
chk "gc: instinct offset reset to 0"            0 "$([ "$(cat .claude/memory/.cache/.instinct-extract.state)" = "0" ]; echo $?)"
chk "gc: under-cap jsonl untouched"             0 "$([ -s .swarms/streams/feat-1/lane-events.jsonl ] && [ ! -f .swarms/streams/feat-1/lane-events.jsonl.1 ]; echo $?)"
chk "gc: under-cap log untouched"               0 "$([ ! -f .claude/hooks/.log/tiny.log.1 ]; echo $?)"
# oversized swarm jsonl also rotates
seq 1 500 | sed 's/.*/{"e":&}/' > .swarms/streams/feat-1/lane-events.jsonl
GC_LOG_MAX_BYTES=100 bash .claude/scripts/gc-logs.sh >/dev/null
chk "gc: swarm lane jsonl rotated"              0 "$([ -f .swarms/streams/feat-1/lane-events.jsonl.1 ]; echo $?)"
cd /; rm -rf "$T"

# factory rig still green
out=$(bash "$R/.claude/scripts/test/gc-suite.sh" 2>&1 | tail -2)
chk "gc: existing gc-suite still green" 0 "$(echo "$out" | grep -q 'failed: 0'; echo $?)"

# ── requeue-failed: lock rc + flip verification ──
T=$(mktemp -d); cd "$T"
mkdir -p .claude/scripts/lib .claude/state/locks tasks
cp "$R/.claude/scripts/requeue-failed.sh" .claude/scripts/
cp -R "$R/.claude/scripts/lib/." .claude/scripts/lib/
printf '# Tasks\n\n## Active\n\n- [!] T-7  | priority: normal  | created: 2026-06-01  | last_touched: 2026-06-01\n  summary: broken thing\n  accept: true\n  owner: @implementer\n\n## Archive\n' > tasks/TASKS.md

# busy lock (live holder) → exit 75, no flip, no ✓
mkdir -p .claude/state/locks/tasks.lock
printf '%s\n' "$$" > .claude/state/locks/tasks.lock/pid
out=$(LOCK_WAIT_S=1 bash .claude/scripts/requeue-failed.sh --reset T-7 2>&1); rc=$?
chk "requeue: busy lock → exit 75"          75 "$rc"
chk "requeue: busy → no false ✓"            1 "$(echo "$out" | grep -q '✓'; echo $?)"
chk "requeue: busy → task still [!]"        0 "$(grep -q '^- \[!\] T-7' tasks/TASKS.md; echo $?)"
rm -rf .claude/state/locks/tasks.lock

# normal reset works + ✓ printed only after re-grep
out=$(bash .claude/scripts/requeue-failed.sh --reset T-7 2>&1); rc=$?
chk "requeue: reset flips [!] → [ ]"        0 "$([ $rc = 0 ] && grep -q '^- \[ \] T-7' tasks/TASKS.md; echo $?)"
chk "requeue: ✓ printed on verified flip"   0 "$(echo "$out" | grep -q '✓ Re-opened T-7'; echo $?)"
cd /; rm -rf "$T"

# staged session-end backstop + doctor check
cd "$R"
chk "session-end (staged): gc backstop wired" 0 "$(grep -q 'gc-logs.sh' verify/2026-06-12-e2e-fixes/staged/.claude/hooks/session-end.sh; echo $?)"
chk "doctor: runtime log size check"          0 "$(bash .claude/scripts/harness-doctor.sh 2>/dev/null | grep -q 'runtime log size'; echo $?)"

echo "----"; echo "hygiene matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
