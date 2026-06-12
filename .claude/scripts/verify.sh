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
#
# e2e-audit tdd-loop-2: VERIFY_CI carve-out — evidence-gate re-executes verify.sh
# on a bare CI runner where story-map / integ-cov / the journey run as their own
# jobs. ONLY those three gates may be relaxed via VERIFY_CI=1, only when actually
# running under GitHub Actions, and always logged. The TDD ledger and coverage
# gates are NEVER relaxable this way (that would reopen the spec-003 bypass).
skip_honored() {
  local var="$1"
  local val="${!var:-0}"
  [ "$val" = "1" ] || return 1
  if [ "$SKIP_GATES_ALLOWED" = "1" ]; then return 0; fi
  case "$var" in
    SKIP_STORY_MAP|SKIP_INTEG_COV|SKIP_E2E_JOURNEY)
      if [ "${VERIFY_CI:-0}" = "1" ] && [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        warn_msg "VERIFY_CI: $var honored in CI re-execution context (gate runs as its own job)"
        return 0
      fi
      ;;
  esac
  return 1
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

# ─── Stack checks (e2e-audit stack-portability-1..4) ─────────────────────────
# Driven by detect-stacks.sh (single source of stack truth). Explicit accounting:
# if language stacks are detected but ZERO stack test commands execute, verify
# FAILS — the old per-stack ifs let an undetected stack sail through green.
# Carve-out: a repo with NO language stacks (this template itself: shell/docs
# only) skips with a visible note.

# JUSTIFIED: detection errors yield empty stacks — the accounting below then takes the no-language-stack path, which is visible, not silent
stacks_json=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null || echo '{"stacks":[]}')
# JUSTIFIED: jq muted on malformed detection output — empty list routes to the visible no-stack path
detected_stacks=$(echo "$stacks_json" | jq -r '.stacks[]' 2>/dev/null)
# JUSTIFIED: grep no-match exits 1 — an empty lang_stacks is the legitimate docs/shell-only case
lang_stacks=$(printf '%s\n' "$detected_stacks" | grep -E '^(typescript|python|rust|go|java|ruby|dotnet|php)$' || true)
stack_tests_ran=0

# Python package-manager ladder (stack-portability-3): pick the runner from the
# lockfile — uv was previously assumed, breaking poetry/pipenv/plain-pip repos.
py_run() {
  if [ -f uv.lock ]; then uv run "$@"
  elif [ -f poetry.lock ]; then poetry run "$@"
  elif [ -f Pipfile.lock ]; then pipenv run "$@"
  else "$@"
  fi
}

# ─── Node / TypeScript ────────────────────────────────────────────────────────
if [ -f package.json ]; then
  step "Node project detected"

  PM="npm"
  if [ -f pnpm-lock.yaml ]; then PM="pnpm"
  elif [ -f bun.lock ] || [ -f bun.lockb ]; then PM="bun"
  elif [ -f yarn.lock ]; then PM="yarn"
  fi

  # Workspace dimension (stack-portability-5) — from detect-stacks.sh; a monorepo
  # run from the root must aggregate across packages, not test only the root.
  # JUSTIFIED: detection errors fall back to "none" — single-package behavior, the safe default
  node_ws=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null | jq -r '.workspace // "none"' 2>/dev/null || echo none)
  case "$node_ws" in turbo|nx|pnpm|lerna|npm) : ;; *) node_ws="none" ;; esac

  # Runner-aware test flags (stack-portability-6): --run is vitest-only, --ci is jest-only.
  test_args=""
  if jq -e '.devDependencies.vitest // .dependencies.vitest' package.json >/dev/null 2>&1; then test_args="--run"
  elif jq -e '.devDependencies.jest // .dependencies.jest' package.json >/dev/null 2>&1; then test_args="--ci"
  fi

  if grep -q '"typecheck"' package.json; then
    $PM run typecheck && ok_msg "typecheck" || { fail_msg "typecheck"; fails=$((fails+1)); }
  fi
  if grep -q '"lint"' package.json; then
    $PM run lint && ok_msg "lint" || { fail_msg "lint"; fails=$((fails+1)); }
  fi

  if [ "$node_ws" != "none" ]; then
    # Monorepo: run the aggregation the repo actually orchestrates with. A detected
    # workspace whose runner is not installed is a FAIL — testing only the root
    # package would silently skip every workspace package.
    step "Workspace test aggregation via $node_ws"
    stack_tests_ran=1
    case "$node_ws" in
      turbo)
        if command -v turbo >/dev/null 2>&1 || [ -x node_modules/.bin/turbo ]; then
          npx turbo run test && ok_msg "turbo run test" || { fail_msg "turbo run test"; fails=$((fails+1)); }
        else
          fail_msg "turbo.json present but turbo not installed — workspace tests cannot aggregate"; fails=$((fails+1))
        fi ;;
      nx)
        if command -v nx >/dev/null 2>&1 || [ -x node_modules/.bin/nx ]; then
          npx nx run-many -t test && ok_msg "nx run-many -t test" || { fail_msg "nx run-many -t test"; fails=$((fails+1)); }
        else
          fail_msg "nx.json present but nx not installed — workspace tests cannot aggregate"; fails=$((fails+1))
        fi ;;
      pnpm)
        if command -v pnpm >/dev/null 2>&1; then
          pnpm -r run test ${test_args:+-- $test_args} && ok_msg "pnpm -r run test" || { fail_msg "pnpm -r run test"; fails=$((fails+1)); }
        else
          fail_msg "pnpm-workspace.yaml present but pnpm not installed — workspace tests cannot aggregate"; fails=$((fails+1))
        fi ;;
      lerna|npm)
        if grep -q '"test"' package.json || [ "$node_ws" = "npm" ]; then
          npm test --workspaces --if-present ${test_args:+-- $test_args} && ok_msg "npm test --workspaces" || { fail_msg "npm test --workspaces"; fails=$((fails+1)); }
        else
          fail_msg "$node_ws workspace detected but no runnable aggregation (no test script)"; fails=$((fails+1))
        fi ;;
    esac
  elif grep -q '"test"' package.json; then
    stack_tests_ran=1
    if [ "$PM" = "npm" ]; then
      npm test ${test_args:+-- $test_args} && ok_msg "unit tests" || { fail_msg "unit tests"; fails=$((fails+1)); }
    elif [ "$PM" = "bun" ]; then
      bun test && ok_msg "unit tests" || { fail_msg "unit tests"; fails=$((fails+1)); }
    else
      $PM test $test_args && ok_msg "unit tests" || { fail_msg "unit tests"; fails=$((fails+1)); }
    fi
  fi

  # Per-package coverage merge (stack-portability-5): in a workspace, each package
  # emits its own coverage/coverage-summary.json. Merge totals (covered/total sums,
  # not pct averages) and apply the same gate. No summaries at all → FAIL.
  if ! skip_honored SKIP_COVERAGE && [ "${node_ws:-none}" != "none" ] && [ "$stack_tests_ran" = "1" ]; then
    step "Workspace coverage merge (min line=${COVERAGE_MIN_LINE}%, branch=${COVERAGE_MIN_BRANCH}%)"
    # JUSTIFIED: find muted — packages without coverage simply contribute no summaries; the zero-summaries case is failed explicitly below
    summaries=$(find . -maxdepth 5 -path '*/coverage/coverage-summary.json' -not -path '*/node_modules/*' 2>/dev/null)
    if [ -z "$summaries" ]; then
      fail_msg "workspace tests ran but NO package emitted coverage/coverage-summary.json — configure the json-summary reporter per package"; fails=$((fails+1))
    else
      # JUSTIFIED: jq muted + 0 fallback — a malformed summary contributes nothing and the 0% computed below fails the gate safely
      merged=$(echo "$summaries" | xargs cat 2>/dev/null | jq -s '
        {lc: (map(.total.lines.covered) | add), lt: (map(.total.lines.total) | add),
         bc: (map(.total.branches.covered) | add), bt: (map(.total.branches.total) | add)} |
        {line: (if .lt > 0 then (.lc / .lt * 100) else 0 end),
         branch: (if .bt > 0 then (.bc / .bt * 100) else 0 end)}' 2>/dev/null || echo '{"line":0,"branch":0}')
      line_pct=$(echo "$merged" | jq -r '.line' 2>/dev/null || echo 0)
      branch_pct=$(echo "$merged" | jq -r '.branch' 2>/dev/null || echo 0)
      line_int=${line_pct%.*}; branch_int=${branch_pct%.*}
      n_pkgs=$(echo "$summaries" | wc -l | tr -d ' ')
      if [ "${line_int:-0}" -lt "$COVERAGE_MIN_LINE" ]; then
        fail_msg "merged line coverage ${line_int}% < ${COVERAGE_MIN_LINE}% (across $n_pkgs package summaries)"; fails=$((fails+1))
      else
        ok_msg "merged line coverage ${line_int}% across $n_pkgs package summaries"
      fi
      if [ "${branch_int:-0}" -lt "$COVERAGE_MIN_BRANCH" ]; then
        fail_msg "merged branch coverage ${branch_int}% < ${COVERAGE_MIN_BRANCH}%"; fails=$((fails+1))
      else
        ok_msg "merged branch coverage ${branch_int}%"
      fi
    fi
  fi

  # Coverage — POLARITY INVERTED (stack-portability-4): when tests ran, missing
  # coverage tooling/script/report is a FAIL, not a silent note. Operator waiver:
  # allow-skip-gates marker + SKIP_COVERAGE=1. Workspace repos gate via the merge
  # block above instead — a root-level coverage run would miss every package.
  if ! skip_honored SKIP_COVERAGE && [ "$stack_tests_ran" = "1" ] && [ "${node_ws:-none}" = "none" ]; then
    step "Coverage gate (min line=${COVERAGE_MIN_LINE}%, branch=${COVERAGE_MIN_BRANCH}%)"
    if grep -q '"coverage"\|"test:coverage"' package.json; then
      cov_script="coverage"
      grep -q '"test:coverage"' package.json && cov_script="test:coverage"
      if $PM run "$cov_script" 2>&1 | tee /tmp/coverage.out > /dev/null; then
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
          fail_msg "coverage script ran but coverage/coverage-summary.json was not generated — configure the json-summary reporter (c8 / @vitest/coverage-v8)"; fails=$((fails+1))
        fi
      else
        fail_msg "coverage script failed"; fails=$((fails+1))
      fi
    else
      fail_msg "tests ran but package.json has no coverage / test:coverage script — coverage gate cannot run (waiver: allow-skip-gates + SKIP_COVERAGE=1)"; fails=$((fails+1))
    fi
  fi
fi

# ─── Python ───────────────────────────────────────────────────────────────────
# Broader sentinel set (stack-portability-3): pyproject OR requirements.txt OR setup.py.
if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then
  step "Python project detected"
  command -v ruff >/dev/null && { ruff check . && ok_msg "ruff" || { fail_msg "ruff"; fails=$((fails+1)); } ; }
  # JUSTIFIED: trailing fallback absorbs the `command -v mypy` miss — when mypy is not installed the whole guarded clause is skipped without the absence being mistaken for a tool failure; a present-but-failing mypy still increments fails inside the braces
  command -v mypy >/dev/null && { mypy . && ok_msg "mypy" || { fail_msg "mypy"; fails=$((fails+1)); } ; } || true
  if [ -d tests ] || [ -f conftest.py ]; then
    stack_tests_ran=1
    py_run python3 -m pytest -q && ok_msg "pytest" || { fail_msg "pytest"; fails=$((fails+1)); }

    if ! skip_honored SKIP_COVERAGE; then
      step "Coverage gate (min line=${COVERAGE_MIN_LINE}%)"
      if py_run coverage run -m pytest -q >/dev/null 2>&1 && py_run coverage report --format=json -o /tmp/coverage.json >/dev/null 2>&1; then
        # JUSTIFIED: jq error muted + 0 fallback — a malformed coverage.json yields 0, which correctly fails the gate rather than crashing it
        pct=$(jq -r '.totals.percent_covered' /tmp/coverage.json 2>/dev/null || echo 0)
        pct_int=${pct%.*}
        if [ "${pct_int:-0}" -lt "$COVERAGE_MIN_LINE" ]; then
          fail_msg "line coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
        else
          ok_msg "line coverage ${pct}%"
        fi
      else
        # Polarity inverted (stack-portability-4): tests ran → coverage must be measurable.
        fail_msg "tests ran but coverage could not be measured — install/configure coverage (pip install coverage) (waiver: allow-skip-gates + SKIP_COVERAGE=1)"; fails=$((fails+1))
      fi
    fi
  fi
fi

# ─── Rust ─────────────────────────────────────────────────────────────────────
if [ -f Cargo.toml ]; then
  step "Rust project detected"
  cargo check && ok_msg "cargo check" || { fail_msg "cargo check"; fails=$((fails+1)); }
  cargo clippy -- -D warnings && ok_msg "clippy" || { fail_msg "clippy"; fails=$((fails+1)); }
  stack_tests_ran=1
  cargo test --quiet && ok_msg "tests" || { fail_msg "tests"; fails=$((fails+1)); }

  if ! skip_honored SKIP_COVERAGE; then
    step "Coverage gate (min line=${COVERAGE_MIN_LINE}%) — cargo llvm-cov"
    if cargo llvm-cov --version >/dev/null 2>&1; then
      # JUSTIFIED: jq + summary errors muted with 0 fallback — an unparsable report yields 0, failing the gate visibly instead of crashing
      pct=$(cargo llvm-cov --summary-only --json 2>/dev/null | jq -r '.data[0].totals.lines.percent' 2>/dev/null || echo 0)
      pct_int=${pct%.*}
      if [ "${pct_int:-0}" -lt "$COVERAGE_MIN_LINE" ]; then
        fail_msg "line coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
      else
        ok_msg "line coverage ${pct}%"
      fi
    else
      fail_msg "tests ran but cargo-llvm-cov is not installed — cargo install cargo-llvm-cov (waiver: allow-skip-gates + SKIP_COVERAGE=1)"; fails=$((fails+1))
    fi
  fi
fi

# ─── Go ───────────────────────────────────────────────────────────────────────
if [ -f go.mod ]; then
  step "Go project detected"
  go vet ./... && ok_msg "go vet" || { fail_msg "go vet"; fails=$((fails+1)); }
  stack_tests_ran=1
  go test ./... && ok_msg "go test" || { fail_msg "go test"; fails=$((fails+1)); }

  if ! skip_honored SKIP_COVERAGE; then
    step "Coverage gate (min ${COVERAGE_MIN_LINE}%) — coverprofile total"
    # Coverprofile TOTAL (stack-portability-4) — the old per-package mean
    # over-weighted tiny packages and ignored untested ones entirely.
    if go test -coverprofile=/tmp/go-cover.out ./... >/dev/null 2>&1 \
       && pct=$(go tool cover -func=/tmp/go-cover.out 2>/dev/null | awk '/^total:/{gsub(/%/,"",$NF); print $NF}') \
       && [ -n "$pct" ]; then
      pct_int=${pct%.*}
      if [ "${pct_int:-0}" -lt "$COVERAGE_MIN_LINE" ]; then
        fail_msg "total coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
      else
        ok_msg "total coverage ${pct}%"
      fi
    else
      fail_msg "tests ran but coverprofile total could not be computed (waiver: allow-skip-gates + SKIP_COVERAGE=1)"; fails=$((fails+1))
    fi
  fi
fi

# ─── Java ─────────────────────────────────────────────────────────────────────
if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  step "Java project detected"
  stack_tests_ran=1
  if [ -f pom.xml ]; then
    mvn -q test && ok_msg "mvn test" || { fail_msg "mvn test"; fails=$((fails+1)); }
  elif [ -x ./gradlew ]; then
    ./gradlew test && ok_msg "gradle test" || { fail_msg "gradle test"; fails=$((fails+1)); }
  else
    gradle test && ok_msg "gradle test" || { fail_msg "gradle test"; fails=$((fails+1)); }
  fi
fi

# ─── Ruby ─────────────────────────────────────────────────────────────────────
if [ -f Gemfile ]; then
  step "Ruby project detected"
  stack_tests_ran=1
  if [ -d spec ]; then
    bundle exec rspec && ok_msg "rspec" || { fail_msg "rspec"; fails=$((fails+1)); }
  else
    bundle exec rake test && ok_msg "rake test" || { fail_msg "rake test"; fails=$((fails+1)); }
  fi
fi

# ─── .NET ─────────────────────────────────────────────────────────────────────
# JUSTIFIED: find muted — absence of sln/csproj simply means no dotnet stack
if find . -maxdepth 2 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q .; then
  step ".NET project detected"
  stack_tests_ran=1
  dotnet test && ok_msg "dotnet test" || { fail_msg "dotnet test"; fails=$((fails+1)); }
fi

# ─── PHP ──────────────────────────────────────────────────────────────────────
if [ -f composer.json ]; then
  step "PHP project detected"
  stack_tests_ran=1
  if jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
    composer test && ok_msg "composer test" || { fail_msg "composer test"; fails=$((fails+1)); }
  elif [ -x vendor/bin/phpunit ]; then
    vendor/bin/phpunit && ok_msg "phpunit" || { fail_msg "phpunit"; fails=$((fails+1)); }
  else
    fail_msg "composer.json present but no test script and no vendor/bin/phpunit"; fails=$((fails+1))
  fi
fi

# ─── Stack accounting (stack-portability-1) ──────────────────────────────────
if [ -n "$lang_stacks" ] && [ "$stack_tests_ran" -eq 0 ]; then
  step "Stack accounting"
  fail_msg "language stack(s) detected ($(printf '%s' "$lang_stacks" | tr '\n' ' ')) but ZERO stack test commands executed — refusing silent pass"
  fails=$((fails+1))
elif [ -z "$lang_stacks" ]; then
  step "Stack accounting"
  ok_msg "no language stacks detected (template/docs/shell-only repo) — stack checks legitimately skipped"
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

# 2. Red→green ledger gate — SINGLE implementation in check-tdd-ledger.sh
# (e2e-audit tdd-loop-2: the previous inline copy and the script drifted; the
# script also carries the bare-checkout degrade + enforcement floor + content
# checks that the inline version lacked).
if [ -f tasks/TASKS.md ] && ! skip_honored SKIP_TDD_LEDGER; then
  step "TDD red→green ledger gate (check-tdd-ledger.sh)"
  if bash .claude/scripts/check-tdd-ledger.sh; then
    ok_msg "TDD ledger gate clean"
  else
    fail_msg "TDD ledger gate failed — see check-tdd-ledger.sh output above"
    fails=$((fails+1))
  fi
fi

# 2b. Accept re-run (e2e-audit tdd-loop-5): every task newly flipped [x] on this
# branch must have an accept: that STILL exits 0 — the flip claimed it did.
# Bounded by the same timeout as the TDD ledger. SKIP_ACCEPT_RERUN to waive.
if [ -f tasks/TASKS.md ] && ! skip_honored SKIP_ACCEPT_RERUN && git rev-parse --git-dir >/dev/null 2>&1; then
  cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo detached)
  if [ "$cur_branch" != "main" ] && [ "$cur_branch" != "master" ] && [ "$cur_branch" != "detached" ]; then
    # JUSTIFIED: merge-base fails on shallow/bare checkouts — the gate degrades to a no-op (zero newly-flipped ids)
    base=$(git merge-base origin/main HEAD 2>/dev/null || git merge-base main HEAD 2>/dev/null || true)
    newly_done=""
    if [ -n "$base" ]; then
      # JUSTIFIED: diff/grep empty when no flips on the branch — the loop simply doesn't run
      newly_done=$(git diff "$base" -- tasks/TASKS.md 2>/dev/null | grep -E '^\+- \[x\] T-[0-9]+' | grep -oE 'T-[0-9]+' | sort -u || true)
    fi
    if [ -n "$newly_done" ]; then
      step "Accept re-run for tasks newly [x] on this branch"
      timeout_bin=""
      command -v timeout >/dev/null 2>&1 && timeout_bin="timeout ${TDD_LEDGER_TIMEOUT:-300}"
      command -v gtimeout >/dev/null 2>&1 && timeout_bin="gtimeout ${TDD_LEDGER_TIMEOUT:-300}"
      accept_fails=0
      for tid in $newly_done; do
        acc=$(awk -v id="$tid" '
          $0 ~ "^- \\[x\\] " id "[^0-9]" { inblk = 1; next }
          inblk && /^- \[/ { inblk = 0 }
          inblk && /^[ \t]+accept:/ { sub(/^[ \t]+accept:[ ]*/, ""); print; exit }
        ' tasks/TASKS.md)
        case "$acc" in
          ""|*"<"*|*tbd*|*human*) continue ;;
        esac
        # JUSTIFIED: word-splitting of $timeout_bin is the wrapper invocation; accept commands run via bash -c
        if $timeout_bin bash -c "$acc" >/dev/null 2>&1; then
          ok_msg "$tid accept still green"
        else
          fail_msg "$tid was flipped [x] on this branch but its accept: now fails: $acc"
          accept_fails=$((accept_fails+1))
        fi
      done
      [ "$accept_fails" -gt 0 ] && fails=$((fails+1))
    fi
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
# e2e-audit e2e-rig-4: keyed on the STANDALONE evidence config — a brownfield
# project's own playwright.config.ts is neither sufficient (wrong reporters)
# nor required (the rig brings its own via --config).
if [ -f playwright.evidence.config.ts ] && ! skip_honored SKIP_E2E_JOURNEY; then
  for spec in specs/active/*.md; do
    [ -f "$spec" ] || continue
    grep -qE '^status:[[:space:]]*"?approved' "$spec" || continue
    sid=$(basename "$spec" .md | grep -oE '^[0-9]+' | head -1)
    [ -n "$sid" ] && [ -d "e2e/$sid" ] || continue
    step "E2E journey gate (spec $sid)"
    slug=$(basename "$spec" .md)
    if VERIFY_FEATURE="$slug" npx playwright test --config playwright.evidence.config.ts "e2e/$sid" >/dev/null 2>&1; then
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
