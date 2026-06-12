#!/usr/bin/env bash
# E2E: SWARM_ROOT shared-root (swarm-1) — hooks fired in a worktree must write
# .swarms/** at the MAIN checkout.
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }

main=$(mktemp -d); cd "$main"
git init -q .; git config user.email t@t; git config user.name t
mkdir -p .claude/hooks .claude/scripts/lib .claude/memory/.cache .swarms/streams
cp "$R/verify/2026-06-12-e2e-fixes/staged/.claude/hooks/session-heartbeat.sh" .claude/hooks/
cp "$R/verify/2026-06-12-e2e-fixes/staged/.claude/hooks/post-bash-log.sh" .claude/hooks/
cp "$R/.claude/scripts/lib/swarm-root.sh" .claude/scripts/lib/
cp "$R/.claude/scripts/lib/atomic-write.sh" .claude/scripts/lib/ 2>/dev/null
echo x > f; git add -A; git commit -qm base
git branch -m main

# lib sanity: in main checkout SWARM_ROOT == main root
sr=$(. .claude/scripts/lib/swarm-root.sh; echo "$SWARM_ROOT")
[ "$sr" = "$(pwd -P)" ] && ok "SWARM_ROOT in main checkout = main root" || no "main-root resolve: $sr != $(pwd -P)"

# create a real worktree on feat-77
git worktree add -q -b feat-77 wt-77
# worktree needs the hook + lib (claude -w copies the checkout incl. .claude)
( cd wt-77
  sr=$(. .claude/scripts/lib/swarm-root.sh; echo "$SWARM_ROOT")
  [ "$sr" = "$(cd .. && pwd -P)" ] && ok "SWARM_ROOT inside worktree = main root" || no "worktree resolve: $sr"
)

# fire session-heartbeat inside the worktree → stream state must land in MAIN .swarms
( cd wt-77 && CLAUDE_SESSION_ID=s-77 bash .claude/hooks/session-heartbeat.sh < /dev/null > /dev/null 2>&1 )
if [ -f .swarms/streams/feat-77/state.json ]; then ok "heartbeat wrote stream state at MAIN root"; else no "stream state missing at main root"; fi
if [ -e wt-77/.swarms/streams/feat-77/state.json ]; then no "stream state leaked into worktree"; else ok "no stream-state leak into worktree"; fi

# fire post-bash-log inside the worktree with a failing command → lane.error at MAIN root
printf '{"tool_input":{"command":"bash .claude/scripts/tdd-ledger.sh red T-1"},"tool_response":{"exit_code":0}}' \
  | ( cd wt-77 && bash .claude/hooks/post-bash-log.sh > /dev/null 2>&1 )
if [ -f .swarms/events/feat-77.jsonl ] && grep -q 'lane.red' .swarms/events/feat-77.jsonl; then
  ok "post-bash-log lane event landed at MAIN root"
else
  no "lane event missing at main root"
fi

# non-swarm no-op: hook on main branch writes nothing new under .swarms/events
rm -rf .swarms/events
printf '{"tool_input":{"command":"echo hi"},"tool_response":{"exit_code":0}}' | bash .claude/hooks/post-bash-log.sh > /dev/null 2>&1
[ -d .swarms/events ] && no "non-swarm session emitted lane events" || ok "non-swarm session no-ops cleanly"

cd /; rm -rf "$main"
echo "----"; echo "swarm-root matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
