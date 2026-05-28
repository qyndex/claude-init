#!/usr/bin/env bash
# Brownfield adoption — Phase 1: Archaeology (READ-ONLY). Round 14.
#
# The mandatory first phase. Builds an honest picture of a legacy repo WITHOUT writing a
# single line of its code (research: read-only archaeology before any change). Produces
# ADOPTION-REPORT.md for human review + the machine artifacts the later phases consume.
# Re-runnable; idempotent (overwrites its own outputs).
#
# Outputs (under .claude/state/adopt/ + repo root):
#   ADOPTION-REPORT.md                       human-facing summary (repo root)
#   .claude/state/adopt/hotspots.txt         top churn×LOC files (score|churn|loc|path)
#   .claude/state/adopt/uncharacterized-paths.txt   conservative legacy-zone globs (the safety manifest)
#   .claude/state/adopt/coverage-baseline.txt       raw coverage attempt output
#   .claude/memory/atlas/*                    via atlas-refresh.sh
#
# Every external probe is best-effort (|| true) so one missing tool never aborts the scan.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

STATE_DIR=".claude/state/adopt"; mkdir -p "$STATE_DIR"
REPORT="ADOPTION-REPORT.md"
HOTSPOTS="$STATE_DIR/hotspots.txt"
UNCHAR="$STATE_DIR/uncharacterized-paths.txt"
COV="$STATE_DIR/coverage-baseline.txt"
SRC_RE='\.(js|jsx|ts|tsx|py|go|rs|java|kt|rb|php|cs|swift|scala|c|cc|cpp|h|hpp|vue|svelte)$'
EXCLUDE_RE='(^|/)(node_modules|vendor|dist|build|\.next|target|\.venv|venv|__pycache__|\.git|coverage|migrations)/'

echo "→ Phase 1: Archaeology (read-only) for $(basename "$ROOT")"

# ─── 1. Atlas (stack + structure + entry points) ─────────────────────────
if [ -f .claude/scripts/atlas-refresh.sh ]; then
  bash .claude/scripts/atlas-refresh.sh >/dev/null 2>&1 || echo "  (atlas-refresh had warnings)"
fi
stacks="unknown"
if [ -f .claude/scripts/detect-stacks.sh ]; then
  stacks="$(bash .claude/scripts/detect-stacks.sh 2>/dev/null || echo '{}')"
fi

# ─── 2. Churn × LOC hotspots (LOC proxy for complexity — no new deps) ─────
: > "$HOTSPOTS"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # churn = how many commits touched the file; complexity ~ LOC. score = churn*loc.
  git log --pretty=format: --name-only 2>/dev/null \
    | grep -aE "$SRC_RE" | grep -avE "$EXCLUDE_RE" | sort | uniq -c | sort -rn | head -60 \
  | while read -r churn path; do
      [ -f "$path" ] || continue
      loc=$(grep -cve '^[[:space:]]*$' "$path" 2>/dev/null || echo 0)
      printf '%s|%s|%s|%s\n' "$(( churn * loc ))" "$churn" "$loc" "$path"
    done | sort -t'|' -k1 -rn | head -20 > "$HOTSPOTS"
  hotspot_note="top $(wc -l < "$HOTSPOTS" | tr -d ' ') by churn×LOC"
else
  hotspot_note="(not a git repo — churn unavailable)"
fi

# ─── 3. Conservative uncharacterized-paths manifest (the safety net) ──────
# Default: every source root that exists is OFF-LIMITS to autonomy until characterized.
# A human prunes this in Phase 2; Phase 4 removes paths as characterization tests land.
{
  echo "# Brownfield legacy-safety manifest — Round 14."
  echo "# Autopilot must NOT auto-modify files matching these globs until a characterization"
  echo "# test exists (verify.sh char gate enforces this). Remove a glob once its zone is"
  echo "# characterized. Empty/absent file = adoption complete, no restrictions."
  echo "# Edit conservatively in Phase 2 (/adopt reconcile)."
  for d in src lib app pkg internal cmd server client api services core domain; do
    [ -d "$d" ] && echo "${d}/**"
  done
  # If none of the common roots exist, flag the repo root's source files broadly.
  if ! ls -d src lib app pkg internal cmd server client api services core domain >/dev/null 2>&1; then
    echo "# (no conventional source root found — review STRUCTURE.md and add globs manually)"
  fi
} > "$UNCHAR"

# ─── 4. Dependency + vulnerability snapshot (best-effort) ─────────────────
deps_out="(deps-audit not run)"
if [ -f .claude/commands/deps-audit.md ] && [ -x .claude/scripts/detect-stacks.sh ]; then
  deps_out="See \`/deps-audit\` — run it for the live registry + OSV vuln report (stacks: $(echo "$stacks" | tr -d '\n' | head -c 200))."
fi

# ─── 5. Security snapshot (best-effort, read-only) ────────────────────────
sec_out="(semgrep not available)"
if command -v semgrep >/dev/null 2>&1; then
  sec_count=$(semgrep --config auto --quiet --json 2>/dev/null | jq '.results | length' 2>/dev/null || echo "?")
  sec_out="semgrep --config auto found ${sec_count} finding(s) (review before clearing false positives)."
fi
secrets_out="(gitleaks not available)"
command -v gitleaks >/dev/null 2>&1 && secrets_out="run \`gitleaks detect\` — confirm no committed secrets before adoption."

# ─── 6. Coverage baseline (best-effort — records the floor we must not drop below) ──
: > "$COV"
cov_summary="not captured (run the repo's own coverage command and record manually)"
test_fw="$(grep -iE 'jest|vitest|pytest|go test|cargo test|mocha|rspec' .claude/memory/atlas/STACK.md 2>/dev/null | head -1 || true)"
[ -n "$test_fw" ] && echo "detected test signal: $test_fw" >> "$COV"
echo "(coverage not auto-run — repo-specific; capture with the project's coverage command and paste here)" >> "$COV"

# ─── 7. Write ADOPTION-REPORT.md ──────────────────────────────────────────
hotspot_table=""
if [ -s "$HOTSPOTS" ]; then
  hotspot_table=$(awk -F'|' 'BEGIN{print "| Score | Churn | LOC | File |"; print "|---|---|---|---|"} {printf "| %s | %s | %s | `%s` |\n",$1,$2,$3,$4}' "$HOTSPOTS")
else
  hotspot_table="_$hotspot_note_"
fi

cat > "$REPORT" <<EOF
# Adoption Report — $(basename "$ROOT") — $(date +%Y-%m-%d)

> Generated by \`/adopt start\` (Phase 1: Archaeology). READ-ONLY — no code was modified.
> Review this, resolve every \`[OQ]\`, then run \`/adopt approve 1\` and \`/adopt reconcile\`.

## Executive summary
- Stacks detected: \`$(echo "$stacks" | tr -d '\n' | head -c 300)\`
- Hotspots: $hotspot_note
- Adoption risk: **REVIEW** — every source zone is treated as uncharacterized legacy until
  proven otherwise (see the safety manifest below). The factory will refuse to auto-modify
  these zones until characterization tests exist.

## Stack inventory
See \`.claude/memory/atlas/STACK.md\` (framework, ORM, test runner, idioms).

## Repo structure
See \`.claude/memory/atlas/STRUCTURE.md\` and \`KNOWN_ENTRIES.md\`.

## Hotspots (churn × LOC — most-changed, largest files; characterize these FIRST)
$hotspot_table

## Dependency & vulnerability audit
$deps_out

## Security scan
- SAST: $sec_out
- Secrets: $secrets_out

## Test / coverage baseline
$(cat "$COV")

## Legacy-safety manifest (.claude/state/adopt/uncharacterized-paths.txt)
These globs are OFF-LIMITS to autonomous modification until characterized:
\`\`\`
$(grep -vE '^[[:space:]]*#' "$UNCHAR" 2>/dev/null || true)
\`\`\`

## Existing \`.claude/\` collision map
Filled in by Phase 2 (\`/adopt reconcile\`) if the repo already had its own \`.claude/\`.

## Recommended migration strategies
Filled in by Phase 5 (\`/adopt backlog\`): per-hotspot strangler-fig / expand-contract /
codemod / sprout-method.

## Open questions (resolve before approving Phase 1)
- [OQ] Confirm the legacy-safety manifest globs above are correct (too broad? too narrow?).
- [OQ] What is the real current test-coverage % (the floor we must not regress)?
- [OQ] Any zones that must NEVER be touched by autonomy (compliance-frozen code)?

## Phase gate status
- [x] Phase 1 (Archaeology) — complete, awaiting human approval
- [ ] Phase 2 (Config reconciliation)
- [ ] Phase 3 (Knowledge import)
- [ ] Phase 4 (Baseline safety)
- [ ] Phase 5 (Remediation backlog)
- [ ] Phase 6 (Handoff)
EOF

# ─── 8. Advance state (self-initialize — this is the first phase) ─────────
if [ -f .claude/scripts/adopt-state.sh ]; then
  [ -f "$STATE_DIR/STATE.json" ] || bash .claude/scripts/adopt-state.sh init "$ROOT" >/dev/null 2>&1 || true
  bash .claude/scripts/adopt-state.sh set 1 archaeology >/dev/null 2>&1 || true
fi

echo "✓ Archaeology complete. Review $REPORT (and resolve [OQ]s), then: /adopt approve 1 → /adopt reconcile"
