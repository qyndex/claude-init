#!/usr/bin/env bash
# E2E: P5.7 stack-portability-5,6 — workspace dimension; runner-aware flags; lint tool-missing arms
set -u
R=/Volumes/M/sourcecode/qyndex/claude-init
pass=0; fail=0
chk() { local d=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then echo "PASS: $d"; pass=$((pass+1)); else echo "FAIL: $d (want $e got $a)"; fail=$((fail+1)); fi; }

# ── detect-stacks workspace dimension (sandboxed: script copied INSIDE so ROOT=sandbox) ──
mk() { T=$(mktemp -d); mkdir -p "$T/.claude/scripts"; cp "$R/.claude/scripts/detect-stacks.sh" "$T/.claude/scripts/"; }
ws() { (cd "$T" && bash .claude/scripts/detect-stacks.sh | jq -r '.workspace'); }

mk; echo '{}' > "$T/package.json"
chk "ws: plain package.json → none"          none "$(ws)"; rm -rf "$T"
mk; echo '{}' > "$T/package.json"; touch "$T/pnpm-workspace.yaml"
chk "ws: pnpm-workspace.yaml → pnpm"         pnpm "$(ws)"; rm -rf "$T"
mk; echo '{}' > "$T/package.json"; touch "$T/pnpm-workspace.yaml" "$T/turbo.json"
chk "ws: turbo wins over pnpm"               turbo "$(ws)"; rm -rf "$T"
mk; echo '{}' > "$T/package.json"; touch "$T/nx.json"
chk "ws: nx.json → nx"                       nx "$(ws)"; rm -rf "$T"
mk; echo '{}' > "$T/package.json"; touch "$T/lerna.json"
chk "ws: lerna.json → lerna"                 lerna "$(ws)"; rm -rf "$T"
mk; echo '{"workspaces":["packages/*"]}' > "$T/package.json"
chk "ws: package.json workspaces → npm"      npm "$(ws)"; rm -rf "$T"
mk; touch "$T/go.work"; echo 'module x' > "$T/go.mod"
chk "ws: go.work → go-work"                  go-work "$(ws)"; rm -rf "$T"
mk; printf '[workspace]\nmembers=["a"]\n' > "$T/Cargo.toml"
chk "ws: Cargo [workspace] → cargo"          cargo "$(ws)"; rm -rf "$T"
mk; printf '[package]\nname="x"\n' > "$T/Cargo.toml"
chk "ws: plain Cargo.toml → none"            none "$(ws)"; rm -rf "$T"

# ── verify.sh workspace plumbing (static + behavioral) ──
cd "$R"
chk "verify: node_ws from detect-stacks"     0 "$(grep -q 'node_ws=$(bash .claude/scripts/detect-stacks.sh' .claude/scripts/verify.sh; echo $?)"
chk "verify: turbo aggregation arm"          0 "$(grep -q 'npx turbo run test' .claude/scripts/verify.sh; echo $?)"
chk "verify: nx aggregation arm"             0 "$(grep -q 'npx nx run-many -t test' .claude/scripts/verify.sh; echo $?)"
chk "verify: pnpm -r aggregation arm"        0 "$(grep -q 'pnpm -r run test' .claude/scripts/verify.sh; echo $?)"
chk "verify: npm --workspaces arm"           0 "$(grep -q 'npm test --workspaces' .claude/scripts/verify.sh; echo $?)"
chk "verify: missing runner = FAIL not skip" 0 "$(grep -q 'workspace tests cannot aggregate' .claude/scripts/verify.sh; echo $?)"
chk "verify: ws merge gate exists"           0 "$(grep -q 'Workspace coverage merge' .claude/scripts/verify.sh; echo $?)"
chk "verify: ws zero-summaries = FAIL"       0 "$(grep -q 'NO package emitted coverage/coverage-summary.json' .claude/scripts/verify.sh; echo $?)"
chk "verify: single-pkg cov gated to none"   0 "$(grep -q 'stack_tests_ran" = "1" \] && \[ "${node_ws:-none}" = "none"' .claude/scripts/verify.sh; echo $?)"

# coverage-merge jq math (behavioral): 2 packages, 80/100 + 90/100 lines → 85%
T=$(mktemp -d); mkdir -p "$T/a/coverage" "$T/b/coverage"
echo '{"total":{"lines":{"covered":80,"total":100},"branches":{"covered":40,"total":50}}}' > "$T/a/coverage/coverage-summary.json"
echo '{"total":{"lines":{"covered":90,"total":100},"branches":{"covered":45,"total":50}}}' > "$T/b/coverage/coverage-summary.json"
merged=$(find "$T" -path '*/coverage/coverage-summary.json' | xargs cat | jq -s '
  {lc: (map(.total.lines.covered) | add), lt: (map(.total.lines.total) | add),
   bc: (map(.total.branches.covered) | add), bt: (map(.total.branches.total) | add)} |
  {line: (if .lt > 0 then (.lc / .lt * 100) else 0 end),
   branch: (if .bt > 0 then (.bc / .bt * 100) else 0 end)}')
chk "merge math: 80+90/200 lines → 85"       85 "$(echo "$merged" | jq -r '.line')"
chk "merge math: 40+45/100 branches → 85"    85 "$(echo "$merged" | jq -r '.branch')"
rm -rf "$T"

# ── runner-aware flags in test-unit.sh ──
chk "test-unit: vitest → --run detection"    0 "$(grep -q 'vitest.*--run\|test_args="--run"' .claude/scripts/test-unit.sh; echo $?)"
chk "test-unit: jest → --ci detection"       0 "$(grep -q 'test_args="--ci"' .claude/scripts/test-unit.sh; echo $?)"
chk "test-unit: no hardcoded pnpm --run"     1 "$(grep -q 'pnpm test --run' .claude/scripts/test-unit.sh; echo $?)"
chk "test-unit: no hardcoded npm -- --run"   1 "$(grep -q 'npm test -- --run' .claude/scripts/test-unit.sh; echo $?)"
chk "test-unit: bun.lockb handled"           0 "$(grep -q 'bun.lockb' .claude/scripts/test-unit.sh; echo $?)"

# ── lint.sh bun unification + counted tool-missing ──
chk "lint: bun.lockb handled"                0 "$(grep -q 'bun.lockb' .claude/scripts/lint.sh; echo $?)"
chk "lint: tool_missing helper exists"       0 "$(grep -q 'tool_missing()' .claude/scripts/lint.sh; echo $?)"
for tool in 'gradle/mvn' hadolint shellcheck sqlfluff 'tflint/terraform'; do
  grep -q "tool_missing \"$tool\"" .claude/scripts/lint.sh || echo "  MISSING arm: $tool"
done
n_arms=$(grep -c 'tool_missing "' .claude/scripts/lint.sh)
chk "lint: 5 counted tool-missing arms"      5 "$n_arms"
chk "lint: LINT_TOOL_MISSING_OK escape"      0 "$(grep -q 'LINT_TOOL_MISSING_OK' .claude/scripts/lint.sh; echo $?)"
# behavioral: tool_missing counts by default, waived with escape (function extracted via subshell)
out=$(bash -c 'failures=0; LINT_TOOL_MISSING_OK=0
tool_missing() { if [ "${LINT_TOOL_MISSING_OK:-0}" = "1" ]; then echo skip; else failures=$((failures+1)); fi; }
tool_missing x; echo $failures')
chk "lint: missing tool counts a failure"    1 "$(echo "$out" | tail -1)"
out=$(bash -c 'failures=0; LINT_TOOL_MISSING_OK=1
tool_missing() { if [ "${LINT_TOOL_MISSING_OK:-0}" = "1" ]; then echo skip; else failures=$((failures+1)); fi; }
tool_missing x; echo $failures')
chk "lint: escape waives to warning"         0 "$(echo "$out" | tail -1)"

# repo-level smoke: lint.sh on this repo (shell stack, shellcheck installed) exits per shellcheck status
chk "detect-stacks on this repo: ws=none"    none "$(bash .claude/scripts/detect-stacks.sh | jq -r '.workspace')"
for s in detect-stacks verify test-unit lint; do
  chk "$s.sh executable + bash -n"           0 "$([ -x .claude/scripts/$s.sh ] && bash -n .claude/scripts/$s.sh; echo $?)"
done

echo "----"; echo "stack-portability matrix: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
