#!/usr/bin/env bash
# M-07-guard + M-06b — reverse-drift detector + merge-boundary STATE writer.
#
# Reverse drift = shipped work marked unshipped: a merged commit carries a
# `Task: T-NNN` trailer (commit_protocol §VI) whose referenced task is STILL
# `[ ]` (pending) in tasks/TASKS.md. The 2026-07 memory audit found spec-004
# stuck `[ ]` for 6 weeks after PR #13 shipped it, with NO detection. This test
# proves reverse-drift-check.sh flags that class (advisory, exit 0) and that the
# staged push:main workflow patch is triggered correctly + wires the third
# initiative-state.sh sync writer site (M-06b).
#
# Auto-covered by the M-00 directory-glob CI runner.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

CHECK=.claude/scripts/reverse-drift-check.sh
PATCH=.claude/memory.proposed/patches/M-07-guard-reverse-drift.patch

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - FAIL: $1"; fi; }

# ── Hermetic temp git repo: a fixture TASKS.md + commits carrying trailers ────
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
(
  cd "$tmp"
  git init -q
  git config user.email t@t.t; git config user.name t
  mkdir -p tasks
  cat > tasks/TASKS.md <<'EOF'
# Tasks

- [ ] T-8  | template placeholder line (never a real task)
- [ ] T-901  | spec:099  | phase:1  | priority: high  | created: 2026-07-23  | last_touched: 2026-07-23  | deps:  | parallel: no  | est: 5m  | accept: bash x.sh  | summary: does a thing
- [s] T-902  | spec:099  | phase:1  | priority: high  | created: 2026-07-23  | last_touched: 2026-07-23  | deps:  | parallel: no  | est: 5m
- [x] T-903  | spec:099  | phase:1  | priority: high  | created: 2026-07-23  | last_touched: 2026-07-23  | deps:  | parallel: no  | est: 5m
EOF
  git add tasks/TASKS.md
  git commit -q -m "chore: seed tasks"
  # A merged commit that SHIPPED T-901 while it is still [ ] → reverse drift.
  echo a > a.txt; git add a.txt
  git commit -q -m "feat(x): ship the thing

Body.

Task: T-901"
  # A merged commit that shipped T-902 ([s]) and T-903 ([x]) — correct, not drift.
  echo b > b.txt; git add b.txt
  git commit -q -m "feat(y): ship more

Task: T-902, T-903"
) >/dev/null 2>&1

# ── (1) reverse-drift-check.sh flags T-901 (pending but shipped), advisory ────
out="$( cd "$tmp" && REVERSE_DRIFT_SINCE=HEAD~2 bash "$ROOT/$CHECK" 2>&1 )"
rc=$?
check "reverse-drift-check.sh exits 0 (advisory, never non-zero)" "$rc"

printf '%s\n' "$out" | grep -qw 'T-901'
check "flags T-901 (shipped commit, task still [ ])" $?

# ── (2) [s] and [x] tasks with trailers are NOT flagged (shipped is correct) ──
if printf '%s\n' "$out" | grep -qw 'T-902'; then
  check "does NOT flag T-902 ([s] shipped — correct)" 1
else
  check "does NOT flag T-902 ([s] shipped — correct)" 0
fi
if printf '%s\n' "$out" | grep -qw 'T-903'; then
  check "does NOT flag T-903 ([x] done — correct)" 1
else
  check "does NOT flag T-903 ([x] done — correct)" 0
fi

# ── (3) accept:/summary: secondary signal is captured for the flagged task ────
printf '%s\n' "$out" | grep -qiE 'accept|summary'
check "reports accept:/summary: presence as a secondary signal" $?

# ── (4) staged workflow patch triggers on push:main only, NOT pull_request ────
if [ -f "$PATCH" ]; then
  check "M-07-guard workflow patch present" 0

  # The patch is a unified diff that CREATES .github/workflows/reverse-drift.yml.
  grep -qE '^\+\+\+ .*/.github/workflows/reverse-drift\.yml' "$PATCH"
  check "patch creates .github/workflows/reverse-drift.yml" $?

  # git apply --check must pass (patch is well-formed against the tree).
  # It must not already exist (guarded file — agent never wrote it directly).
  if [ ! -e .github/workflows/reverse-drift.yml ]; then
    git apply --check "$PATCH" 2>/dev/null
    check "patch applies cleanly (git apply --check)" $?
  else
    check "reverse-drift.yml is a staged patch, not a direct write" 1
  fi

  # Extract only the ADDED workflow body (lines the patch inserts) and inspect
  # it. Drop the `+++ b/...` file header FIRST (fixed-string, not regex — the
  # `+++`/`++` forms are invalid regex quantifiers under some greps), then strip
  # the single leading `+` from real added lines.
  added="$(grep -E '^\+' "$PATCH" | grep -vF '+++ ' | sed -E 's/^\+//')"

  printf '%s\n' "$added" | grep -qE '^\s*push:'
  check "workflow triggers on push:" $?

  printf '%s\n' "$added" | grep -qE 'branches:\s*\[?\s*main'
  check "workflow push is scoped to main" $?

  if printf '%s\n' "$added" | grep -qE '^\s*pull_request:'; then
    check "workflow does NOT trigger on pull_request (WIP carries [ ] trailers)" 1
  else
    check "workflow does NOT trigger on pull_request (WIP carries [ ] trailers)" 0
  fi

  # (5 · M-06b) workflow calls the THIRD initiative-state.sh sync writer site.
  printf '%s\n' "$added" | grep -qE 'initiative-state\.sh sync'
  check "workflow wires initiative-state.sh sync (M-06b merge-boundary writer)" $?

  # workflow actually runs the reverse-drift checker.
  printf '%s\n' "$added" | grep -qE 'reverse-drift-check\.sh'
  check "workflow runs reverse-drift-check.sh" $?
else
  check "M-07-guard workflow patch present" 1
fi

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
