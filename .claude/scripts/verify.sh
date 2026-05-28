#!/usr/bin/env bash
# Health-check used by /loop to gate continuation.
# Returns 0 if the project is in a healthy state, non-zero otherwise.
#
# Includes coverage gate: ≥90% line, ≥85% branch (95% on critical paths) — Round 8/10.
# Skip coverage with SKIP_COVERAGE=1.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fails=0
# Round 8 D: calibrated thresholds (was 80/70). Critical paths (auth/payments/
# security/billing/crypto) get 95% via codecov.yml component_management.
COVERAGE_MIN_LINE="${COVERAGE_MIN_LINE:-90}"
COVERAGE_MIN_BRANCH="${COVERAGE_MIN_BRANCH:-85}"
COVERAGE_CRITICAL_LINE="${COVERAGE_CRITICAL_LINE:-95}"

step() { printf '\n→ %s\n' "$*"; }
fail_msg() { printf '  ✗ %s\n' "$*"; }
ok_msg() { printf '  ✓ %s\n' "$*"; }

# ─── Node / TypeScript ────────────────────────────────────────────────────────
if [ -f package.json ]; then
  step "Node project detected"

  PM="npm"
  if [ -f pnpm-lock.yaml ]; then PM="pnpm"
  elif [ -f bun.lock ] || [ -f bun.lockb ]; then PM="bun"
  elif [ -f yarn.lock ]; then PM="yarn"
  fi

  if grep -q '"typecheck"' package.json; then
    $PM run typecheck && ok_msg "typecheck" || { fail_msg "typecheck"; fails=$((fails+1)); }
  fi
  if grep -q '"lint"' package.json; then
    $PM run lint && ok_msg "lint" || { fail_msg "lint"; fails=$((fails+1)); }
  fi
  if grep -q '"test"' package.json; then
    if [ "$PM" = "npm" ]; then
      npm test -- --run && ok_msg "unit tests" || { fail_msg "unit tests"; fails=$((fails+1)); }
    elif [ "$PM" = "bun" ]; then
      bun test && ok_msg "unit tests" || { fail_msg "unit tests"; fails=$((fails+1)); }
    else
      $PM test --run && ok_msg "unit tests" || { fail_msg "unit tests"; fails=$((fails+1)); }
    fi
  fi

  # Coverage — only run if a coverage script is defined and SKIP_COVERAGE is unset
  if [ "${SKIP_COVERAGE:-0}" != "1" ] && grep -q '"coverage"\|"test:coverage"' package.json; then
    step "Coverage gate (min line=${COVERAGE_MIN_LINE}%, branch=${COVERAGE_MIN_BRANCH}%)"
    cov_script="coverage"
    grep -q '"test:coverage"' package.json && cov_script="test:coverage"
    if $PM run "$cov_script" 2>&1 | tee /tmp/coverage.out > /dev/null; then
      # Parse coverage from common formats. Try v8/istanbul JSON summary if exists.
      if [ -f coverage/coverage-summary.json ]; then
        line_pct=$(jq -r '.total.lines.pct' coverage/coverage-summary.json 2>/dev/null || echo 0)
        branch_pct=$(jq -r '.total.branches.pct' coverage/coverage-summary.json 2>/dev/null || echo 0)
        line_int=${line_pct%.*}
        branch_int=${branch_pct%.*}
        if [ "${line_int:-0}" -lt "$COVERAGE_MIN_LINE" ]; then
          fail_msg "line coverage ${line_pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
        else
          ok_msg "line coverage ${line_pct}%"
        fi
        if [ "${branch_int:-0}" -lt "$COVERAGE_MIN_BRANCH" ]; then
          fail_msg "branch coverage ${branch_pct}% < ${COVERAGE_MIN_BRANCH}%"; fails=$((fails+1))
        else
          ok_msg "branch coverage ${branch_pct}%"
        fi
      else
        echo "  (coverage-summary.json not generated — install c8 or @vitest/coverage-v8)"
      fi
    fi
  fi
fi

# ─── Python ───────────────────────────────────────────────────────────────────
if [ -f pyproject.toml ]; then
  step "Python project detected"
  command -v ruff >/dev/null && { ruff check . && ok_msg "ruff" || { fail_msg "ruff"; fails=$((fails+1)); } ; }
  command -v mypy >/dev/null && { mypy . && ok_msg "mypy" || { fail_msg "mypy"; fails=$((fails+1)); } ; } || true
  if [ -d tests ]; then
    uv run pytest -q && ok_msg "pytest" || { fail_msg "pytest"; fails=$((fails+1)); }
  fi

  if [ "${SKIP_COVERAGE:-0}" != "1" ] && [ -d tests ]; then
    step "Coverage gate (min line=${COVERAGE_MIN_LINE}%)"
    if uv run coverage run -m pytest -q 2>/dev/null && uv run coverage report --format=json -o /tmp/coverage.json 2>/dev/null; then
      pct=$(jq -r '.totals.percent_covered' /tmp/coverage.json 2>/dev/null || echo 0)
      pct_int=${pct%.*}
      if [ "${pct_int:-0}" -lt "$COVERAGE_MIN_LINE" ]; then
        fail_msg "line coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
      else
        ok_msg "line coverage ${pct}%"
      fi
    fi
  fi
fi

# ─── Rust ─────────────────────────────────────────────────────────────────────
if [ -f Cargo.toml ]; then
  step "Rust project detected"
  cargo check && ok_msg "cargo check" || { fail_msg "cargo check"; fails=$((fails+1)); }
  cargo clippy -- -D warnings && ok_msg "clippy" || { fail_msg "clippy"; fails=$((fails+1)); }
  cargo test --quiet && ok_msg "tests" || { fail_msg "tests"; fails=$((fails+1)); }
fi

# ─── Go ───────────────────────────────────────────────────────────────────────
if [ -f go.mod ]; then
  step "Go project detected"
  go vet ./... && ok_msg "go vet" || { fail_msg "go vet"; fails=$((fails+1)); }
  go test ./... && ok_msg "go test" || { fail_msg "go test"; fails=$((fails+1)); }

  if [ "${SKIP_COVERAGE:-0}" != "1" ]; then
    step "Coverage gate (min ${COVERAGE_MIN_LINE}%)"
    pct=$(go test -cover ./... 2>/dev/null | awk '/coverage:/{sum += $2; count++} END {if(count>0) print sum/count}' | tr -d '%' || echo 0)
    pct_int=${pct%.*}
    if [ "${pct_int:-0}" -lt "$COVERAGE_MIN_LINE" ]; then
      fail_msg "avg coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
    else
      ok_msg "avg coverage ${pct}%"
    fi
  fi
fi

# ─── Round 10 A: TDD + evidence gates ───────────────────────────────────
# These were proposed in Round 8 but never wired. Now they run.

# 1. Assertion-density: no assertion-free tests
if [ -x .claude/scripts/assert-density.sh ] && [ "${SKIP_ASSERT_DENSITY:-0}" != "1" ]; then
  step "Assertion-density gate"
  if bash .claude/scripts/assert-density.sh; then
    ok_msg "all tests contain real assertions"
  else
    fail_msg "assertion-free test(s) found"; fails=$((fails+1))
  fi
fi

# 2. Red→green ledger: any [x] task must have red.log + green.log
if [ -f tasks/TASKS.md ] && [ "${SKIP_TDD_LEDGER:-0}" != "1" ]; then
  step "TDD red→green ledger gate"
  ledger_fails=0
  # For each completed task, confirm a red.log + green.log exist somewhere under verify/
  while IFS= read -r task_id; do
    [ -z "$task_id" ] && continue
    if ! find verify -path "*/${task_id}/red.log" 2>/dev/null | grep -q . ; then
      fail_msg "task $task_id marked [x] but no red.log (TDD red phase not captured)"
      ledger_fails=$((ledger_fails+1))
    fi
    if ! find verify -path "*/${task_id}/green.log" 2>/dev/null | grep -q . ; then
      fail_msg "task $task_id marked [x] but no green.log"
      ledger_fails=$((ledger_fails+1))
    fi
  done < <(grep -oE '^- \[x\] T-[0-9]+' tasks/TASKS.md 2>/dev/null | grep -oE 'T-[0-9]+')
  if [ "$ledger_fails" -eq 0 ]; then
    ok_msg "all completed tasks have red→green ledger"
  else
    fails=$((fails + ledger_fails))
  fi
fi

# 3. Story → E2E map (Round 8 script, finally wired)
if [ -x .claude/scripts/story-test-map.sh ] && [ "${SKIP_STORY_MAP:-0}" != "1" ]; then
  step "Story → E2E coverage gate"
  if bash .claude/scripts/story-test-map.sh >/dev/null 2>&1; then
    ok_msg "every approved-spec user story has an E2E test"
  else
    fail_msg "user story missing E2E test (run story-test-map.sh for detail)"; fails=$((fails+1))
  fi
fi

# 4. Integration coverage (Round 8 script, finally wired)
if [ -x .claude/scripts/test-integration-coverage.sh ] && [ "${SKIP_INTEG_COV:-0}" != "1" ]; then
  step "Integration coverage gate"
  if bash .claude/scripts/test-integration-coverage.sh >/dev/null 2>&1; then
    ok_msg "changed API/DB files have integration tests"
  else
    fail_msg "changed handler/query lacks integration test"; fails=$((fails+1))
  fi
fi

# 5. Brownfield characterization gate (Round 14) — "no tests = no writes" on adopted
#    legacy. Blocks any change to a file under a flagged-legacy glob that lacks a
#    characterization test. Fires ONLY in an adopted repo (manifest present) with real
#    globs; SKIP_CHAR_GATE=1 is the explicit human override.
CHAR_MANIFEST=".claude/state/adopt/uncharacterized-paths.txt"
if [ -s "$CHAR_MANIFEST" ] && [ "${SKIP_CHAR_GATE:-0}" != "1" ] && grep -qvE '^[[:space:]]*(#|$)' "$CHAR_MANIFEST"; then
  step "Brownfield characterization gate (flagged-legacy edits require a characterization test)"
  BASE="${VERIFY_BASE:-}"
  if [ -z "$BASE" ]; then
    if git rev-parse --verify -q origin/main >/dev/null 2>&1; then BASE="origin/main"
    elif git rev-parse --verify -q main >/dev/null 2>&1; then BASE="main"
    else BASE="HEAD~1"; fi
  fi
  changed=$( { git diff --name-only "${BASE}...HEAD" 2>/dev/null; git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u | grep -vE '^[[:space:]]*$' || true)
  char_fails=0
  while IFS= read -r glob; do
    glob="${glob%%[[:space:]]*}"
    case "$glob" in ''|\#*) continue ;; esac
    for f in $changed; do
      # Tests/specs never need their own characterization test.
      case "$f" in *test*|*spec*|*Test*|*Spec*|*characterization*) continue ;; esac
      # shellcheck disable=SC2254
      case "$f" in
        $glob)
          base=$(basename "$f"); base="${base%.*}"
          if ! find . -type d -name node_modules -prune -o -type f \
               \( -iname "*${base}*characterization*" -o -iname "*characterization*${base}*" \) -print 2>/dev/null | grep -q .; then
            fail_msg "legacy edit '$f' (flagged in uncharacterized-paths.txt) has no characterization test — sprout/characterize first (override: SKIP_CHAR_GATE=1)"
            char_fails=$((char_fails+1))
          fi
          ;;
      esac
    done
  done < "$CHAR_MANIFEST"
  [ "$char_fails" -eq 0 ] && ok_msg "no un-characterized legacy edits (or none changed)" || fails=$((fails + char_fails))
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "verify: PASS"
  exit 0
else
  echo "verify: FAIL ($fails check(s) failed)"
  exit 1
fi
