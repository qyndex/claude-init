#!/usr/bin/env bash
# Health-check used by /loop to gate continuation.
# Returns 0 if the project is in a healthy state, non-zero otherwise.
#
# Includes coverage gate: ≥90% line, ≥85% branch (95% on critical paths) — Round 8/10.
# Required gates cannot be waived by candidate-controlled environment flags.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || { echo "--root requires a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "Candidate root unavailable" >&2; exit 2; }
cd "$ROOT" || exit 2
printf 'Verification root: %s\n' "$ROOT"

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

# Invalid/null/non-numeric percentages must fail rather than enter the success
# branch of a shell integer comparison. Compare decimals without truncation.
coverage_meets() {
  printf '%s\n' "$1" | jq -es --arg minimum "$2" '
    length == 1 and (.[0] | type == "number" and . >= 0 and . <= 100 and . >= ($minimum | tonumber))' >/dev/null 2>&1
}

# Required gates cannot be waived by candidate files or environment claims.
# A trusted external waiver/equivalent-check service is not yet provisioned.
skip_honored() { return 1; }
for v in SKIP_COVERAGE SKIP_TDD_LEDGER SKIP_ASSERT_DENSITY SKIP_STORY_MAP SKIP_INTEG_COV SKIP_CHAR_GATE SKIP_BRANCH_CHECK SKIP_E2E_JOURNEY SKIP_ACCEPT_RERUN; do
  if [ "${!v:-0}" = "1" ]; then
    fail_msg "$v requested: trusted waiver unavailable"
    fails=$((fails+1))
  fi
done

# ─── Branch freshness preflight (Spec 001 AC-19) ──────────────────────────────
# First step: advisory-only. Warns if the branch has drifted far from main.
# Never increments $fails — a stale branch shouldn't block verification, only
# nudge a rebase.
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

if ! stacks_json=$(bash .claude/scripts/detect-stacks.sh); then
  fail_msg "stack detection failed"; exit 1
fi
if ! printf '%s\n' "$stacks_json" | jq -es '
  length == 1 and (.[0] | type == "object" and (.stacks | type == "array") and
  (.stacks | all(.[]; type == "string")) and
  (.stacks | length == (unique | length)) and
  (.stacks | all(.[]; . as $s | ["typescript","python","rust","go","java","ruby","dotnet","php","terraform","docker","kubernetes","shell","sql"] | index($s) != null)))' >/dev/null; then
  fail_msg "invalid or unsupported stack detection"; exit 1
fi
detected_stacks=$(printf '%s\n' "$stacks_json" | jq -r '.stacks[]')
lang_stacks=$(printf '%s\n' "$detected_stacks" | grep -E '^(typescript|python|rust|go|java|ruby|dotnet|php)$' || true)
stack_tests_ran=0
tested_stacks=""

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
  node_ws=$(printf '%s\n' "$stacks_json" | jq -r '.workspace // "none"')
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
    tested_stacks="$tested_stacks typescript"
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
    tested_stacks="$tested_stacks typescript"
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
      if ! coverage_meets "$line_pct" "$COVERAGE_MIN_LINE"; then
        fail_msg "merged line coverage ${line_int}% < ${COVERAGE_MIN_LINE}% (across $n_pkgs package summaries)"; fails=$((fails+1))
      else
        ok_msg "merged line coverage ${line_int}% across $n_pkgs package summaries"
      fi
      if ! coverage_meets "$branch_pct" "$COVERAGE_MIN_BRANCH"; then
        fail_msg "merged branch coverage ${branch_int}% < ${COVERAGE_MIN_BRANCH}%"; fails=$((fails+1))
      else
        ok_msg "merged branch coverage ${branch_int}%"
      fi
    fi
  fi

  # Coverage — POLARITY INVERTED (stack-portability-4): when tests ran, missing
  # coverage tooling/script/report is a FAIL, not a silent note. Operator waiver:
  # No local waiver is accepted. Workspace repos gate via the merge
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
          if ! coverage_meets "$line_pct" "$COVERAGE_MIN_LINE"; then
            fail_msg "line coverage ${line_pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
          else
            ok_msg "line coverage ${line_pct}%"
          fi
          if ! coverage_meets "$branch_pct" "$COVERAGE_MIN_BRANCH"; then
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
      fail_msg "tests ran but package.json has no coverage / test:coverage script — coverage gate cannot run"; fails=$((fails+1))
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
    tested_stacks="$tested_stacks python"
    py_run python3 -m pytest -q && ok_msg "pytest" || { fail_msg "pytest"; fails=$((fails+1)); }

    if ! skip_honored SKIP_COVERAGE; then
      step "Coverage gate (min line=${COVERAGE_MIN_LINE}%)"
      if py_run coverage run -m pytest -q >/dev/null 2>&1 && py_run coverage report --format=json -o /tmp/coverage.json >/dev/null 2>&1; then
        # JUSTIFIED: jq error muted + 0 fallback — a malformed coverage.json yields 0, which correctly fails the gate rather than crashing it
        pct=$(jq -r '.totals.percent_covered' /tmp/coverage.json 2>/dev/null || echo 0)
          if ! coverage_meets "$pct" "$COVERAGE_MIN_LINE"; then
          fail_msg "line coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
        else
          ok_msg "line coverage ${pct}%"
        fi
      else
        # Polarity inverted (stack-portability-4): tests ran → coverage must be measurable.
        fail_msg "tests ran but coverage could not be measured — install/configure coverage (pip install coverage)"; fails=$((fails+1))
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
  tested_stacks="$tested_stacks rust"
  cargo test --quiet && ok_msg "tests" || { fail_msg "tests"; fails=$((fails+1)); }

  if ! skip_honored SKIP_COVERAGE; then
    step "Coverage gate (min line=${COVERAGE_MIN_LINE}%) — cargo llvm-cov"
    if cargo llvm-cov --version >/dev/null 2>&1; then
      # JUSTIFIED: jq + summary errors muted with 0 fallback — an unparsable report yields 0, failing the gate visibly instead of crashing
      pct=$(cargo llvm-cov --summary-only --json 2>/dev/null | jq -r '.data[0].totals.lines.percent' 2>/dev/null || echo 0)
      if ! coverage_meets "$pct" "$COVERAGE_MIN_LINE"; then
        fail_msg "line coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
      else
        ok_msg "line coverage ${pct}%"
      fi
    else
      fail_msg "tests ran but cargo-llvm-cov is not installed — cargo install cargo-llvm-cov"; fails=$((fails+1))
    fi
  fi
fi

# ─── Go ───────────────────────────────────────────────────────────────────────
if [ -f go.mod ]; then
  step "Go project detected"
  go vet ./... && ok_msg "go vet" || { fail_msg "go vet"; fails=$((fails+1)); }
  stack_tests_ran=1
  tested_stacks="$tested_stacks go"
  go test ./... && ok_msg "go test" || { fail_msg "go test"; fails=$((fails+1)); }

  if ! skip_honored SKIP_COVERAGE; then
    step "Coverage gate (min ${COVERAGE_MIN_LINE}%) — coverprofile total"
    # Coverprofile TOTAL (stack-portability-4) — the old per-package mean
    # over-weighted tiny packages and ignored untested ones entirely.
    if go test -coverprofile=/tmp/go-cover.out ./... >/dev/null 2>&1 \
       && pct=$(go tool cover -func=/tmp/go-cover.out 2>/dev/null | awk '/^total:/{gsub(/%/,"",$NF); print $NF}') \
       && [ -n "$pct" ]; then
      if ! coverage_meets "$pct" "$COVERAGE_MIN_LINE"; then
        fail_msg "total coverage ${pct}% < ${COVERAGE_MIN_LINE}%"; fails=$((fails+1))
      else
        ok_msg "total coverage ${pct}%"
      fi
    else
      fail_msg "tests ran but coverprofile total could not be computed"; fails=$((fails+1))
    fi
  fi
fi

# ─── Java ─────────────────────────────────────────────────────────────────────
if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  step "Java project detected"
  stack_tests_ran=1
  tested_stacks="$tested_stacks java"
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
  tested_stacks="$tested_stacks ruby"
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
  tested_stacks="$tested_stacks dotnet"
  dotnet test && ok_msg "dotnet test" || { fail_msg "dotnet test"; fails=$((fails+1)); }
fi

# ─── PHP ──────────────────────────────────────────────────────────────────────
if [ -f composer.json ]; then
  step "PHP project detected"
  stack_tests_ran=1
  tested_stacks="$tested_stacks php"
  if jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
    composer test && ok_msg "composer test" || { fail_msg "composer test"; fails=$((fails+1)); }
  elif [ -x vendor/bin/phpunit ]; then
    vendor/bin/phpunit && ok_msg "phpunit" || { fail_msg "phpunit"; fails=$((fails+1)); }
  else
    fail_msg "composer.json present but no test script and no vendor/bin/phpunit"; fails=$((fails+1))
  fi
fi

# ─── Stack accounting (stack-portability-1) ──────────────────────────────────
step "Stack accounting"
for language in $lang_stacks; do
  case " $tested_stacks " in
    *" $language "*) ok_msg "$language test command executed" ;;
    *) fail_msg "$language detected but its test command did not execute"; fails=$((fails+1)) ;;
  esac
done
[ -n "$lang_stacks" ] || ok_msg "no language stacks detected (template/docs/shell-only repo)"

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

# Acceptance is required in branches and detached CI checkouts alike.
if [ -f tasks/TASKS.md ]; then
  step "Rerun newly completed task acceptance"
  acceptance_args=(--root "$ROOT" --timeout "${TDD_LEDGER_TIMEOUT:-300}")
  [ -z "${VERIFY_BASE:-}" ] || acceptance_args+=(--base "$VERIFY_BASE")
  if python3 "$SCRIPT_DIR/rerun-acceptance.py" "${acceptance_args[@]}"; then
    ok_msg "task acceptance green"
  else
    fail_msg "task acceptance failed"; fails=$((fails+1))
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
#     e2e/<id>/ dir exist. Applicable journeys must execute successfully.
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
    # e2e-rig-7 / FINDING-23 (live-e2e 2026-06-13): the journey used to launch
    # Playwright assuming a pre-provisioned browser. On a fresh runner that fails
    # with "Executable doesn't exist … chrome-headless-shell" — a TOOLCHAIN gap
    # mis-reported as a journey failure. Ensure the browser is present first
    # (idempotent; a no-op when already installed). Capture output to a log so a
    # real journey failure is diagnosable instead of swallowed by >/dev/null.
    jlog="verify/.journey-${sid}.log"
    # JUSTIFIED: mkdir is best-effort — if verify/ can't be created the log
    # redirects below fail loudly on their own; no error is hidden here.
    mkdir -p verify 2>/dev/null || true
    if ! npx playwright install chromium >>"$jlog" 2>&1; then
      fail_msg "E2E browser provisioning failed for spec $sid (see $jlog)"
      fails=$((fails+1))
    elif VERIFY_FEATURE="$slug" npx playwright test --config playwright.evidence.config.ts "e2e/$sid" >>"$jlog" 2>&1; then
      jr=$(ls -t verify/*-${sid}*/results.json 2>/dev/null | head -1)
      if [ -n "$jr" ] && bash .claude/scripts/spec-match.sh "$sid" "$jr" >/dev/null 2>&1; then
        ok_msg "journey green + every AC proven (spec $sid)"
      else
        fail_msg "journey ran but spec-match found unproven ACs (spec $sid)"; fails=$((fails+1))
      fi
    else
      fail_msg "E2E journey FAILED for spec $sid — fix before PR time (see $jlog)"; fails=$((fails+1))
    fi
  done
fi

# 5. Brownfield characterization gate (Round 14) — "no tests = no writes" on adopted
#    legacy. Blocks any change to a file under a flagged-legacy glob that lacks a
#    characterization test. Fires ONLY in an adopted repo (manifest present) with real
#    globs; local skip flags cannot waive this gate.
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
            fail_msg "legacy edit '$f' (flagged in uncharacterized-paths.txt) has no characterization test — sprout/characterize first"
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
