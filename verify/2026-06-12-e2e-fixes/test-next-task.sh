#!/usr/bin/env bash
# E2E matrix for next-task.sh (spec-pipeline-2 + tdd-loop-3)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
NT="$R/.claude/scripts/next-task.sh"
tmpd=$(mktemp -d)
pass=0; fail=0
chk() { # chk <desc> <expected-rc> <actual-rc> <expected-substr> <output>
  local desc=$1 erc=$2 arc=$3 sub=$4 out=$5
  if [ "$arc" = "$erc" ] && { [ -z "$sub" ] || printf '%s' "$out" | grep -qF "$sub"; }; then
    echo "PASS: $desc"; pass=$((pass+1))
  else
    echo "FAIL: $desc (rc=$arc want=$erc; out=$out)"; fail=$((fail+1))
  fi
}

F="$tmpd/TASKS.md"

# ── Case 1: template line only (Format section) → backlog empty, NOT the template
cat > "$F" <<'EOF'
# Tasks
## Format
```
- [ ] T-NNN  | spec:NNN  | phase:N  | priority: <P>
```
## Active
EOF
out=$(TASKS_FILE="$F" bash "$NT" 2>&1); rc=$?
chk "template line never nominated" 1 $rc "no pending tasks" "$out"

# ── Case 2: priority ordering — normal listed first in file, hotfix later wins
cat > "$F" <<'EOF'
## Active
- [ ] T-201 | spec:009 | phase:1 | priority: normal | created: 2026-06-12 | est: 5m
  summary: normal task listed first
  accept: true
  owner: implementer
- [ ] T-202 | spec:HOTFIX | phase:1 | priority: hotfix | created: 2026-06-12 | est: 5m
  summary: hotfix task listed second
  accept: true
  owner: implementer
EOF
out=$(TASKS_FILE="$F" bash "$NT" 2>&1); rc=$?
chk "hotfix outranks earlier normal" 0 $rc "T-202" "$out"

# ── Case 3: unmet dep skipped, met dep eligible
cat > "$F" <<'EOF'
## Active
- [x] T-300 | spec:009 | phase:1 | priority: normal | created: 2026-06-12 | est: 5m
  summary: done dep
  accept: true
  owner: implementer
- [ ] T-301 | spec:009 | phase:1 | priority: normal | created: 2026-06-12 | deps: T-300, T-302 | est: 5m
  summary: blocked by T-302
  accept: true
  owner: implementer
- [ ] T-303 | spec:009 | phase:1 | priority: normal | created: 2026-06-12 | deps: T-300 | est: 5m
  summary: dep satisfied
  accept: true
  owner: implementer
EOF
out=$(TASKS_FILE="$F" bash "$NT" 2>&1); rc=$?
chk "unmet dep skipped, satisfied dep picked" 0 $rc "T-303" "$out"
out=$(TASKS_FILE="$F" bash "$NT" --json 2>&1)
chk "blocked-by-dep reported in json" 0 $? "blocked-by-dep:T-302" "$out"

# ── Case 4: operator-owned RESOLVE line skipped
cat > "$F" <<'EOF'
## Active
- [ ] RESOLVE: specs/active/007 open question OQ-1 | priority: P1-spec | created: 2026-06-12
  summary: operator escalation
  owner: operator
- [ ] T-401 | spec:009 | phase:1 | priority: normal | created: 2026-06-12 | est: 5m
  summary: agent task
  accept: true
  owner: implementer
EOF
out=$(TASKS_FILE="$F" bash "$NT" 2>&1); rc=$?
chk "RESOLVE/operator line skipped" 0 $rc "T-401" "$out"

# ── Case 5: all blocked → exit 3
cat > "$F" <<'EOF'
## Active
- [ ] T-501 | spec:009 | phase:1 | priority: normal | created: 2026-06-12 | deps: T-999 | est: 5m
  summary: forever blocked
  accept: true
  owner: implementer
EOF
out=$(TASKS_FILE="$F" bash "$NT" 2>&1); rc=$?
chk "all-blocked exits 3" 3 $rc "blocked-by-dep:T-999" "$out"

# ── Case 6: owner @operator variant skipped
cat > "$F" <<'EOF'
## Active
- [ ] T-601 | spec:009 | phase:1 | priority: hotfix | created: 2026-06-12 | est: 5m
  summary: human-only hotfix
  accept: true
  owner: @operator
- [ ] T-602 | spec:009 | phase:1 | priority: cleanup | created: 2026-06-12 | est: 5m
  summary: agent cleanup
  accept: true
  owner: implementer
EOF
out=$(TASKS_FILE="$F" bash "$NT" 2>&1); rc=$?
chk "@operator owner skipped even at hotfix priority" 0 $rc "T-602" "$out"

# ── Case 7: --require-analyze gates on marker; HOTFIX exempt
cat > "$F" <<'EOF'
## Active
- [ ] T-701 | spec:042 | phase:1 | priority: normal | created: 2026-06-12 | est: 5m
  summary: spec 042 task no marker
  accept: true
  owner: implementer
- [ ] T-702 | spec:HOTFIX | phase:1 | priority: deprecation | created: 2026-06-12 | est: 5m
  summary: hotfix exempt from analyze gate
  accept: true
  owner: implementer
EOF
out=$(TASKS_FILE="$F" bash "$NT" --require-analyze 2>&1); rc=$?
chk "analyze gate skips unanalyzed spec, HOTFIX exempt" 0 $rc "T-702" "$out"
# marker with verdict PASS → eligible again
mkdir -p "$R/.claude/state"
echo '{"verdict":"PASS","blockers":[],"date":"2026-06-12"}' > "$R/.claude/state/analyze-042.json"
out=$(TASKS_FILE="$F" bash "$NT" --require-analyze 2>&1); rc=$?
chk "analyze marker PASS unblocks" 0 $rc "T-701" "$out"
echo '{"verdict":"BLOCK","blockers":["x"],"date":"2026-06-12"}' > "$R/.claude/state/analyze-042.json"
out=$(TASKS_FILE="$F" bash "$NT" --require-analyze 2>&1); rc=$?
chk "analyze verdict BLOCK re-blocks" 0 $rc "T-702" "$out"
rm -f "$R/.claude/state/analyze-042.json"

# ── Case 8: --all lists in priority order
cat > "$F" <<'EOF'
## Active
- [ ] T-801 | spec:009 | phase:1 | priority: cleanup | created: 2026-06-12 | est: 5m
  summary: c
  accept: true
  owner: implementer
- [ ] T-802 | spec:009 | phase:1 | priority: security | created: 2026-06-12 | est: 5m
  summary: s
  accept: true
  owner: implementer
EOF
out=$(TASKS_FILE="$F" bash "$NT" --all 2>&1); rc=$?
first=$(printf '%s' "$out" | head -1)
chk "--all orders security before cleanup" 0 $rc "" "$out"
case "$first" in T-802*) echo "PASS: --all first row is T-802"; pass=$((pass+1));; *) echo "FAIL: --all first row: $first"; fail=$((fail+1));; esac

# ── Case 9: live repo TASKS.md — must NOT nominate the template
out=$(bash "$NT" 2>&1); rc=$?
chk "live TASKS.md: template never nominated (backlog empty or real id)" $rc $rc "" "$out"
case "$out" in *T-NNN*) echo "FAIL: live run nominated the template line"; fail=$((fail+1));; *) echo "PASS: live run free of T-NNN"; pass=$((pass+1));; esac

echo "----"
echo "next-task.sh matrix: $pass pass / $fail fail"
rm -rf "$tmpd"
[ "$fail" -eq 0 ]
