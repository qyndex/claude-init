#!/usr/bin/env bash
# E2E: P4.7 brownfield-3/4/5 — .github reconcile, backup hygiene + revert, import error capture
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

# ── mini factory clone ──
F=$(mktemp -d)
mkdir -p "$F/.claude/scripts" "$F/.claude/agents" "$F/.github/workflows" "$F/.github/rulesets" "$F/specs/templates" "$F/tasks"
printf "# Constitution\nKarpathy's Four Principles\n" > "$F/.claude/CLAUDE.md"
printf '{"disableBypassPermissionsMode":"disable"}\n' > "$F/.claude/settings.json"
printf '# agent\n' > "$F/.claude/agents/impl.md"
cp "$R/.claude/scripts/reconcile-claude-dir.sh" "$F/.claude/scripts/"
printf 'jobs:\n  evidence-gate:\n    runs-on: ubuntu\n' > "$F/.github/workflows/evidence-gate.yml"
printf 'factory-ci\n' > "$F/.github/workflows/ci.yml"
printf '{"rules":[{"parameters":{"required_status_checks":[{"context":"evidence-gate"}]}}]}\n' > "$F/.github/rulesets/main-protection.json"
printf 'node_modules\n' > "$F/.gitignore"
printf 'spec tpl\n' > "$F/specs/templates/spec.md"
printf '# Tasks\n\n## Active\n\n## Archive\n' > "$F/tasks/TASKS.md"

# ── brownfield target ──
T=$(mktemp -d); cd "$T"
git init -q .; git config user.email t@t; git config user.name t
mkdir -p .claude/memory .github/workflows .husky
printf 'MY OWN CONSTITUTION\n' > .claude/CLAUDE.md
printf '{"my":"settings"}\n' > .claude/settings.local.json
printf 'their knowledge\n' > .claude/memory/notes.md
printf 'target-ci DIFFERENT\n' > .github/workflows/ci.yml
printf 'own workflow\n' > .github/workflows/own.yml
printf 'commitlint -e\n' > .husky/commit-msg
git add -A; git commit -qm base

bash "$F/.claude/scripts/reconcile-claude-dir.sh" --from "$F" --into . >/dev/null 2>&1
ts=$(ls -1 .brownfield-backup | head -1)
BK=".brownfield-backup/$ts"

# brownfield-4: backup + hygiene
chk "backup contains settings.local.json"   0 "$([ -f "$BK/settings.local.json" ]; echo $?)"
chk "backup gitignored at backup time"      0 "$(grep -qxF '.brownfield-backup/' .gitignore; echo $?)"
chk "git does not see the backup"           0 "$(git status --porcelain | grep -q brownfield-backup; [ $? = 1 ] && echo 0 || echo 1)"
chk "MANIFEST.txt written"                  0 "$([ -f "$BK/MANIFEST.txt" ]; echo $?)"
chk "MANIFEST has overwritten CLAUDE.md"    0 "$(grep -q "overwritten	.claude/CLAUDE.md" "$BK/MANIFEST.txt"; echo $?)"
chk "MANIFEST has created evidence-gate"    0 "$(grep -q "created	.github/workflows/evidence-gate.yml" "$BK/MANIFEST.txt"; echo $?)"

# brownfield-3: .github no-clobber + collision map + hook [OQ]
chk "factory workflow created"              0 "$([ -f .github/workflows/evidence-gate.yml ]; echo $?)"
chk "target ci.yml NOT clobbered"           0 "$(grep -q 'target-ci DIFFERENT' .github/workflows/ci.yml; echo $?)"
chk "collision [OQ] in report"              0 "$(grep -q '.github collisions' ADOPTION-REPORT.md; echo $?)"
chk "ci.yml named in collision map"         0 "$(grep -q '.github/workflows/ci.yml' ADOPTION-REPORT.md; echo $?)"
chk "husky coexistence [OQ] in report"      0 "$(grep -q 'Git-hook coexistence' ADOPTION-REPORT.md; echo $?)"
chk "factory governs: agents copied"        0 "$([ -f .claude/agents/impl.md ]; echo $?)"
chk "their memory preserved"                0 "$(grep -q 'their knowledge' .claude/memory/notes.md; echo $?)"

# brownfield-4: revert
bash "$F/.claude/scripts/reconcile-claude-dir.sh" --revert "$ts" --into . >/dev/null 2>&1
chk "revert: original CLAUDE.md restored"   0 "$(grep -q 'MY OWN CONSTITUTION' .claude/CLAUDE.md; echo $?)"
chk "revert: created workflow deleted"      1 "$([ -e .github/workflows/evidence-gate.yml ]; echo $?)"
chk "revert: created scaffold deleted"      1 "$([ -e specs/templates/spec.md ]; echo $?)"
chk "revert: repo's own workflow kept"      0 "$([ -f .github/workflows/own.yml ]; echo $?)"
chk "revert: no stray MANIFEST in .claude"  1 "$([ -e .claude/MANIFEST.txt ]; echo $?)"
cd /; rm -rf "$T"

# ── greenfield fast-path: no .claude, but own .github ──
T=$(mktemp -d); cd "$T"
git init -q .; mkdir -p .github/workflows
printf 'mine\n' > .github/workflows/ci.yml
bash "$F/.claude/scripts/reconcile-claude-dir.sh" --from "$F" --into . > out.log 2>&1
chk "greenfield: .claude copied"            0 "$([ -f .claude/CLAUDE.md ]; echo $?)"
chk "greenfield: factory gate added"        0 "$([ -f .github/workflows/evidence-gate.yml ]; echo $?)"
chk "greenfield: own ci.yml kept + flagged" 0 "$(grep -q 'mine' .github/workflows/ci.yml && grep -q '\[OQ\] .github/workflows/ci.yml' out.log; echo $?)"
cd /; rm -rf "$T"

# ── brownfield-5: import-issues-once error capture (stub gh) ──
T=$(mktemp -d); cd "$T"
git init -q .; git config user.email t@t; git config user.name t
mkdir -p .claude/scripts/lib .claude/state/adopt tasks bin
cp "$R/.claude/scripts/import-issues-once.sh" .claude/scripts/
cp -R "$R/.claude/scripts/lib/." .claude/scripts/lib/
cat > bin/gh <<'GH'
#!/bin/bash
case "$1" in
  auth) exit "${GH_AUTH_RC:-0}" ;;
  issue)
    [ "${GH_LIST_RC:-0}" != 0 ] && { echo "HTTP 401: Bad credentials" >&2; exit "$GH_LIST_RC"; }
    case "$*" in
      *"--state open"*)   echo '[{"number":7,"title":"Fix login","labels":[{"name":"bug"}]},{"number":9,"title":"Add export","labels":[]}]' ;;
      *"--state closed"*) echo '[{"number":3,"title":"Old one","closedAt":"2024-01-01T00:00:00Z"}]' ;;
    esac ;;
  *) exit 0 ;;
esac
GH
chmod +x bin/gh
export PATH="$T/bin:$PATH"
SENT=.claude/state/adopt/issues-imported.done

out=$(GH_AUTH_RC=1 bash .claude/scripts/import-issues-once.sh 2>&1); rc=$?
chk "import: unauthenticated gh → exit 1"     1 "$rc"
chk "import: no sentinel on auth failure"     1 "$([ -e "$SENT" ]; echo $?)"
out=$(GH_LIST_RC=1 bash .claude/scripts/import-issues-once.sh 2>&1); rc=$?
chk "import: failed list → exit 1, loud"      0 "$([ $rc = 1 ] && echo "$out" | grep -q 'NOT writing the sentinel'; echo $?)"
chk "import: no sentinel on read failure"     1 "$([ -e "$SENT" ]; echo $?)"
chk "import: no tasks created on failure"     1 "$(grep -q 'imported_from_issue' tasks/TASKS.md 2>/dev/null; echo $?)"
out=$(bash .claude/scripts/import-issues-once.sh 2>&1); rc=$?
chk "import: success → exit 0"                0 "$rc"
chk "import: 2 open issues → tasks"           2 "$(grep -c 'imported_from_issue' tasks/TASKS.md)"
chk "import: sentinel written on success"     0 "$([ -f "$SENT" ]; echo $?)"
chk "import: re-run refused (sentinel)"       1 "$(bash .claude/scripts/import-issues-once.sh >/dev/null 2>&1; echo $?)"
cd /; rm -rf "$T"

# ── /adopt auto refuses Phase-3 approve on import failure; handoff gate check ──
T=$(mktemp -d); cd "$T"
git init -q .; git config user.email t@t; git config user.name t
mkdir -p .claude/scripts/lib .claude/state .github/rulesets .github/workflows tasks bin
cp "$R/.claude/scripts/import-issues-once.sh" "$R/.claude/scripts/adopt-state.sh" .claude/scripts/
cp -R "$R/.claude/scripts/lib/." .claude/scripts/lib/
sed -n '/^```bash$/,/^```$/p' "$R/.claude/commands/adopt.md" | sed '1d;$d' > adopt.sh
cat > bin/gh <<'GH'
#!/bin/bash
case "$1" in
  auth) exit "${GH_AUTH_RC:-0}" ;;
  issue) [ "${GH_LIST_RC:-0}" != 0 ] && { echo "boom" >&2; exit "$GH_LIST_RC"; }; echo '[]' ;;
  *) exit 0 ;;
esac
GH
chmod +x bin/gh
export PATH="$T/bin:$PATH"
S=.claude/scripts/adopt-state.sh
bash "$S" init . >/dev/null; bash "$S" set 1 archaeology >/dev/null
touch .claude/state/allow-adopt-approve; bash "$S" approve 1 >/dev/null

out=$(GH_LIST_RC=1 bash adopt.sh auto 2>&1); rc=$?
chk "auto: halts on import failure (rc=1)"    1 "$rc"
chk "auto: prints AUTO HALTED"                0 "$(echo "$out" | grep -q 'AUTO HALTED'; echo $?)"
chk "auto: phase 3 NOT approved"              1 "$(bash "$S" gate 3 >/dev/null 2>&1; echo $?)"
out=$(bash adopt.sh auto 2>&1); rc=$?
chk "auto: retry succeeds → gate 4 pause"     0 "$([ $rc = 0 ] && echo "$out" | grep -q 'SAFETY GATE 4'; echo $?)"
chk "auto: phase 3 approved after retry"      0 "$(bash "$S" gate 3 >/dev/null 2>&1; echo $?)"

# handoff gate verification: ruleset names a check with no workflow job
printf '{"rules":[{"parameters":{"required_status_checks":[{"context":"evidence-gate"}]}}]}\n' > .github/rulesets/main-protection.json
touch .claude/state/allow-adopt-approve
bash "$S" set 4 baseline >/dev/null; bash "$S" approve 4 >/dev/null
bash "$S" set 5 backlog  >/dev/null; bash "$S" approve 5 >/dev/null
out=$(bash adopt.sh handoff 2>&1); rc=$?
chk "handoff: refuses when required check unmapped" 1 "$rc"
chk "handoff: names the missing check"              0 "$(echo "$out" | grep -q "required check .evidence-gate. has NO workflow"; echo $?)"
printf 'on:\n  pull_request:\njobs:\n  evidence-gate:\n    runs-on: ubuntu\n' > .github/workflows/evidence-gate.yml
out=$(bash adopt.sh handoff 2>&1); rc=$?
chk "handoff: completes once gate mapped"           0 "$([ $rc = 0 ] && echo "$out" | grep -q 'Adoption complete'; echo $?)"
cd /; rm -rf "$T" "$F"

echo "----"; echo "adopt-completeness matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
