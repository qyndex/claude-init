#!/usr/bin/env bash
# E2E: verified-merge.sh — stub-claude continuation fix + PR lifecycle (swarm-2/3/4)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }

g=$(mktemp -d); cd "$g"
git init -q .; git config user.email t@t; git config user.name t
echo base > f; git add -A; git commit -qm base; git branch -m main; git remote add origin "$PWD"; git fetch -q origin

mkdir -p .claude/scripts .claude/hooks/.log .swarms/coordinator .claude/worktrees stubbin
cp "$R/.claude/scripts/verified-merge.sh" .claude/scripts/

# stub claude: record argv + stdin state
cat > stubbin/claude <<'EOF'
#!/usr/bin/env bash
printf 'ARGV:' > /tmp/vm-claude-argv
for a in "$@"; do printf ' [%s]' "$a" >> /tmp/vm-claude-argv; done
echo >> /tmp/vm-claude-argv
if [ -t 0 ]; then echo "STDIN:tty" >> /tmp/vm-claude-argv; else echo "STDIN:pipe-or-null" >> /tmp/vm-claude-argv; fi
echo "stub mediation output"
exit 0
EOF
# stub gh: record subcommands; pr view fails (no PR), create/checks/merge succeed
cat > stubbin/gh <<'EOF'
#!/usr/bin/env bash
echo "GH: $*" >> /tmp/vm-gh-calls
case "$1 $2" in
  "pr view") exit 1 ;;
  *) exit 0 ;;
esac
EOF
# stub verify.sh: fail FIRST call (trigger mediation), pass afterwards
cat > .claude/scripts/verify.sh <<'EOF'
#!/usr/bin/env bash
n=$(cat /tmp/vm-verify-count 2>/dev/null || echo 0)
n=$((n+1)); echo $n > /tmp/vm-verify-count
[ "$n" -le 1 ] && exit 1
exit 0
EOF
chmod +x stubbin/claude stubbin/gh .claude/scripts/verify.sh
rm -f /tmp/vm-claude-argv /tmp/vm-gh-calls /tmp/vm-verify-count

# worktree for the stream
git worktree add -q -b feat-9 .claude/worktrees/feat-9
printf '{"fleet":{"feat-9":{"branch":"feat-9","status":"running","worktree":".claude/worktrees/feat-9"}}}\n' > .swarms/coordinator/fleet.json

PATH="$PWD/stubbin:$PATH" bash .claude/scripts/verified-merge.sh feat-9 > /tmp/vm-out 2>&1
rc=$?
[ "$rc" = 0 ] && ok "verified-merge completes (rc=0)" || no "verified-merge rc=$rc: $(tail -3 /tmp/vm-out)"

# THE swarm-2 assertion: stub claude received the positional prompt as argv
if grep -q '\[Fix the integration failure for stream feat-9\]' /tmp/vm-claude-argv 2>/dev/null; then
  ok "mediation prompt arrived as argv (continuation fixed)"
else
  no "mediation prompt missing from argv: $(cat /tmp/vm-claude-argv 2>/dev/null)"
fi
# stdout landed in the log, not the console
log=$(ls .claude/hooks/.log/verified-merge-feat-9-*.log | head -1)
grep -q 'stub mediation output' "$log" && ok "claude stdout captured in log" || no "claude stdout not in log"

# swarm-3: PR lifecycle — create + checks --watch before merge
grep -q 'pr create --fill' /tmp/vm-gh-calls && ok "gh pr create called when no PR exists" || no "no pr create"
grep -q 'pr checks feat-9 --watch --fail-fast' /tmp/vm-gh-calls && ok "gh pr checks --watch gates the merge" || no "no checks watch"
grep -q 'pr merge feat-9 --squash' /tmp/vm-gh-calls && ok "gh pr merge after checks" || no "no merge"
# ordering: create < checks < merge
order_ok=$(awk '/pr create/{c=NR} /pr checks/{k=NR} /pr merge/{m=NR} END{print (c<k && k<m) ? "yes" : "no"}' /tmp/vm-gh-calls)
[ "$order_ok" = yes ] && ok "lifecycle order create→checks→merge" || no "lifecycle order wrong"

# swarm-4: success teardown removed the worktree
[ ! -d .claude/worktrees/feat-9 ] && ok "worktree removed on success" || no "worktree still present"

# exit 41 path: failing checks must escalate, not merge
rm -f /tmp/vm-gh-calls /tmp/vm-verify-count
cat > stubbin/gh <<'EOF'
#!/usr/bin/env bash
echo "GH: $*" >> /tmp/vm-gh-calls
case "$1 $2" in
  "pr view") exit 0 ;;
  "pr checks") exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x stubbin/gh
echo 2 > /tmp/vm-verify-count   # verify passes immediately
git worktree add -q -b feat-8 .claude/worktrees/feat-8
printf '{"fleet":{"feat-8":{"branch":"feat-8","status":"running","worktree":".claude/worktrees/feat-8"}}}\n' > .swarms/coordinator/fleet.json
PATH="$PWD/stubbin:$PATH" bash .claude/scripts/verified-merge.sh feat-8 > /tmp/vm-out2 2>&1
rc=$?
[ "$rc" = 41 ] && ok "red PR checks escalate with exit 41" || no "expected 41, got $rc"
grep -q 'pr merge' /tmp/vm-gh-calls && no "merged around red checks!" || ok "no merge around red checks"

cd /; rm -rf "$g" /tmp/vm-claude-argv /tmp/vm-gh-calls /tmp/vm-verify-count /tmp/vm-out /tmp/vm-out2
echo "----"; echo "verified-merge matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
