#!/usr/bin/env bash
# Local pre-PR check — runs the SAME suite as the daily 8am CI batch.
#
# Why this exists:
#   Round 5 audit found CI minutes burned because devs push, fail, retry. With
#   heavy workflows moved to a single 8am daily batch (codeql/semgrep/lighthouse
#   /perf-budget/license-check), devs lose the per-PR feedback loop. This script
#   restores it locally for free.
#
# Convention: every check here matches a step in .github/workflows/daily-batch.yml.
# If you add a check there, add it here (and vice versa).
#
# Usage:
#   bash .claude/scripts/local-pr-check.sh             # run all
#   bash .claude/scripts/local-pr-check.sh --quick     # only fast checks (<2min)
#   bash .claude/scripts/local-pr-check.sh --heavy     # only heavy (codeql/lighthouse/perf-budget)
#   bash .claude/scripts/local-pr-check.sh --only=semgrep,gitleaks
#
# Recommended: wire as pre-push hook
#   ln -s ../../.claude/scripts/local-pr-check.sh .git/hooks/pre-push

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-all}"          # all | --quick | --heavy | --only=...
ONLY=""
case "$MODE" in
  --quick) MODE=quick ;;
  --heavy) MODE=heavy ;;
  --only=*) MODE=only; ONLY="${1#--only=}" ;;
  all|"") MODE=all ;;
esac

PASS=0; FAIL=0; SKIP=0
LOG_DIR=".claude/hooks/.log/local-pr"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/last-run.json"
START_TS=$(date -Iseconds)

run_check() {
  local name="$1" tier="$2" cmd="$3"
  [ "$MODE" = "quick" ] && [ "$tier" != "quick" ] && { SKIP=$((SKIP+1)); return; }
  [ "$MODE" = "heavy" ] && [ "$tier" != "heavy" ] && { SKIP=$((SKIP+1)); return; }
  [ "$MODE" = "only" ] && ! echo ",$ONLY," | grep -q ",$name,"  && { SKIP=$((SKIP+1)); return; }

  printf '→ %-20s ' "$name"
  local log="$LOG_DIR/$name.log"
  if bash -c "$cmd" > "$log" 2>&1; then
    printf '✓\n'
    PASS=$((PASS+1))
  else
    printf '✗  (see %s)\n' "$log"
    FAIL=$((FAIL+1))
  fi
}

echo "→ Local PR check ($MODE) — mirrors .github/workflows/daily-batch.yml"
echo

# ─── Quick tier (<2 min total) — always recommended pre-push ────────────
run_check lint        quick "bash .claude/scripts/lint.sh"
run_check typecheck   quick "bash .claude/scripts/typecheck.sh"
run_check test-unit   quick "bash .claude/scripts/test-unit.sh"
run_check gitleaks    quick "command -v gitleaks >/dev/null && gitleaks detect --no-banner --redact --staged || echo 'gitleaks not installed; install: brew install gitleaks'"
run_check commitlint  quick "command -v commitlint >/dev/null && git log -1 --pretty=%B | commitlint || echo 'commitlint not installed; skipping'"
run_check harness     quick "bash .claude/scripts/validate.sh"

# ─── Heavy tier (~5-15 min) — what gets deferred to daily 8am batch ─────
run_check semgrep     heavy "command -v semgrep >/dev/null && semgrep --config=auto --error --quiet . || echo 'semgrep not installed; install: brew install semgrep'"
run_check codeql      heavy "command -v codeql >/dev/null && codeql database analyze --format=sarif-latest --output=/tmp/codeql.sarif --quiet . || echo 'codeql not installed; pulling from cache OR skip'"
run_check license     heavy "command -v licensee >/dev/null && licensee detect . || echo 'licensee not installed; skipping'"
run_check sbom        heavy "command -v cyclonedx-bom >/dev/null && cyclonedx-bom -o /tmp/sbom.json || echo 'cyclonedx-bom not installed; skipping'"
run_check coverage    heavy "bash .claude/scripts/verify.sh"
run_check test-integ  heavy "bash .claude/scripts/test-integration.sh"

# Lighthouse + perf-budget need a dev server — only run if explicitly requested
if [ "$MODE" = "heavy" ] || [ "$MODE" = "only" ]; then
  run_check lighthouse  heavy "command -v lighthouse >/dev/null && [ -f .lighthouserc.json ] && lighthouse --config-path=.lighthouserc.json --quiet || echo 'lighthouse/.lighthouserc not configured; skipping'"
  run_check perf-budget heavy "[ -f perf-budget.json ] && command -v perf-budget >/dev/null && perf-budget check || echo 'perf-budget not configured; skipping'"
fi

# ─── Summary ────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────────"
printf '✓ pass=%d  ✗ fail=%d  ⊘ skip=%d\n' "$PASS" "$FAIL" "$SKIP"

# Resolve git identity outside the JSON heredoc so the comments below stay valid shell.
# JUSTIFIED: git stderr suppressed — outside a repo / before first commit rev-parse fails, "unknown" is the documented report fallback
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
# JUSTIFIED: git stderr suppressed — detached/unborn branch yields no name, "unknown" is the documented report fallback
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

cat > "$SUMMARY" <<EOF
{
  "started_at": "$START_TS",
  "completed_at": "$(date -Iseconds)",
  "mode": "$MODE",
  "pass": $PASS,
  "fail": $FAIL,
  "skip": $SKIP,
  "git_sha": "$GIT_SHA",
  "git_branch": "$GIT_BRANCH"
}
EOF

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "✗ Local PR check failed. The daily 8am CI batch will fail on this state."
  echo "  Fix above, re-run, then push."
  exit 1
fi

if [ "$MODE" = "quick" ]; then
  echo
  echo "ℹ Heavy checks (codeql/semgrep/lighthouse/perf-budget) were skipped."
  echo "  The daily 8am batch will run them. To run locally now:"
  echo "    bash .claude/scripts/local-pr-check.sh --heavy"
fi

exit 0
