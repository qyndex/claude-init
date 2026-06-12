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
warn_msg() { printf '  ⚠ %s\n' "$*"; }

# ─── SKIP_* gate-bypass guard (Spec 003 AC-1, AC-2) ───────────────────────────
# An autonomous agent can set SKIP_TDD_LEDGER=1 / SKIP_COVERAGE=1 etc. to disarm
# the very gates that constrain it. Honor any SKIP_* ONLY when the operator has
# created .claude/state/allow-skip-gates (gitignored, human-only). Otherwise the
# SKIP request is ignored and the gate runs. Either way, log the requested set so
# a skipped gate is visible at PR review (AC-2).
SKIP_GATES_MARKER="$ROOT/.claude/state/allow-skip-gates"
SKIP_GATES_ALLOWED=0
[ -f "$SKIP_GATES_MARKER" ] && SKIP_GATES_ALLOWED=1

# skip_honored VARNAME → returns 0 (true) only if that SKIP_* is set AND the
# operator marker is present. Without the marker it always returns 1 (run gate).
skip_honored() {
  local var="$1"
  local val="${!var:-0}"
  [ "$val" = "1" ] || return 1
  [ "$SKIP_GATES_ALLOWED" = "1" ]
}

# Log the requested SKIP_* set and whether it is honored.
requested_skips=""
for v in SKIP_COVERAGE SKIP_TDD_LEDGER SKIP_ASSERT_DENSITY SKIP_STORY_MAP SKIP_INTEG_COV SKIP_CHAR_GATE SKIP_BRANCH_CHECK SKIP_E2E_JOURNEY; do
  [ "${!v:-0}" = "1" ] && requested_skips="$requested_skips $v"
done
if [ -n "$requested_skips" ]; then
  if [ "$SKIP_GATES_ALLOWED" = "1" ]; then
    warn_msg "SKIP gates requested and HONORED (operator marker present):${requested_skips}"
  else
    warn_msg "SKIP gates requested but IGNORED (no .claude/state/allow-skip-gates marker):${requested_skips}"
  fi
  # Append to the evidence bundle so the bypass is auditable at PR review (AC-2).
  mkdir -p "$ROOT/verify" 2>/dev/null || true
  printf '%s\tverify-skip-request\thonored=%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SKIP_GATES_ALLOWED" "${requested_skips# }" \
    >> "$ROOT/verify/.skip-log" 2>/dev/null || true
else
  ok_msg "no SKIP_* gates requested"
fi

# ─── Branch freshness preflight (Spec 001 AC-19) ──────────────────────────────
# First step: advisory-only. Warns if the branch has drifted far from main.
# Never increments $fails — a stale branch shouldn't block verification, only
# nudge a rebase. Honors SKIP_BRANCH_CHECK=1 (set in CI).
step "Branch freshness"
# JUSTIFIED: 2>/dev/null + || true keep this advisory preflight from ever aborting verify — branch-freshness is non-blocking by design (AC-19); an empty bf_out simply means "fresh"
bf_out="$(bash "$ROOT/.claude/scripts/branch-freshness.sh" 2>/dev/null || true)"
if [ -n "$bf_out" ]; then
  warn_msg "$bf_out"
else
  ok_msg "branch fresh against main"
fi

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
  if ! skip_honored SKIP_COVERAGE && grep -q '"coverage"\|"test:coverage"' package.json; then
    step "Coverage gate (min line=${COVERAGE_MIN_LINE}%, branch=${COVERAGE_MIN_BRANCH}%)"
    cov_script="coverage"
    grep -q '"test:coverage"' package.json && cov_script="test:coverage"
    if $PM run "$cov_script" 2>&1 | tee /tmp/coverage.out > /dev/null; then
      # Parse coverage from common formats. Try v8/istanbul JSON summary if exists.
      if [ -f coverage/coverage-summary.json ]; then
        # JUSTIFIED: jq error muted + 0 fallback — a malformed summary yields 0, which correctly fails the line-coverage gate rather than crashing it
        line_pct=$(jq -r '.total.lines.pct' coverage/coverage-summary.json 2>/dev/null || echo 0)
        # JUSTIFIED: jq error muted + 0 fallback — same rationale for branch coverage; 0 fails the gate safely
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
  # JUSTIFIED: trailing fallback absorbs the `command -v mypy` miss — when mypy is not installed the whole guarded clause is skipped without the absence being mistaken for a tool failure; a present-but-failing mypy still increments fails inside the braces
  command -v mypy >/dev/null && { mypy . && ok_msg "mypy" || { fail_msg "mypy"; fails=$((fails+1)); } ; } || true
  if [ -d tests ]; then
    uv run pytest -q && ok_msg "pytest" || { fail_msg "pytest"; fails=$((fails+1)); }
  fi

  if ! skip_honored SKIP_COVERAGE && [ -d tests ]; then
    step "Coverage gate (min line=${COVERAGE_MIN_LINE}%)"
    # JUSTIFIED: coverage tool errors muted — the && chain already gates on success; a failing run skips the whole block rather than parsing a bad report
    if uv run coverage run -m pytest -q 2>/dev/null && uv run coverage report --format=json -o /tmp/coverage.json 2>/dev/null; then
      # JUSTIFIED: jq error muted + 0 fallback — a malformed coverage.json yields 0, which correctly fails the gate rather than crashing it
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

  if ! skip_honored SKIP_COVERAGE; then
    step "Coverage gate (min ${COVERAGE_MIN_LINE}%)"
    # JUSTIFIED: go test error muted + 0 fallback — a package with no tests prints to stderr; the awk averages only real "coverage:" lines and 0 is the correct floor when none exist
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
if [ -x .claude/scripts/assert-density.sh ] && ! skip_honored SKIP_ASSERT_DENSITY; then
  step "Assertion-density gate"
  if bash .claude/scripts/assert-density.sh; then
    ok_msg "all tests contain real assertions"
  else
    fail_msg "assertion-free test(s) found"; fails=$((fails+1))
  fi
fi

# 2. Red→green ledger: any [x] task must have red.log + green.log
if [ -f tasks/TASKS.md ] && ! skip_honored SKIP_TDD_LEDGER; then
  step "TDD red→green ledger gate"
  ledger_fails=0
  # For each completed task, confirm a red.log + green.log exist somewhere under verify/
  while IFS= read -r task_id; do
    [ -z "$task_id" ] && continue
    # JUSTIFIED: find error muted — an absent verify/ dir means the red.log genuinely does not exist; grep -q "no match" is the intended ledger-gate failure trigger
    if ! find verify -path "*/${task_id}/red.log" 2>/dev/null | grep -q . ; then
      fail_msg "task $task_id marked [x] but no red.log (TDD red phase not captured)"
      ledger_fails=$((ledger_fails+1))
    fi
    # JUSTIFIED: find error muted — same rationale; an absent green.log is the intended ledger-gate failure trigger
    if ! find verify -path "*/${task_id}/green.log" 2>/dev/null | grep -q . ; then
      fail_msg "task $task_id marked [x] but no green.log"
      ledger_fails=$((ledger_fails+1))
    fi
  # JUSTIFIED: grep error muted — a missing tasks/TASKS.md yields no completed task ids, so the loop runs zero times (nothing to gate)
  done < <(grep -oE '^- \[x\] T-[0-9]+' tasks/TASKS.md 2>/dev/null | grep -oE 'T-[0-9]+')
  if [ "$ledger_fails" -eq 0 ]; then
    ok_msg "all completed tasks have red→green ledger"
  else
    fails=$((fails + ledger_fails))
  fi
fi

# 3. Story → E2E map (Round 8 script, finally wired)
if [ -x .claude/scripts/story-test-map.sh ] && ! skip_honored SKIP_STORY_MAP; then
  step "Story → E2E coverage gate"
  if bash .claude/scripts/story-test-map.sh >/dev/null 2>&1; then
    ok_msg "every approved-spec user story has an E2E test"
  else
    fail_msg "user story missing E2E test (run story-test-map.sh for detail)"; fails=$((fails+1))
  fi
fi

# 4. Integration coverage (Round 8 script, finally wired)
if [ -x .claude/scripts/test-integration-coverage.sh ] && ! skip_honored SKIP_INTEG_COV; then
  step "Integration coverage gate"
  if bash .claude/scripts/test-integration-coverage.sh >/dev/null 2>&1; then
    ok_msg "changed API/DB files have integration tests"
  else
    fail_msg "changed handler/query lacks integration test"; fails=$((fails+1))
  fi
fi

# 4b. E2E journey gate (gap-audit G55) — the autonomous local gate used to skip
#     the user journey entirely; AC coverage was only enforced at PR time, so
#     /loop and self-heal cycles could iterate on a broken journey for hours.
#     Opt-in by construction: fires only when the Playwright rig AND a spec's
#     e2e/<id>/ dir exist. SKIP_E2E_JOURNEY honors the operator marker.
if [ -f playwright.config.ts ] && ! skip_honored SKIP_E2E_JOURNEY; then
  for spec in specs/active/*.md; do
    [ -f "$spec" ] || continue
    grep -qE '^status:[[:space:]]*"?approved' "$spec" || continue
    sid=$(basename "$spec" .md | grep -oE '^[0-9]+' | head -1)
    [ -n "$sid" ] && [ -d "e2e/$sid" ] || continue
    step "E2E journey gate (spec $sid)"
    slug=$(basename "$spec" .md)
    if VERIFY_FEATURE="$slug" npx playwright test "e2e/$sid" >/dev/null 2>&1; then
      jr=$(ls -t verify/*-${sid}*/results.json 2>/dev/null | head -1)
      if [ -n "$jr" ] && bash .claude/scripts/spec-match.sh "$sid" "$jr" >/dev/null 2>&1; then
        ok_msg "journey green + every AC proven (spec $sid)"
      else
        fail_msg "journey ran but spec-match found unproven ACs (spec $sid)"; fails=$((fails+1))
      fi
    else
      fail_msg "E2E journey FAILED for spec $sid — fix before PR time"; fails=$((fails+1))
    fi
  done
fi

# 5. Brownfield characterization gate (Round 14) — "no tests = no writes" on adopted
#    legacy. Blocks any change to a file under a flagged-legacy glob that lacks a
#    characterization test. Fires ONLY in an adopted repo (manifest present) with real
#    globs; SKIP_CHAR_GATE=1 is the explicit human override.
CHAR_MANIFEST=".claude/state/adopt/uncharacterized-paths.txt"
if [ -s "$CHAR_MANIFEST" ] && ! skip_honored SKIP_CHAR_GATE && grep -qvE '^[[:space:]]*(#|$)' "$CHAR_MANIFEST"; then
  step "Brownfield characterization gate (flagged-legacy edits require a characterization test)"
  BASE="${VERIFY_BASE:-}"
  if [ -z "$BASE" ]; then
    if git rev-parse --verify -q origin/main >/dev/null 2>&1; then BASE="origin/main"
    elif git rev-parse --verify -q main >/dev/null 2>&1; then BASE="main"
    else BASE="HEAD~1"; fi
  fi
  # JUSTIFIED: git errors muted + grep fallback — an unresolvable BASE or empty diff yields no changed files; the empty-then-loop body simply iterates zero times, the correct "nothing to gate" behaviour
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
          # JUSTIFIED: find error muted — unreadable subdirs emit noise; grep -q decides presence and "no match" is the intended trigger for the gate failure below
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
