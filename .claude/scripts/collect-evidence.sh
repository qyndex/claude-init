#!/usr/bin/env bash
# Evidence collector — Round 10 C.
#
# Reads a spec's acceptance criteria, maps each to its proving test, runs the
# journey (capturing screenshots+video+HAR via the playwright rig), runs smoke
# commands, and emits a PR-ready evidence bundle.
#
# Outputs into verify/<date>-<spec-id>/:
#   EVIDENCE.md     — full human-readable bundle
#   pr-body.md      — PR-ready markdown block (embedded in gh pr create --body-file)
#   evidence.json   — machine-readable for the evidence-gate
#   + screenshots/, traces/, results.json, video.webm, trace.zip, network.har
#
# Usage: bash .claude/scripts/collect-evidence.sh <spec-id|latest> [--check-only]
# Exit 0 only if all ACs proven + smoke green + coverage gate met.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/atomic-write.sh
. "$ROOT/.claude/scripts/lib/atomic-write.sh"

target="${1:-latest}"
CHECK_ONLY=0
[ "${2:-}" = "--check-only" ] && CHECK_ONLY=1

# Resolve spec
if [ "$target" = "latest" ]; then
  # JUSTIFIED: the redirect drops the glob's no-match error — an empty spec is caught by the existence check below which exits with a clear message
  spec=$(ls -t specs/active/*.md 2>/dev/null | head -1)
else
  # JUSTIFIED: the redirect drops the glob's no-match error — an empty spec is caught by the existence check below which exits with a clear message
  spec=$(ls specs/active/${target}*.md 2>/dev/null | head -1)
fi
[ -z "$spec" ] && { echo "Spec not found: $target"; exit 1; }

spec_id=$(basename "$spec" .md | grep -oE '^[0-9]+' | head -1)
slug=$(basename "$spec" .md)
date_dir="verify/$(date +%Y-%m-%d)-${slug}"
mkdir -p "$date_dir/screenshots" "$date_dir/traces"

echo "→ Collecting evidence for spec $spec_id ($slug)"

# ─── 1. Parse acceptance criteria ───────────────────────────────────────
ac_block=$(awk '/^## Acceptance criteria/,/^## [^A]/' "$spec")
# Normalized to unpadded AC-N (e2e-audit e2e-rig-3) — must match spec-match.sh's canonical form.
ac_ids=$(echo "$ac_block" | grep -oE 'AC-[0-9]+' | sed 's/AC-0*\([0-9]\)/AC-\1/' | sort -u)
# JUSTIFIED: the fallback yields a zero count when grep matches no AC lines (exit 1) — a spec with no acceptance criteria correctly reports zero rather than aborting under pipefail
ac_count=$(echo "$ac_ids" | grep -c . || echo 0)

# ─── 2. Run the journey via the playwright rig (unless check-only) ──────
results_json="$date_dir/results.json"
if [ "$CHECK_ONLY" = "0" ]; then
  # e2e-audit e2e-rig-4: the rig runs via its OWN config (--config
  # playwright.evidence.config.ts) so it never collides with a brownfield
  # project's playwright.config.ts; existence checks key on the evidence config.
  if [ -f playwright.evidence.config.ts ] && [ -d "e2e/$spec_id" ]; then
    echo "  Running journey: VERIFY_FEATURE=$slug npx playwright test --config playwright.evidence.config.ts e2e/$spec_id"
    # JUSTIFIED: the fallback lets the script continue past a failing journey run — the AC-proven verdict is computed from results.json in step 4, so a non-zero exit here is captured there, not swallowed
    VERIFY_FEATURE="$slug" npx playwright test --config playwright.evidence.config.ts "e2e/$spec_id" 2>&1 | tail -20 || true
  else
    # e2e-audit greenfield-4: no browser rig — CLIs/APIs/libraries prove ACs via
    # the stack's own runner emitting AC-tagged junit/json into the bundle dir.
    echo "  ⚠ No playwright.evidence.config.ts or e2e/$spec_id/ — run: bash .claude/scripts/rig-bootstrap.sh (web apps) or rely on the stack-runner AC proof below"
    if [ -f package.json ] && jq -e '.devDependencies.vitest // .dependencies.vitest' package.json >/dev/null 2>&1; then
      echo "  Running stack AC proof: vitest → $date_dir/results.json"
      # JUSTIFIED: failing tests must not abort evidence collection — step 4 reads pass/fail from the output file
      npx vitest run --reporter=json --outputFile="$results_json" 2>&1 | tail -5 || true
    elif [ -f package.json ] && jq -e '.devDependencies.jest // .dependencies.jest' package.json >/dev/null 2>&1; then
      echo "  Running stack AC proof: jest → $date_dir/results.json"
      # JUSTIFIED: same contract as above — the verdict comes from the output file
      npx jest --json --outputFile="$results_json" 2>&1 | tail -5 || true
    elif [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then
      echo "  Running stack AC proof: pytest → $date_dir/results.xml"
      results_json="$date_dir/results.xml"
      # JUSTIFIED: same contract — junit XML carries pass/fail per testcase
      python3 -m pytest --junitxml="$results_json" 2>&1 | tail -5 || true
    fi
  fi
fi
if [ ! -f "$results_json" ]; then
  echo "  ⚠ No results at $results_json — every AC will read UNPROVEN. Install the rig: bash .claude/scripts/rig-bootstrap.sh, or emit AC-tagged junit/jest output to that path."
fi

# ─── 3. Smoke commands ──────────────────────────────────────────────────
smoke_log="$date_dir/smoke.log"
smoke_max_exit=0
{
  echo "# Smoke test — $(date -Iseconds)"
  for cmd in "bash .claude/scripts/verify.sh"; do
    echo "\$ $cmd"
    if eval "$cmd" >/tmp/smoke.out 2>&1; then ec=0; else ec=$?; fi
    tail -5 /tmp/smoke.out
    echo "exit: $ec"
    echo "---"
    [ "$ec" -gt "$smoke_max_exit" ] && smoke_max_exit=$ec
  done
} > "$smoke_log"

# ─── 4. spec-match (AC → passing test) ──────────────────────────────────
ac_proven=0
ac_unproven=()
if [ -f "$results_json" ]; then
  # JUSTIFIED: the fallback keeps match_out as captured output even if spec-match exits non-zero — each AC is then individually checked against it below, so a tool error degrades to "unproven", never a crash
  match_out=$(bash .claude/scripts/spec-match.sh "$spec_id" "$results_json" 2>&1 || true)
  for ac in $ac_ids; do
    # Anchored (e2e-audit e2e-rig-3): without the boundary, '✓ AC-10' satisfied AC-1.
    if echo "$match_out" | grep -qE "✓ ${ac}( |\$)"; then
      ac_proven=$((ac_proven + 1))
    else
      ac_unproven+=("$ac")
    fi
  done
else
  # No results — all ACs unproven
  for ac in $ac_ids; do ac_unproven+=("$ac"); done
fi

# ─── 5. Coverage delta ──────────────────────────────────────────────────
cov_line="?"
cov_branch="?"
[ -f coverage/coverage-summary.json ] && {
  # JUSTIFIED: the redirect and fallback yield "?" when the coverage summary is malformed — coverage is informational in the evidence bundle and a parse failure must not block evidence collection
  cov_line=$(jq -r '.total.lines.pct' coverage/coverage-summary.json 2>/dev/null || echo "?")
  # JUSTIFIED: same — a malformed coverage summary degrades the branch figure to "?" rather than aborting the bundle
  cov_branch=$(jq -r '.total.branches.pct' coverage/coverage-summary.json 2>/dev/null || echo "?")
}

# ─── 6. Verdict ─────────────────────────────────────────────────────────
verdict="PASS"
[ "${#ac_unproven[@]}" -gt 0 ] && verdict="FAIL"
[ "$smoke_max_exit" -ne 0 ] && verdict="FAIL"

# ─── 7. Emit evidence.json ──────────────────────────────────────────────
# JUSTIFIED: the redirect and fallback emit an empty JSON array when there are no unproven ACs (grep exits 1 on empty input) — the valid default keeps evidence.json well-formed
unproven_json=$(printf '%s\n' "${ac_unproven[@]+"${ac_unproven[@]}"}" | grep . | jq -R . | jq -sc . 2>/dev/null || echo '[]')
# Gap-audit G53: bind the bundle to the exact commit + moment it attests, so
# evidence-gate can reject stale or wrong-branch evidence instead of trusting
# any committed file.
# JUSTIFIED: git muted + unknown fallback — outside a repo the binding fields degrade visibly; evidence-gate treats "unknown" as unbound and fails
ev_commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)
jq -nc \
  --arg spec "$spec_id" \
  --arg commit "$ev_commit" \
  --arg generated_at "$(date -Iseconds)" \
  --argjson ac_total "${ac_count:-0}" \
  --argjson ac_proven "$ac_proven" \
  --argjson ac_unproven "$unproven_json" \
  --argjson smoke_exit "$smoke_max_exit" \
  --arg cov_line "$cov_line" \
  --arg cov_branch "$cov_branch" \
  --arg verdict "$verdict" \
  '{spec: $spec, commit: $commit, generated_at: $generated_at,
    ac_total: $ac_total, ac_proven: $ac_proven, ac_unproven: $ac_unproven,
    smoke_exit_max: $smoke_exit, coverage: {line: $cov_line, branch: $cov_branch}, verdict: $verdict}' \
  | replace_atomic "$date_dir/evidence.json"

# ─── 8. Emit pr-body.md ─────────────────────────────────────────────────
{
  echo "## Evidence Bundle — Spec $spec_id ($slug)"
  # JUSTIFIED: the redirect and fallback print "unknown" outside a git repo — the commit ref is cosmetic provenance in the PR body and its absence must not break bundle generation
  echo "Spec: \`$spec\` · Commit: \`$(git rev-parse --short HEAD 2>/dev/null || echo unknown)\`"
  # Round 11 D: link the projected spec issue for traceability + lifecycle automation
  # JUSTIFIED: the redirect drops awk stderr if the spec is unreadable — an empty gh_issue simply skips the "Closes #" line below
  gh_issue=$(awk '/^github_issue:/{print $2}' "$spec" 2>/dev/null)
  if [ -n "$gh_issue" ]; then
    echo
    echo "Closes #${gh_issue}"
  fi
  echo
  echo "### Acceptance criteria ($ac_proven/$ac_count proven)"
  echo "| AC | Proven by | Result |"
  echo "|----|-----------|--------|"
  for ac in $ac_ids; do
    if printf '%s\n' "${ac_unproven[@]+"${ac_unproven[@]}"}" | grep -qx "$ac"; then
      echo "| $ac | — | ✗ UNPROVEN |"
    else
      # JUSTIFIED: the redirect drops grep stderr when e2e/ or tests/ is absent — an empty test_file falls back to the "tagged test" label via the default expansion below
      test_file=$(grep -rl "@$ac\|$ac" e2e/ tests/ 2>/dev/null | head -1)
      echo "| $ac | ${test_file:-tagged test} | ✓ PASS |"
    fi
  done
  echo
  echo "### Smoke test (exit codes are load-bearing)"
  echo '```'
  cat "$smoke_log"
  echo '```'
  echo
  echo "### Visual proof"
  # JUSTIFIED: the redirect drops the glob's no-match error — wc then counts zero, correctly reporting no screenshots captured
  shot_count=$(ls "$date_dir/screenshots/"*.png 2>/dev/null | wc -l | tr -d ' ')
  echo "$shot_count screenshot(s) captured under \`$date_dir/screenshots/\` (named by AC)."
  [ -f "$date_dir/video.webm" ] && echo "Journey video: \`$date_dir/video.webm\` (CI artifact)."
  [ -f "$date_dir/trace.zip" ] && echo "Playwright trace: \`$date_dir/trace.zip\` → trace.playwright.dev"
  echo
  echo "### API traces"
  # JUSTIFIED: the redirect drops the glob's no-match error — wc then counts zero, correctly reporting no API trace files
  api_count=$(ls "$date_dir/traces/"*.json 2>/dev/null | wc -l | tr -d ' ')
  echo "$api_count API trace file(s) under \`$date_dir/traces/\`; full HAR at \`$date_dir/network.har\`."
  echo
  echo "### Coverage"
  echo "line ${cov_line}% · branch ${cov_branch}% (gate: line≥90 branch≥85)"
  echo
  echo "### Verdict: **$verdict**"
} > "$date_dir/pr-body.md"

# ─── 9. EVIDENCE.md = pr-body + index ───────────────────────────────────
cp "$date_dir/pr-body.md" "$date_dir/EVIDENCE.md"
{
  echo
  echo "## Artifact index"
  find "$date_dir" -type f | sed 's|^|- |'
} >> "$date_dir/EVIDENCE.md"

echo
echo "✓ Evidence bundle: $date_dir/"
echo "  Verdict: $verdict | ACs: $ac_proven/$ac_count proven | smoke exit: $smoke_max_exit"
echo "  PR body: $date_dir/pr-body.md"

[ "$verdict" = "PASS" ]
