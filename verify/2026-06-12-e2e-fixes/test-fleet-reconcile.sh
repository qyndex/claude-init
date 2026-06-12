#!/usr/bin/env bash
# E2E: fleet-reconcile.sh (swarm-4)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }

g=$(mktemp -d); cd "$g"
git init -q .
mkdir -p .claude/scripts .swarms/coordinator .swarms/streams/feat-1 .swarms/streams/feat-2 stubbin
cp "$R/.claude/scripts/fleet-reconcile.sh" .claude/scripts/
cp "$R/.claude/scripts/swarm-respawn.sh" .claude/scripts/
cat > .swarms/coordinator/fleet.json <<'EOF'
{"fleet":{
  "feat-1":{"sessionId":"sess-live","status":"running","worktree":".claude/worktrees/feat-1","branch":"feat-1"},
  "feat-2":{"sessionId":"sess-dead","status":"running","worktree":".claude/worktrees/feat-2","branch":"feat-2"},
  "feat-3":{"sessionId":"sess-x","status":"merged","worktree":".claude/worktrees/feat-3","branch":"feat-3"}
}}
EOF

# stub claude: agents --json reports only sess-live; respawn fails; --bg returns a new sid
cat > stubbin/claude <<'EOF'
#!/usr/bin/env bash
case "$1" in
  agents) echo '[{"session_id":"sess-live"}]' ;;
  respawn) exit 1 ;;
  --bg) echo '{"session_id":"sess-new"}' ;;
esac
exit 0
EOF
chmod +x stubbin/claude
export PATH="$PWD/stubbin:$PATH"

# dry run touches nothing
out=$(bash .claude/scripts/fleet-reconcile.sh --dry-run 2>&1)
printf '%s' "$out" | grep -q 'DRY: feat-2' && ok "dry-run flags only the vanished stream" || no "dry-run: $out"
[ "$(jq -r '.fleet["feat-2"].status' .swarms/coordinator/fleet.json)" = running ] && ok "dry-run mutates nothing" || no "dry-run mutated fleet"

# real run marks feat-2 crashed, leaves feat-1 running
out=$(bash .claude/scripts/fleet-reconcile.sh 2>&1)
[ "$(jq -r '.fleet["feat-2"].status' .swarms/coordinator/fleet.json)" = crashed ] && ok "vanished session marked crashed" || no "feat-2 not crashed: $out"
[ "$(jq -r '.fleet["feat-1"].status' .swarms/coordinator/fleet.json)" = running ] && ok "live session untouched" || no "feat-1 mutated"
grep -q 'feat-2.*CRASHED' .swarms/coordinator/decisions.log && ok "decisions.log entry written" || no "no decisions.log entry"

# --respawn path: reset feat-2 to running, rerun with respawn
jq '.fleet["feat-2"].status = "running"' .swarms/coordinator/fleet.json > f.tmp && mv f.tmp .swarms/coordinator/fleet.json
out=$(bash .claude/scripts/fleet-reconcile.sh --respawn 2>&1)
[ "$(jq -r '.fleet["feat-2"].status' .swarms/coordinator/fleet.json)" = respawned ] && ok "--respawn relaunched the crashed stream" || no "respawn: $(jq -c .fleet .swarms/coordinator/fleet.json) / $out"
[ "$(jq -r '.fleet["feat-2"].sessionId' .swarms/coordinator/fleet.json)" = sess-new ] && ok "new session id recorded atomically" || no "session id not updated"

# daemon unreachable → refuse, touch nothing
cat > stubbin/claude <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x stubbin/claude
jq '.fleet["feat-1"].status = "running"' .swarms/coordinator/fleet.json > f.tmp && mv f.tmp .swarms/coordinator/fleet.json
out=$(bash .claude/scripts/fleet-reconcile.sh 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'refusing to reconcile' && ok "unreachable daemon: fail-safe refusal" || no "refusal: rc=$rc $out"
[ "$(jq -r '.fleet["feat-1"].status' .swarms/coordinator/fleet.json)" = running ] && ok "fail-safe left fleet untouched" || no "fail-safe mutated fleet"

cd /; rm -rf "$g"
echo "----"; echo "fleet-reconcile matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
