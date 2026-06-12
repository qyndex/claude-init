#!/usr/bin/env bash
# E2E: pre-lane-guard.sh (swarm-5/6)
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want rc=$e got=$a)"; fail=$((fail+1)); fi; }

main=$(mktemp -d); cd "$main"
git init -q .; git config user.email t@t; git config user.name t
mkdir -p .claude/hooks .claude/scripts/lib .swarms/streams/feat-5
cp "$R/verify/2026-06-12-e2e-fixes/staged/.claude/hooks/pre-lane-guard.sh" .claude/hooks/
cp "$R/.claude/scripts/lib/swarm-root.sh" .claude/scripts/lib/
echo x > f; git add -A; git commit -qm b; git branch -m main
printf '{"files_owned":["src/auth/*","docs/auth.md"],"files_shared":["src/shared/api.ts"]}\n' > .swarms/streams/feat-5/task.json

git worktree add -q -b feat-5 wt5
run() { # run <path> -> rc   (from inside worktree)
  printf '{"tool_input":{"file_path":"%s"}}' "$1" | ( cd wt5 && bash .claude/hooks/pre-lane-guard.sh >/dev/null 2>&1 ); echo $?
}

chk "owned glob allowed (src/auth/login.ts)"        0 "$(run src/auth/login.ts)"
chk "owned literal allowed (docs/auth.md)"          0 "$(run docs/auth.md)"
chk "out-of-lane write BLOCKED (src/billing/x.ts)"  2 "$(run src/billing/x.ts)"
chk "shared file BLOCKED (src/shared/api.ts)"       2 "$(run src/shared/api.ts)"
chk "own stream state allowed"                      0 "$(run .swarms/streams/feat-5/handoff-1.yaml)"
chk "test file allowed (TDD beside owned code)"     0 "$(run src/auth/login.test.ts)"
chk "evidence dir allowed"                          0 "$(run verify/2026-06-12-f/EVIDENCE.md)"
chk "LANE_GUARD=0 escape"                           0 "$(printf '{"tool_input":{"file_path":"src/billing/x.ts"}}' | ( cd wt5 && LANE_GUARD=0 bash .claude/hooks/pre-lane-guard.sh >/dev/null 2>&1 ); echo $?)"

# non-swarm branch: no-op even for out-of-lane paths
rc=$(printf '{"tool_input":{"file_path":"src/billing/x.ts"}}' | bash .claude/hooks/pre-lane-guard.sh >/dev/null 2>&1; echo $?)
chk "main-branch session no-ops" 0 "$rc"

# no files_owned declared → no guard
printf '{"files_owned":[],"files_shared":[]}\n' > .swarms/streams/feat-5/task.json
chk "empty allocation = no lane to guard" 0 "$(run src/billing/x.ts)"

cd /; rm -rf "$main"
echo "----"; echo "lane-guard matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
